"""CalDAV/CardDAV client acting like DAVx5 (sync-collection) or iOS (ctag + etag polling)."""

import urllib.parse
import uuid
import xml.etree.ElementTree as ET

import items
import state
import transport
from profiles import PROFILES
from transport import HelperError

D = "{DAV:}"
CS = "{http://calendarserver.org/ns/}"
CAL = "{urn:ietf:params:xml:ns:caldav}"
CARD = "{urn:ietf:params:xml:ns:carddav}"

KINDS = {
    "contact": {"wellknown": "/.well-known/carddav", "ext": ".vcf", "type": "text/vcard; charset=utf-8",
                "multiget": "card:addressbook-multiget", "data": "card:address-data"},
    "event": {"wellknown": "/.well-known/caldav", "ext": ".ics", "type": "text/calendar; charset=utf-8",
              "multiget": "c:calendar-multiget", "data": "c:calendar-data"},
}
XMLNS = 'xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/" ' \
        'xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:card="urn:ietf:params:xml:ns:carddav"'


# Parsing

def _responses(body):
    """(href, {tag: element}) for each response, with only the properties found (200 OK)."""
    out = []
    for resp in ET.fromstring(body).findall(D + "response"):
        href = urllib.parse.unquote(resp.findtext(D + "href"))
        props = {}
        status = resp.findtext(D + "status")
        for propstat in resp.findall(D + "propstat"):
            if " 200 " in (propstat.findtext(D + "status") or ""):
                for prop in propstat.find(D + "prop"):
                    props[prop.tag] = prop
        out.append((href, props, status))
    return out


def principal_href(body):
    for _, props, _ in _responses(body):
        if D + "current-user-principal" in props:
            return props[D + "current-user-principal"].findtext(D + "href")
    raise HelperError("no current-user-principal")


def home_sets(body):
    _, props, _ = _responses(body)[0]
    return (props[CAL + "calendar-home-set"].findtext(D + "href"),
            props[CARD + "addressbook-home-set"].findtext(D + "href"))


def collections(body, kind):
    out = []
    for href, props, _ in _responses(body):
        rtype = props.get(D + "resourcetype")
        if rtype is None:
            continue
        if kind == "contact" and rtype.find(CARD + "addressbook") is None:
            continue
        if kind == "event":
            comps = props.get(CAL + "supported-calendar-component-set")
            if rtype.find(CAL + "calendar") is None or (
                    comps is not None and "VEVENT" not in [c.get("name") for c in comps]):
                continue
        out.append({"href": href,
                    "displayname": props[D + "displayname"].text if D + "displayname" in props else None,
                    "ctag": props[CS + "getctag"].text if CS + "getctag" in props else None,
                    "sync_token": props[D + "sync-token"].text if D + "sync-token" in props else None})
    return out


def etags(body):
    return {href: props[D + "getetag"].text for href, props, _ in _responses(body) if D + "getetag" in props}


def sync_result(body):
    """({href: etag, or None when deleted}, new sync token) of a sync-collection report."""
    changes = {}
    for href, props, status in _responses(body):
        if status and " 404 " in status:
            changes[href] = None
        elif D + "getetag" in props:
            changes[href] = props[D + "getetag"].text
    return changes, ET.fromstring(body).findtext(D + "sync-token")


def is_invalid_sync_token(status, body):
    return status in (403, 409) and b"valid-sync-token" in body


def multiget(body):
    out = {}
    for href, props, _ in _responses(body):
        data = props.get(CARD + "address-data", props.get(CAL + "calendar-data"))
        if data is not None:
            out[href] = (props[D + "getetag"].text if D + "getetag" in props else None, data.text)
    return out


def diff(known, listing, complete):
    """(added, changed, deleted) hrefs of a listing {href: etag or None} against known {href: {"etag"}}.

    complete: the listing holds the whole collection, so known hrefs missing from it were deleted.
    """
    added = sorted(h for h, e in listing.items() if e is not None and h not in known)
    changed = sorted(h for h, e in listing.items() if e is not None and h in known and known[h]["etag"] != e)
    deleted = {h for h, e in listing.items() if e is None and h in known}
    if complete:
        deleted |= {h for h in known if h not in listing}
    return added, changed, sorted(deleted)


