"""Exchange ActiveSync client acting like the iOS Mail app or an Android mail app."""

import base64
import datetime
import email.message
import email.utils
import json
import struct
import time
import urllib.parse
import uuid
import xml.etree.ElementTree as ET
import zoneinfo

import items
import state
import transport
import wbxml
from profiles import PROFILES
from transport import HelperError

# Protocol versions this helper speaks; Z-Push (2.4.5 and 2.7.7) offers at most 14.1
SUPPORTED = ["14.0", "14.1"]
# Default folder type first; Z-Push lists WebTop's calendar and address book as user folders (13, 14)
CLASS_FOLDER_TYPES = {"Email": ["2"], "Calendar": ["8", "13"], "Contacts": ["9", "14"], "Tasks": ["7", "15"]}
RECURRENCE_TYPES = {"DAILY": "0", "WEEKLY": "1"}  # the rules the tests use; others raise
MAX_PAGES = 50  # a Sync that keeps saying MoreAvailable beyond this is broken
POLICY_STATUSES = {"142", "143", "144"}  # device not provisioned / policy refresh / invalid policy key
WINDOWS_TZ_NAMES = {"Europe/Rome": ("W. Europe Standard Time", "W. Europe Daylight Time")}


class NeedsProvision(Exception):
    pass


def _version_key(v):
    return tuple(int(x) for x in v.split("."))


def negotiate(server_versions, cap):
    offered = {v.strip() for v in server_versions.split(",")}
    beyond = [v for v in offered if v and _version_key(max(SUPPORTED, key=_version_key)) < _version_key(v) <= _version_key(cap)]
    if beyond:
        raise HelperError("server offers ActiveSync %s, which this phone would use but the helper does not speak"
                          % max(beyond, key=_version_key))
    usable = [v for v in SUPPORTED if v in offered and _version_key(v) <= _version_key(cap)]
    if not usable:
        raise HelperError("no common ActiveSync version: server offers %s" % server_versions)
    return max(usable, key=_version_key)


def el(parent, tag, text=None):
    e = ET.SubElement(parent, tag) if parent is not None else ET.Element(tag)
    e.text = text
    return e


# Request bodies

def provision_request(version, profile, temp_key=None):
    root = el(None, "Provision:Provision")
    if temp_key is None and _version_key(version) >= (14, 1):
        s = el(el(root, "Settings:DeviceInformation"), "Settings:Set")
        el(s, "Settings:Model", profile["device_type"])
        el(s, "Settings:FriendlyName", "phonesync " + profile["device_type"])
        el(s, "Settings:OS", profile["device_type"])
        el(s, "Settings:UserAgent", profile["user_agent"])
    policy = el(el(root, "Provision:Policies"), "Provision:Policy")
    el(policy, "Provision:PolicyType", "MS-EAS-Provisioning-WBXML")
    if temp_key is not None:
        el(policy, "Provision:PolicyKey", temp_key)
        el(policy, "Provision:Status", "1")
    return root


