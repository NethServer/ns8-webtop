"""Server-side changes through the WebTop Java REST API, the same one the PHP services call."""

import datetime
import json
import subprocess
import uuid

import items
import transport
from transport import HelperError

CONTACTS_API = "/webtop/api/com.sonicle.webtop.contacts/v1/carddav/addressbooks"
CALENDAR_API = "/webtop/api/com.sonicle.webtop.calendar/v1/caldav/calendars"
TASKS_API = "/webtop/api/com.sonicle.webtop.tasks/v2/eas/folders"
TASK_FIELDS = ("subject", "start", "due", "complOn", "impo", "prvt", "notes")


def _compact(iso):
    """'2026-07-20T08:00:00Z' -> '20260720T080000Z' (the tasks API date format)."""
    return iso.replace("-", "").replace(":", "") if iso else None


class WebTop:
    def __init__(self, url, host, user, password, module):
        self.url = url.rstrip("/")
        self.auth = {"user": user, "password": password, "host": host}
        self.user = user
        self.user_id = user.split("@")[0]
        self.module = module

    def sql(self, query, *params):
        """Rows of a WebTop database query; params are bound as psql variables :'p1', :'p2', ..."""
        cmd = ["runagent", "-m", self.module, "podman", "exec", "-i", "postgres",
               "psql", "-U", "postgres", "-tA", "-F", "\t", "-v", "ON_ERROR_STOP=1", "webtop5"]
        for i, value in enumerate(params, 1):
            cmd += ["-v", "p%d=%s" % (i, value)]
        out = subprocess.run(cmd, input=query, capture_output=True, text=True)
        if out.returncode != 0:
            raise HelperError("psql: " + out.stderr.strip())
        return [line.split("\t") for line in out.stdout.splitlines() if line]

    def call(self, method, path, body=None, content_type="application/json"):
        headers = {"Accept": "application/json"}
        if body is not None:
            headers["Content-Type"] = content_type
            if not isinstance(body, bytes):
                body = (json.dumps(body) if content_type == "application/json" else body).encode("utf-8")
        resp = transport.request(method, self.url + path, headers=headers, body=body, **self.auth)
        if resp.status >= 300:
            raise HelperError("%s %s: HTTP %d %s" % (method, path, resp.status, resp.body[:300]), resp.status)
        return json.loads(resp.body) if resp.body.strip() else None

    # Address books and calendars

    def addressbook(self):
        books = [b for b in self.call("GET", CONTACTS_API) if b.get("ownerUsername", self.user) == self.user]
        if not books:
            raise HelperError("user %s has no address book" % self.user)
        return books[0]["uid"]

    def calendar(self):
        cals = [c for c in self.call("GET", CALENDAR_API) if c.get("ownerUsername", self.user) == self.user]
        if not cals:
            raise HelperError("user %s has no calendar" % self.user)
        return cals[0]["uid"]

    # Items, looked up by name in the database (the REST listing of calendar objects fails, see webtop_server.resource)

    def _contact(self, name):
        """(href, public_uid) of the user's only contact with this name."""
        rows = self.sql("SELECT c.href, c.public_uid FROM contacts.contacts c JOIN contacts.categories k USING (category_id) "
                        "WHERE k.user_id = :'p1' AND c.display_name = :'p2' AND c.revision_status <> 'D'",
                        self.user_id, name)
        if len(rows) != 1:
            raise HelperError("expected one contact named %r, found %d" % (name, len(rows)))
        return rows[0]

    def _event(self, name):
        """(href, public_uid, start, end) of the user's only event with this name; times in UTC."""
        rows = self.sql("SELECT e.href, e.public_uid, "
                        "to_char(e.start AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"'), "
                        "to_char(e.\"end\" AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') "
                        "FROM calendar.events e JOIN calendar.calendars c USING (calendar_id) "
                        "WHERE c.user_id = :'p1' AND e.title = :'p2' AND e.revision_status <> 'D'",
                        self.user_id, name)
        if len(rows) != 1:
            raise HelperError("expected one event named %r, found %d" % (name, len(rows)))
        return rows[0]

    def contact_create(self, name):
        uid = str(uuid.uuid4())
        href = uid + ".vcf"
        self.call("POST", "%s/%s/cards" % (CONTACTS_API, self.addressbook()), {"href": href, "vcard": items.vcard(uid, name)})
        return {"href": href, "uid": uid}

    # Changes rebuild the item from the database: the REST API cannot read single calendar objects back

    def contact_rename(self, name, new_name):
        href, uid = self._contact(name)
        base = "%s/%s/cards" % (CONTACTS_API, self.addressbook())
        self.call("PUT", "%s/%s" % (base, href), items.vcard(uid, new_name), "text/vcard")
        return {}

    def contact_delete(self, name):
        href, _ = self._contact(name)
        self.call("DELETE", "%s/%s/cards/%s" % (CONTACTS_API, self.addressbook(), href))
        return {}

    def event_create(self, name, start, end, tz):
        uid = str(uuid.uuid4())
        href = uid + ".ics"
        body = {"href": href, "icalendar": items.event(uid, name, start, end, tz)}
        self.call("POST", "%s/%s/objects" % (CALENDAR_API, self.calendar()), body)
        return {"href": href, "uid": uid}

    def event_rename(self, name, new_name):
        href, uid, start, end = self._event(name)
        base = "%s/%s/objects" % (CALENDAR_API, self.calendar())
        self.call("PUT", "%s/%s" % (base, href), items.event(uid, new_name, start, end, None), "text/calendar")
        return {}

    def event_delete(self, name):
        href = self._event(name)[0]
        self.call("DELETE", "%s/%s/objects/%s" % (CALENDAR_API, self.calendar(), href))
        return {}

    # Tasks, through the REST API the ActiveSync tasks backend uses

    def task_folder(self):
        folders = [f for f in self.call("GET", TASKS_API) if f.get("deflt")]
        if not folders:
            raise HelperError("user %s has no default task folder" % self.user)
        return folders[0]["id"]

    def _task_id(self, name):
        rows = self.sql("SELECT t.task_id FROM tasks.tasks t JOIN tasks.categories k USING (category_id) "
                        "WHERE k.user_id = :'p1' AND t.subject = :'p2' AND t.revision_status <> 'D'",
                        self.user_id, name)
        if len(rows) != 1:
            raise HelperError("expected one task named %r, found %d" % (name, len(rows)))
        return rows[0][0]

    def _task_update(self, name, **changes):
        path = "%s/%s/messages/%s" % (TASKS_API, self.task_folder(), self._task_id(name))
        task = {k: v for k, v in self.call("GET", path).items() if k in TASK_FIELDS}
        task.update(changes)
        self.call("PUT", path, task)
        return {}

    def task_create(self, name, due):
        body = {"subject": name, "due": _compact(due), "impo": 5, "prvt": False, "notes": ""}
        return self.call("POST", "%s/%s/messages" % (TASKS_API, self.task_folder()), body)

    def task_rename(self, name, new_name):
        return self._task_update(name, subject=new_name)

    def task_complete(self, name):
        now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        return self._task_update(name, complOn=now)

    def task_delete(self, name):
        self.call("DELETE", "%s/%s/messages/%s" % (TASKS_API, self.task_folder(), self._task_id(name)))
        return {}

    def cleanup(self, prefix):
        """Delete every contact and event of the user whose name starts with prefix."""
        contacts = self.sql("SELECT c.href FROM contacts.contacts c JOIN contacts.categories k USING (category_id) "
                            "WHERE k.user_id = :'p1' AND c.revision_status <> 'D' AND starts_with(c.display_name, :'p2')",
                            self.user_id, prefix)
        events = self.sql("SELECT e.href FROM calendar.events e JOIN calendar.calendars c USING (calendar_id) "
                          "WHERE c.user_id = :'p1' AND e.revision_status <> 'D' AND starts_with(e.title, :'p2')",
                          self.user_id, prefix)
        if contacts:
            base = "%s/%s/cards" % (CONTACTS_API, self.addressbook())
            for (href,) in contacts:
                self.call("DELETE", "%s/%s" % (base, href))
        if events:
            base = "%s/%s/objects" % (CALENDAR_API, self.calendar())
            for (href,) in events:
                self.call("DELETE", "%s/%s" % (base, href))
        tasks = self.sql("SELECT t.task_id FROM tasks.tasks t JOIN tasks.categories k USING (category_id) "
                         "WHERE k.user_id = :'p1' AND t.revision_status <> 'D' AND starts_with(t.subject, :'p2')",
                         self.user_id, prefix)
        if tasks:
            folder = self.task_folder()
            for (task_id,) in tasks:
                self.call("DELETE", "%s/%s/messages/%s" % (TASKS_API, folder, task_id))
        return {"removed": len(contacts) + len(events) + len(tasks)}

def run(args):
    wt = WebTop(args.url, args.host, args.user, args.password, args.module)
    if args.command == "contact-create":
        return wt.contact_create(args.name)
    if args.command == "contact-rename":
        return wt.contact_rename(args.name, args.new_name)
    if args.command == "contact-delete":
        return wt.contact_delete(args.name)
    if args.command == "event-create":
        return wt.event_create(args.name, args.start, args.end, args.tz)
    if args.command == "event-rename":
        return wt.event_rename(args.name, args.new_name)
    if args.command == "event-delete":
        return wt.event_delete(args.name)
    if args.command == "task-create":
        return wt.task_create(args.name, args.due)
    if args.command == "task-rename":
        return wt.task_rename(args.name, args.new_name)
    if args.command == "task-complete":
        return wt.task_complete(args.name)
    if args.command == "task-delete":
        return wt.task_delete(args.name)
    if args.command == "cleanup":
        return wt.cleanup(args.name)
    raise HelperError("unknown webtop command %s" % args.command)