# Client

class DavClient:
    def __init__(self, url, host, user, password, profile, state_path):
        self.url = url.rstrip("/")
        self.auth = {"user": user, "password": password, "host": host}
        self.profile = PROFILES[profile]
        self.state_path = state_path
        self.state = state.load(state_path)

    def req(self, method, path, body=None, headers=None, ok=(200, 201, 204, 207)):
        all_headers = {"User-Agent": self.profile["user_agent"]}
        if body is not None and "Content-Type" not in (headers or {}):
            all_headers["Content-Type"] = "application/xml; charset=utf-8"
        all_headers.update(headers or {})
        if isinstance(body, str):
            body = body.encode("utf-8")
        resp = transport.request(method, self.url + path, headers=all_headers, body=body, **self.auth)
        if ok and resp.status not in ok:
            raise HelperError("%s %s: HTTP %d %s" % (method, path, resp.status, resp.body[:300]), resp.status)
        return resp

    def propfind(self, path, depth, props):
        body = '<?xml version="1.0" encoding="utf-8"?><d:propfind %s><d:prop>%s</d:prop></d:propfind>' % (XMLNS, props)
        return self.req("PROPFIND", path, body, {"Depth": str(depth)}).body

    def save(self):
        state.save(self.state_path, self.state)

    def discover(self):
        homes = {}
        result = {}
        for kind in ("event", "contact"):
            resp = self.req("PROPFIND", KINDS[kind]["wellknown"], ok=(301, 302, 307, 308))
            start = urllib.parse.urlparse(resp.headers["location"]).path
            principal = principal_href(self.propfind(start, 0, "<d:current-user-principal/>"))
            homes["event"], homes["contact"] = home_sets(self.propfind(
                principal, 0, "<c:calendar-home-set/><card:addressbook-home-set/>"))
            found = collections(self.propfind(
                homes[kind], 1, "<d:resourcetype/><d:displayname/><cs:getctag/><d:sync-token/>"
                "<c:supported-calendar-component-set/>"), kind)
            if not found:
                raise HelperError("no %s collection in %s" % (kind, homes[kind]))
            self.state.setdefault(kind, {"sync_token": None, "ctag": None, "items": {}})["collection"] = found[0]["href"]
            result["principal"] = principal
            result["calendars" if kind == "event" else "addressbooks"] = found
        result["calendar_home"], result["addressbook_home"] = homes["event"], homes["contact"]
        self.save()
        return result

    def kind_state(self, kind):
        if "collection" not in self.state.get(kind, {}):
            self.discover()
        return self.state[kind]

    def _etag(self, path, resp):
        etag = resp.headers.get("etag")
        if etag:
            return etag
        return etags(self.propfind(path, 0, "<d:getetag/>")).get(path)

    def put(self, kind, name, start=None, end=None, tz=None):
        ks = self.kind_state(kind)
        uid = str(uuid.uuid4())
        href = ks["collection"] + uid + KINDS[kind]["ext"]
        data = items.vcard(uid, name) if kind == "contact" else items.event(uid, name, start, end, tz)
        resp = self.req("PUT", href, data, {"Content-Type": KINDS[kind]["type"], "If-None-Match": "*"})
        etag = self._etag(href, resp)
        ks["items"][href] = {"etag": etag, "uid": uid, "name": name}
        self.save()
        return {"href": href, "uid": uid, "etag": etag}

    def get(self, href):
        resp = self.req("GET", href, ok=(200,))
        data = resp.body.decode("utf-8")
        start = items.parse_start(data)
        return {"etag": resp.headers.get("etag"), "name": items.parse_name(data),
                "start": start[0] if start else None, "tz": start[1] if start else None}

    def _owner(self, href):
        kind = "contact" if href.endswith(KINDS["contact"]["ext"]) else "event"
        return kind, self.kind_state(kind)

    def update(self, href, name):
        kind, ks = self._owner(href)
        resp = self.req("GET", href, ok=(200,))
        data = items.with_name(resp.body.decode("utf-8"), name)
        resp = self.req("PUT", href, data, {"Content-Type": KINDS[kind]["type"], "If-Match": resp.headers["etag"]})
        etag = self._etag(href, resp)
        ks["items"].setdefault(href, {})
        ks["items"][href].update({"etag": etag, "name": name})
        self.save()
        return {"etag": etag}

    def delete(self, href):
        _, ks = self._owner(href)
        headers = {}
        if href in ks["items"] and ks["items"][href].get("etag"):
            headers["If-Match"] = ks["items"][href]["etag"]
        self.req("DELETE", href, headers=headers)
        ks["items"].pop(href, None)
        self.save()
        return {}

    def sync(self, kind):
        ks = self.kind_state(kind)
        full_resync = False
        if self.profile["strategy"] == "sync-collection":
            listing, complete, full_resync = self._sync_collection(ks)
        else:
            listing, complete = self._ctag_listing(kind, ks)
        added, changed, deleted = diff(ks["items"], listing, complete)
        fetched = self._multiget(kind, ks["collection"], added + changed)
        out = {"added": [], "changed": [], "deleted": deleted, "full_resync": full_resync}
        for key, hrefs in (("added", added), ("changed", changed)):
            for href in hrefs:
                etag, data = fetched.get(href, (listing[href], None))
                name = items.parse_name(data) if data else None
                ks["items"][href] = {"etag": etag or listing[href], "uid": None, "name": name}
                out[key].append({"href": href, "uid": None, "name": name})
        for href in deleted:
            ks["items"].pop(href, None)
        self.save()
        return out

    def _sync_collection(self, ks):
        def report(token):
            body = ('<?xml version="1.0" encoding="utf-8"?><d:sync-collection %s><d:sync-token>%s</d:sync-token>'
                    '<d:sync-level>1</d:sync-level><d:prop><d:getetag/></d:prop></d:sync-collection>'
                    % (XMLNS, token or ""))
            return self.req("REPORT", ks["collection"], body, {"Depth": "1"}, ok=None)

        resp = report(ks.get("sync_token"))
        full_resync = False
        if is_invalid_sync_token(resp.status, resp.body):
            full_resync = True
            resp = report(None)
        if resp.status != 207:
            raise HelperError("sync-collection: HTTP %d %s" % (resp.status, resp.body[:300]), resp.status)
        complete = full_resync or not ks.get("sync_token")
        listing, ks["sync_token"] = sync_result(resp.body)
        return listing, complete, full_resync

    def _ctag_listing(self, kind, ks):
        found = collections(self.propfind(ks["collection"], 0, "<d:resourcetype/><cs:getctag/>"
                                          "<c:supported-calendar-component-set/>"), kind)
        ctag = found[0]["ctag"] if found else None
        if ctag and ctag == ks.get("ctag"):
            return {}, False
        listing = etags(self.propfind(ks["collection"], 1, "<d:getetag/>"))
        ks["ctag"] = ctag
        return listing, True

    def _multiget(self, kind, collection, hrefs):
        if not hrefs:
            return {}
        spec = KINDS[kind]
        body = '<?xml version="1.0" encoding="utf-8"?><%s %s><d:prop><d:getetag/><%s/></d:prop>%s</%s>' % (
            spec["multiget"], XMLNS, spec["data"],
            "".join("<d:href>%s</d:href>" % urllib.parse.quote(h) for h in hrefs), spec["multiget"])
        return multiget(self.req("REPORT", collection, body, {"Depth": "1"}).body)


def run(args):
    client = DavClient(args.url, args.host, args.user, args.password, args.profile, args.state)
    if args.command == "discover":
        return client.discover()
    if args.command == "put":
        return client.put(args.kind, args.name, args.start, args.end, args.tz)
    if args.command == "get":
        return client.get(args.href)
    if args.command == "update":
        return client.update(args.href, args.name)
    if args.command == "delete":
        return client.delete(args.href)
    if args.command == "sync":
        return client.sync(args.kind)
    raise HelperError("unknown dav command %s" % args.command)