def timezone_blob(tz):
    """Base64 TIME_ZONE_INFORMATION for a zone with EU daylight saving rules, or UTC for None."""
    if tz is None:
        return base64.b64encode(bytes(172)).decode()
    zone = zoneinfo.ZoneInfo(tz)
    winter = datetime.datetime(2026, 1, 15, tzinfo=zone).utcoffset()
    summer = datetime.datetime(2026, 7, 15, tzinfo=zone).utcoffset()
    std_name, dst_name = WINDOWS_TZ_NAMES.get(tz, (tz, tz))

    def name(text):
        return text.encode("utf-16-le")[:64].ljust(64, b"\0")

    # SYSTEMTIME: year, month, day of week (0 = Sunday), week of month (5 = last), hour, minute, second, ms
    std_date = struct.pack("<8H", 0, 10, 0, 5, 3, 0, 0, 0)
    dst_date = struct.pack("<8H", 0, 3, 0, 5, 2, 0, 0, 0)
    bias = -int(winter.total_seconds() // 60)
    dst_bias = -int((summer - winter).total_seconds() // 60)
    blob = struct.pack("<l", bias) + name(std_name) + std_date + struct.pack("<l", 0) \
        + name(dst_name) + dst_date + struct.pack("<l", dst_bias)
    return base64.b64encode(blob).decode()


def parse_timezone(blob):
    """The parts of a base64 TIME_ZONE_INFORMATION that tests check, or None."""
    if not blob:
        return None
    raw = base64.b64decode(blob)
    bias, = struct.unpack_from("<l", raw, 0)
    std_month, = struct.unpack_from("<H", raw, 70)
    dst_month, = struct.unpack_from("<H", raw, 154)
    dst_bias, = struct.unpack_from("<l", raw, 168)
    return {"bias": bias, "dst_bias": dst_bias, "std_month": std_month, "dst_month": dst_month}


def _utc_compact(value, tz):
    """'2026-07-15T10:00:00' in tz, or '...Z' -> '20260715T080000Z'."""
    if value.endswith("Z"):
        dt = datetime.datetime.fromisoformat(value[:-1]).replace(tzinfo=datetime.timezone.utc)
    else:
        dt = datetime.datetime.fromisoformat(value).replace(tzinfo=zoneinfo.ZoneInfo(tz))
    return dt.astimezone(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def _iso_from_compact(value):
    if not value:
        return None
    return datetime.datetime.strptime(value, "%Y%m%dT%H%M%SZ").strftime("%Y-%m-%dT%H:%M:%SZ")


CONTACT_FIELDS = {"mobile": "Contacts:MobilePhoneNumber", "email": "Contacts:Email1Address",
                  "street": "Contacts:BusinessStreet", "city": "Contacts:BusinessCity"}


def contact_data(name, fields=None):
    fields = fields or {}
    data = el(None, "AirSync:ApplicationData")
    el(data, "Contacts:FileAs", name)
    el(data, "Contacts:FirstName", name)
    for key, tag in CONTACT_FIELDS.items():
        if fields.get(key):
            el(data, tag, fields[key])
    if fields.get("photo") in items.PHOTOS:
        el(data, "Contacts:Picture", base64.b64encode(items.PHOTOS[fields["photo"]]).decode())
    return data


def contact_fields(data):
    out = {key: wbxml.findtext(data, tag) or None for key, tag in CONTACT_FIELDS.items()}
    picture = wbxml.findtext(data, "Contacts:Picture")
    out["photo_size"] = len(base64.b64decode(picture)) if picture else 0
    return out


def _local_midnight(day, tz):
    dt = datetime.datetime.fromisoformat(day).replace(tzinfo=zoneinfo.ZoneInfo(tz or "UTC"))
    return dt.astimezone(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def _recurrence(parent, rrule, start_utc):
    parts = dict(p.split("=", 1) for p in rrule.split(";"))
    if parts.get("FREQ") not in RECURRENCE_TYPES or not set(parts) <= {"FREQ", "COUNT", "INTERVAL"}:
        raise HelperError("RRULE %s not supported by the helper" % rrule)
    rec = el(parent, "Calendar:Recurrence")
    el(rec, "Calendar:Type", RECURRENCE_TYPES[parts["FREQ"]])
    if "COUNT" in parts:
        el(rec, "Calendar:Occurrences", parts["COUNT"])
    el(rec, "Calendar:Interval", parts.get("INTERVAL", "1"))
    if parts["FREQ"] == "WEEKLY":
        weekday = datetime.datetime.strptime(start_utc, "%Y%m%dT%H%M%SZ").isoweekday() % 7  # Sunday = 0
        el(rec, "Calendar:DayOfWeek", str(1 << weekday))


def calendar_data(uid, name, start, end, tz, all_day=False, rrule=None, alarm=None):
    data = el(None, "AirSync:ApplicationData")
    el(data, "Calendar:Timezone", timezone_blob(tz))
    el(data, "Calendar:AllDayEvent", "1" if all_day else "0")
    el(data, "Calendar:BusyStatus", "2")
    el(data, "Calendar:DtStamp", datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ"))
    start_utc = _local_midnight(start, tz) if all_day else _utc_compact(start, tz)
    el(data, "Calendar:EndTime", _local_midnight(end, tz) if all_day else _utc_compact(end, tz))
    if alarm is not None:
        el(data, "Calendar:Reminder", str(alarm))
    el(data, "Calendar:Sensitivity", "0")
    el(data, "Calendar:Subject", name)
    el(data, "Calendar:StartTime", start_utc)
    el(data, "Calendar:UID", uid)
    el(data, "Calendar:MeetingStatus", "0")
    if rrule:
        _recurrence(data, rrule, start_utc)
    return data


def event_details(data):
    """all_day, start (local date for all-day, else UTC), rrule and alarm of an event."""
    all_day = wbxml.findtext(data, "Calendar:AllDayEvent") == "1"
    start = _iso_from_compact(wbxml.findtext(data, "Calendar:StartTime"))
    if all_day and start:
        # all-day events start at local midnight, always within 12 hours of UTC midnight
        start = (datetime.datetime.strptime(start, "%Y-%m-%dT%H:%M:%SZ") + datetime.timedelta(hours=12)).strftime("%Y-%m-%d")
    rrule = None
    rec = wbxml.find(data, "Calendar:Recurrence")
    if rec is not None:
        freq = {v: k for k, v in RECURRENCE_TYPES.items()}.get(wbxml.findtext(rec, "Calendar:Type"),
                                                               "TYPE" + str(wbxml.findtext(rec, "Calendar:Type")))
        rrule = "FREQ=" + freq
        if wbxml.findtext(rec, "Calendar:Occurrences"):
            rrule += ";COUNT=" + wbxml.findtext(rec, "Calendar:Occurrences")
        if wbxml.findtext(rec, "Calendar:Interval") not in (None, "", "1"):
            rrule += ";INTERVAL=" + wbxml.findtext(rec, "Calendar:Interval")
    reminder = wbxml.findtext(data, "Calendar:Reminder")
    return {"all_day": all_day, "start": start, "rrule": rrule, "alarm": int(reminder) if reminder else None}


def _eas_date(iso):
    """'2026-07-20T08:00:00Z' -> '2026-07-20T08:00:00.000Z' (ActiveSync task dates)."""
    return iso[:-1] + ".000Z"


def task_data(name, due, complete=False):
    data = el(None, "AirSync:ApplicationData")
    el(data, "Tasks:Complete", "1" if complete else "0")
    if complete:
        el(data, "Tasks:DateCompleted",
           datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z"))
    if due:
        el(data, "Tasks:DueDate", _eas_date(due))
        el(data, "Tasks:UtcDueDate", _eas_date(due))
    el(data, "Tasks:Importance", "1")
    el(data, "Tasks:Sensitivity", "0")
    el(data, "Tasks:Subject", name)
    return data


def item_name(data):
    for tag in ("Contacts:FileAs", "Calendar:Subject", "Email:Subject", "Tasks:Subject"):
        if wbxml.findtext(data, tag):
            return wbxml.findtext(data, tag)
    names = [wbxml.findtext(data, "Contacts:FirstName"), wbxml.findtext(data, "Contacts:LastName")]
    return " ".join(n for n in names if n) or None


def sendmail_request(client_id, mime):
    root = el(None, "ComposeMail:SendMail")
    el(root, "ComposeMail:ClientId", client_id)
    el(root, "ComposeMail:SaveInSentItems")
    el(root, "ComposeMail:Mime", mime)
    return root


# Client

class EasClient:
    def __init__(self, url, host, user, password, profile, state_path, post=None, insecure=False):
        self.url = url.rstrip("/")
        self.auth = {"user": user, "password": password, "host": host, "insecure": insecure}
        self.user = user
        self.profile = PROFILES[profile]
        self.state_path = state_path
        self.state = state.load(state_path)
        self.post = post or self._http_post
        self.reprovisioned = False
        self.timeout = 60

    def save(self):
        state.save(self.state_path, self.state)

    def _headers(self):
        return {"User-Agent": self.profile["user_agent"]}

    def _http_post(self, cmd, root):
        query = urllib.parse.urlencode({"Cmd": cmd, "User": self.user, "DeviceId": self.profile["device_id"],
                                        "DeviceType": self.profile["device_type"]})
        headers = self._headers()
        headers.update({"MS-ASProtocolVersion": self.state["protocol"],
                        "Content-Type": "application/vnd.ms-sync.wbxml",
                        "X-MS-PolicyKey": self.state.get("policy_key") or "0"})
        resp = transport.request("POST", "%s/Microsoft-Server-ActiveSync?%s" % (self.url, query),
                                 headers=headers, body=wbxml.encode(root) if root is not None else None,
                                 timeout=self.timeout, **self.auth)
        if resp.status == 449:
            raise NeedsProvision()
        if resp.status != 200:
            raise HelperError("%s: HTTP %d %s" % (cmd, resp.status, resp.body[:300]), resp.status)
        return wbxml.decode(resp.body) if resp.body else None

    def call(self, cmd, root):
        """post(), provisioning again when the server asks for it."""
        for attempt in range(2):
            try:
                reply = self.post(cmd, root)
            except NeedsProvision:
                reply = None
                needs = True
            else:
                needs = reply is not None and wbxml.findtext(reply, "{0}:Status".format(reply.tag.split(":")[0])) in POLICY_STATUSES
            if not needs:
                return reply
            if attempt == 0:
                self.provision()
                self.reprovisioned = True
        raise HelperError("%s: server keeps asking to provision" % cmd)

    # Account setup

    def setup(self):
        resp = transport.request("OPTIONS", self.url + "/Microsoft-Server-ActiveSync",
                                 headers=self._headers(), **self.auth)
        if resp.status != 200:
            raise HelperError("OPTIONS: HTTP %d" % resp.status, resp.status)
        self.state["protocol"] = negotiate(resp.headers.get("ms-asprotocolversions", ""), self.profile["max_protocol"])
        self.provision()
        self.folder_sync()
        self.save()
        return {"protocol": self.state["protocol"], "policy_key": self.state["policy_key"],
                "folders": self.state["folders"]}

    def provision(self):
        self.state["policy_key"] = None
        reply = self.post("Provision", provision_request(self.state["protocol"], self.profile))
        status = wbxml.findtext(reply, "Provision:Status")
        if status != "1":
            raise HelperError("Provision status %s" % status)
        policy = wbxml.find(reply, "Provision:Policies/Provision:Policy")
        temp_key = wbxml.findtext(policy, "Provision:PolicyKey") if policy is not None else None
        if not temp_key:  # server enforces no policy
            self.state["policy_key"] = "0"
            return
        self.state["policy_key"] = temp_key
        reply = self.post("Provision", provision_request(self.state["protocol"], self.profile, temp_key=temp_key))
        self.state["policy_key"] = wbxml.findtext(reply, ".//Provision:PolicyKey") or temp_key

    def folder_sync(self, retry=True):
        root = el(None, "FolderHierarchy:FolderSync")
        el(root, "FolderHierarchy:SyncKey", self.state.get("folder_sync_key") or "0")
        reply = self.call("FolderSync", root)
        status = wbxml.findtext(reply, "FolderHierarchy:Status")
        if status == "9" and retry:  # sync key out of date: start over, once
            self.state["folder_sync_key"] = None
            self.reprovisioned = True
            return self.folder_sync(retry=False)
        if status != "1":
            raise HelperError("FolderSync status %s" % status)
        folders = {f["id"]: f for f in self.state.get("folders", [])}
        for change in wbxml.find(reply, "FolderHierarchy:Changes") or []:
            tag = change.tag.split(":")[1]
            fid = wbxml.findtext(change, "FolderHierarchy:ServerId")
            if tag in ("Add", "Update"):
                folders[fid] = {"id": fid, "type": wbxml.findtext(change, "FolderHierarchy:Type"),
                                "name": wbxml.findtext(change, "FolderHierarchy:DisplayName")}
            elif tag == "Delete":
                folders.pop(fid, None)
        self.state["folders"] = list(folders.values())
        self.state["folder_sync_key"] = wbxml.findtext(reply, "FolderHierarchy:SyncKey")

    def ensure_setup(self):
        if not self.state.get("protocol") or self.state.get("policy_key") is None:
            self.setup()

    # Sync

    def class_state(self, cls):
        sync = self.state.setdefault("sync", {})
        if cls not in sync:
            folders = self.state.get("folders", [])
            folder = next((f for t in CLASS_FOLDER_TYPES[cls] for f in folders if f["type"] == t), None)
            if folder is None:
                raise HelperError("no %s folder" % cls)
            sync[cls] = {"collection_id": folder["id"], "sync_key": "0", "items": {}}
        return sync[cls]

    def _sync_request(self, cs, commands=None, window=None, get_changes=True):
        root = el(None, "AirSync:Sync")
        coll = el(el(root, "AirSync:Collections"), "AirSync:Collection")
        el(coll, "AirSync:SyncKey", cs["sync_key"])
        el(coll, "AirSync:CollectionId", cs["collection_id"])
        if cs["sync_key"] != "0":
            el(coll, "AirSync:GetChanges", None if get_changes else "0")
            if window:
                el(coll, "AirSync:WindowSize", str(window))
            if get_changes:
                pref = el(el(coll, "AirSync:Options"), "AirSyncBase:BodyPreference")
                el(pref, "AirSyncBase:Type", "1")
                el(pref, "AirSyncBase:TruncationSize", "10240")
        if commands is not None:
            coll.append(commands)
        return root

    def _collection(self, cs, root):
        reply = self.call("Sync", root)
        if reply is None:  # empty response: nothing changed
            return None
        coll = wbxml.find(reply, "AirSync:Collections/AirSync:Collection")
        if coll is None:
            raise HelperError("Sync status %s" % wbxml.findtext(reply, "AirSync:Status"))
        return coll

    def sync(self, cls, window=25):
        self.ensure_setup()
        cs = self.class_state(cls)
        out = {"added": [], "changed": [], "deleted": [], "full_resync": False, "status": 1,
               "pages": 0, "max_page": 0}
        seen = None  # server ids seen again during a full resync
        while True:
            if cs["sync_key"] == "0":
                coll = self._collection(cs, self._sync_request(cs))
                cs["sync_key"] = wbxml.findtext(coll, "AirSync:SyncKey")
            coll = self._collection(cs, self._sync_request(cs, window=window))
            if coll is None:
                break
            status = wbxml.findtext(coll, "AirSync:Status")
            if status == "3":  # invalid sync key: the phone must start over, once
                if seen is not None:
                    raise HelperError("Sync %s: sync key rejected again after a full resync" % cls)
                out["full_resync"] = True
                cs["sync_key"] = "0"
                seen = set()
                continue
            if status != "1":
                raise HelperError("Sync %s status %s" % (cls, status))
            cs["sync_key"] = wbxml.findtext(coll, "AirSync:SyncKey")
            commands = wbxml.find(coll, "AirSync:Commands")
            out["pages"] += 1
            out["max_page"] = max(out["max_page"], len(commands) if commands is not None else 0)
            self._apply_commands(cs, commands, out, seen)
            if wbxml.find(coll, "AirSync:MoreAvailable") is None:
                break
            if out["pages"] >= MAX_PAGES:
                raise HelperError("Sync %s: still MoreAvailable after %d pages" % (cls, MAX_PAGES))
        if seen is not None:
            for sid in [s for s in cs["items"] if s not in seen]:
                cs["items"].pop(sid)
                out["deleted"].append(sid)
        out["full_resync"] = out["full_resync"] or self.reprovisioned
        self.save()
        return out

    def lookup(self, cls, name):
        """The server id of the only item with this name the phone knows."""
        ids = [sid for sid, item in self.class_state(cls)["items"].items() if item.get("name") == name]
        if len(ids) != 1:
            raise HelperError("phone knows %d %s items named %r" % (len(ids), cls, name))
        return {"server_id": ids[0]}

    def _apply_commands(self, cs, commands, out, seen):
        for cmd in commands if commands is not None else []:
            kind = cmd.tag.split(":")[1]
            sid = wbxml.findtext(cmd, "AirSync:ServerId")
            if kind in ("Add", "Change"):
                data = wbxml.find(cmd, "AirSync:ApplicationData")
                item = self._item(data)
                tz = parse_timezone(wbxml.findtext(data, "Calendar:Timezone"))
                entry = {"server_id": sid, "name": item["name"], "start": item["start"],
                         "tz_bias": tz["bias"] if tz else None, "tz_dst_bias": tz["dst_bias"] if tz else None}
                if wbxml.find(data, "Contacts:FileAs") is not None or wbxml.find(data, "Contacts:FirstName") is not None:
                    entry["fields"] = contact_fields(data)
                if wbxml.find(data, "Calendar:StartTime") is not None:
                    entry["details"] = event_details(data)
                if wbxml.find(data, "Tasks:Subject") is not None:
                    entry["complete"], entry["due"] = item["complete"], item["due"]
                if seen is not None:
                    seen.add(sid)
                if kind == "Add" and sid not in cs["items"]:
                    out["added"].append(entry)
                elif kind == "Change" or cs["items"][sid].get("name") != item["name"]:
                    out["changed"].append(entry)
                cs["items"][sid] = item
            elif kind in ("Delete", "SoftDelete") and sid in cs["items"]:
                # like real phones, ignore deletes of items the phone never had
                cs["items"].pop(sid)
                out["deleted"].append(sid)

    @staticmethod
    def _item(data):
        """What the phone remembers about an item, enough to send a change later."""
        due = wbxml.findtext(data, "Tasks:UtcDueDate")
        return {"name": item_name(data), "uid": wbxml.findtext(data, "Calendar:UID"),
                "start": _iso_from_compact(wbxml.findtext(data, "Calendar:StartTime")),
                "end": _iso_from_compact(wbxml.findtext(data, "Calendar:EndTime")),
                "due": due.replace(".000Z", "Z") if due else None,
                "complete": wbxml.findtext(data, "Tasks:Complete") == "1"}

    def _write(self, cs, command):
        if cs["sync_key"] == "0":
            raise HelperError("sync the collection before changing it")
        commands = el(None, "AirSync:Commands")
        commands.append(command)
        coll = self._collection(cs, self._sync_request(cs, commands=commands, get_changes=False))
        if coll is None:
            raise HelperError("Sync write: empty reply from the server")
        if wbxml.findtext(coll, "AirSync:Status") != "1":
            raise HelperError("Sync write status %s" % wbxml.findtext(coll, "AirSync:Status"))
        cs["sync_key"] = wbxml.findtext(coll, "AirSync:SyncKey")
        return coll

    def add(self, cls, name, start=None, end=None, tz=None, client_id=None, fields=None,
            all_day=False, rrule=None, alarm=None, due=None, complete=False):
        self.ensure_setup()
        cs = self.class_state(cls)
        client_id = client_id or uuid.uuid4().hex
        add = el(None, "AirSync:Add")
        el(add, "AirSync:ClientId", client_id)
        if cls == "Contacts":
            data = contact_data(name, fields)
        elif cls == "Tasks":
            data = task_data(name, due, complete)
        else:
            data = calendar_data(str(uuid.uuid4()), name, start, end, tz, all_day=all_day, rrule=rrule, alarm=alarm)
        add.append(data)
        coll = self._write(cs, add)
        resp = wbxml.find(coll, "AirSync:Responses/AirSync:Add")
        if resp is None or wbxml.findtext(resp, "AirSync:Status") != "1":
            raise HelperError("Add status %s" % (wbxml.findtext(resp, "AirSync:Status") if resp is not None else "missing"))
        sid = wbxml.findtext(resp, "AirSync:ServerId")
        cs["items"][sid] = self._item(data)
        self.save()
        return sid

    def change(self, cls, server_id, name=None, complete=False, fields=None):
        self.ensure_setup()
        cs = self.class_state(cls)
        item = cs["items"].get(server_id)
        if item is None:
            raise HelperError("unknown %s item %s: sync first" % (cls, server_id))
        change = el(None, "AirSync:Change")
        el(change, "AirSync:ServerId", server_id)
        name = name or item["name"]
        if cls == "Contacts":
            data = contact_data(name, fields)
        elif cls == "Tasks":
            data = task_data(name, item.get("due"), complete or item.get("complete"))
        else:
            data = calendar_data(item.get("uid") or str(uuid.uuid4()), name, item.get("start"), item.get("end"), None)
        change.append(data)
        coll = self._write(cs, change)
        resp = wbxml.find(coll, "AirSync:Responses/AirSync:Change")
        if resp is not None and wbxml.findtext(resp, "AirSync:Status") != "1":
            raise HelperError("Change status %s" % wbxml.findtext(resp, "AirSync:Status"))
        cs["items"][server_id] = self._item(data)
        self.save()
        return {}

    def delete(self, cls, server_id):
        self.ensure_setup()
        cs = self.class_state(cls)
        delete = el(None, "AirSync:Delete")
        el(delete, "AirSync:ServerId", server_id)
        coll = self._write(cs, delete)
        resp = wbxml.find(coll, "AirSync:Responses/AirSync:Delete")
        if resp is not None and wbxml.findtext(resp, "AirSync:Status") != "1":
            raise HelperError("Delete status %s" % wbxml.findtext(resp, "AirSync:Status"))
        cs["items"].pop(server_id, None)
        self.save()
        return {}

    # Push

    def ping(self, classes, heartbeat):
        """Wait like a phone for changes in the synced folders of these classes."""
        self.ensure_setup()
        root = el(None, "Ping:Ping")
        el(root, "Ping:LifeTime", str(heartbeat))
        folders = el(root, "Ping:Folders")
        for cls in classes:
            cs = self.state.get("sync", {}).get(cls)
            if not cs or cs["sync_key"] == "0":
                raise HelperError("sync %s before pinging it" % cls)
            folder = el(folders, "Ping:Folder")
            el(folder, "Ping:ServerEntryId", cs["collection_id"])
            el(folder, "Ping:FolderType", cls)
        self.timeout = heartbeat + 30
        started = time.monotonic()
        reply = self.call("Ping", root)
        seconds = time.monotonic() - started
        status = int(wbxml.findtext(reply, "Ping:Status") or 0)
        changed = [f.text for f in (wbxml.find(reply, "Ping:Folders") or [])]
        return {"status": status, "folders": changed, "seconds": round(seconds, 1) + 0.0}

    # Mail

    def fetch(self, server_id):
        self.ensure_setup()
        cs = self.class_state("Email")
        root = el(None, "ItemOperations:ItemOperations")
        fetch = el(root, "ItemOperations:Fetch")
        el(fetch, "ItemOperations:Store", "Mailbox")
        el(fetch, "AirSync:CollectionId", cs["collection_id"])
        el(fetch, "AirSync:ServerId", server_id)
        pref = el(el(fetch, "ItemOperations:Options"), "AirSyncBase:BodyPreference")
        el(pref, "AirSyncBase:Type", "1")
        reply = self.call("ItemOperations", root)
        result = wbxml.find(reply, "ItemOperations:Response/ItemOperations:Fetch")
        if result is None or wbxml.findtext(result, "ItemOperations:Status") != "1":
            raise HelperError("ItemOperations fetch failed")
        props = wbxml.find(result, "ItemOperations:Properties")
        return {"subject": wbxml.findtext(props, "Email:Subject"),
                "body": (wbxml.findtext(props, "AirSyncBase:Body/AirSyncBase:Data") or "").strip()}

    def send(self, to, subject, body):
        self.ensure_setup()
        msg = email.message.EmailMessage()
        msg["From"] = self.user
        msg["To"] = to
        msg["Subject"] = subject
        msg["Date"] = email.utils.formatdate()
        msg["Message-ID"] = email.utils.make_msgid()
        msg.set_content(body)
        reply = self.call("SendMail", sendmail_request(uuid.uuid4().hex, msg.as_bytes()))
        if reply is not None and wbxml.findtext(reply, "ComposeMail:Status") not in (None, "1"):
            raise HelperError("SendMail status %s" % wbxml.findtext(reply, "ComposeMail:Status"))
        return {}


def run(args):
    client = EasClient(args.url, args.host, args.user, args.password, args.profile, args.state,
                       insecure=args.insecure)
    if args.command == "setup":
        return client.setup()
    if args.command == "sync":
        return client.sync(args.cls, args.window)
    if args.command == "add":
        return {"server_id": client.add(args.cls, args.name, args.start, args.end, args.tz,
                                        fields=json.loads(args.fields) if args.fields else None,
                                        all_day=args.all_day, rrule=args.rrule, alarm=args.alarm,
                                        due=args.due, complete=args.complete)}
    if args.command == "change":
        return client.change(args.cls, args.server_id, args.name, complete=args.complete,
                             fields=json.loads(args.fields) if args.fields else None)
    if args.command == "delete":
        return client.delete(args.cls, args.server_id)
    if args.command == "fetch":
        return client.fetch(args.server_id)
    if args.command == "lookup":
        return client.lookup(args.cls, args.name)
    if args.command == "ping":
        return client.ping(args.classes.split(","), args.heartbeat)
    if args.command == "send":
        return client.send(args.to, args.subject, args.body)
    raise HelperError("unknown eas command %s" % args.command)
