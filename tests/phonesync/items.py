"""vCard and iCalendar items as phones write them, and the few fields tests read back."""

import base64
import datetime
import re

# 1x1 transparent PNG used as contact photo
TEST_PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGBgAAAABQABpfZFQAAAAABJRU5ErkJggg==")

VTIMEZONES = {
    "Europe/Rome": (
        "BEGIN:VTIMEZONE\r\n"
        "TZID:Europe/Rome\r\n"
        "BEGIN:DAYLIGHT\r\n"
        "TZOFFSETFROM:+0100\r\n"
        "TZOFFSETTO:+0200\r\n"
        "TZNAME:CEST\r\n"
        "DTSTART:19700329T020000\r\n"
        "RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU\r\n"
        "END:DAYLIGHT\r\n"
        "BEGIN:STANDARD\r\n"
        "TZOFFSETFROM:+0200\r\n"
        "TZOFFSETTO:+0100\r\n"
        "TZNAME:CET\r\n"
        "DTSTART:19701025T030000\r\n"
        "RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU\r\n"
        "END:STANDARD\r\n"
        "END:VTIMEZONE\r\n"
    ),
}


def escape(text):
    return text.replace("\\", "\\\\").replace(",", "\\,").replace(";", "\\;").replace("\n", "\\n")


def unescape(text):
    out, i = [], 0
    while i < len(text):
        if text[i] == "\\" and i + 1 < len(text):
            out.append("\n" if text[i + 1] in "nN" else text[i + 1])
            i += 2
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


def fold(line):
    """Fold a content line at 75 octets without splitting UTF-8 characters."""
    out, current = [], ""
    for ch in line:
        limit = 75 if not out else 74  # continuation lines start with a space
        if len((current + ch).encode("utf-8")) > limit:
            out.append(current)
            current = ""
        current += ch
    out.append(current)
    return "\r\n ".join(out)


def _join(lines):
    return "".join(fold(line) + "\r\n" for line in lines)


def vcard(uid, name, fields=None):
    """vCard 3.0; fields: mobile, email, street, city, photo ("png" for TEST_PNG)."""
    fields = fields or {}
    lines = ["BEGIN:VCARD", "VERSION:3.0", "UID:" + uid, "FN:" + escape(name), "N:%s;;;;" % escape(name)]
    if fields.get("mobile"):
        lines.append("TEL;TYPE=CELL:" + fields["mobile"])
    if fields.get("email"):
        lines.append("EMAIL;TYPE=WORK:" + fields["email"])
    if fields.get("street") or fields.get("city"):
        lines.append("ADR;TYPE=WORK:;;%s;%s;;;" % (escape(fields.get("street") or ""), escape(fields.get("city") or "")))
    if fields.get("photo") == "png":
        lines.append("PHOTO;ENCODING=b;TYPE=PNG:" + base64.b64encode(TEST_PNG).decode())
    lines.append("END:VCARD")
    return _join(lines)


def _ical_time(value):
    """"2026-07-15T10:00:00" -> "20260715T100000", keeping a trailing Z."""
    return value.replace("-", "").replace(":", "")


def event(uid, name, start, end, tz, all_day=False, rrule=None, alarm=None):
    """iCalendar VEVENT; all_day takes dates (end exclusive), alarm is minutes before start."""
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//NethServer//phonesync//EN"]
    if tz and not all_day:
        lines += VTIMEZONES[tz].rstrip("\r\n").split("\r\n")
    lines += ["BEGIN:VEVENT", "UID:" + uid, "DTSTAMP:" + stamp]
    if all_day:
        lines += ["DTSTART;VALUE=DATE:" + start.replace("-", ""), "DTEND;VALUE=DATE:" + end.replace("-", "")]
    else:
        tzparam = ";TZID=%s" % tz if tz else ""
        lines += ["DTSTART%s:%s" % (tzparam, _ical_time(start)), "DTEND%s:%s" % (tzparam, _ical_time(end))]
    if rrule:
        lines.append("RRULE:" + rrule)
    lines.append("SUMMARY:" + escape(name))
    if alarm is not None:
        lines += ["BEGIN:VALARM", "ACTION:DISPLAY", "DESCRIPTION:Reminder", "TRIGGER:-PT%dM" % alarm, "END:VALARM"]
    lines += ["END:VEVENT", "END:VCALENDAR"]
    return _join(lines)


def _unfold(data):
    unfolded = []
    for line in data.replace("\r\n", "\n").split("\n"):
        if line[:1] in (" ", "\t") and unfolded:
            unfolded[-1] += line[1:]
        elif line:
            unfolded.append(line)
    return unfolded


def _lines(data):
    """Unfolded content lines of the main component (VCARD or VEVENT), as (name, params, value)."""
    out, stack = [], []
    for line in _unfold(data):
        head, _, value = line.partition(":")
        name, *params = head.split(";")
        name = name.upper()
        if name == "BEGIN":
            stack.append(value.upper())
        elif name == "END":
            stack.pop()
        elif stack and stack[-1] in ("VCARD", "VEVENT"):
            out.append((name, params, value))
    return out


def parse_name(data):
    for name, _, value in _lines(data):
        if name in ("FN", "SUMMARY"):
            return unescape(value)
    return None


def _components(data):
    """(component path, name, params, value) for every unfolded content line."""
    out, stack = [], []
    for line in _unfold(data):
        head, _, value = line.partition(":")
        name, *params = head.split(";")
        name = name.upper()
        if name == "BEGIN":
            stack.append(value.upper())
        elif name == "END":
            stack.pop()
        else:
            out.append(("/".join(stack), name, params, value))
    return out


def _has_type(params, wanted):
    types = []
    for p in params:
        key, _, val = p.partition("=")
        types += (val if val else key).upper().split(",")
    return wanted in types


def parse_fields(data):
    """Contact details as the tests compare them: mobile, email, street, city, photo_size."""
    out = {"mobile": None, "email": None, "street": None, "city": None, "photo_size": 0}
    for name, params, value in _lines(data):
        if name == "TEL" and _has_type(params, "CELL") and out["mobile"] is None:
            out["mobile"] = value
        elif name == "EMAIL" and out["email"] is None:
            out["email"] = value
        elif name == "ADR" and out["street"] is None:
            parts = value.split(";") + [""] * 7
            out["street"], out["city"] = unescape(parts[2]) or None, unescape(parts[3]) or None
        elif name == "PHOTO":
            if value.startswith("data:"):
                value = value.split(",", 1)[1]
            try:
                out["photo_size"] = len(base64.b64decode(value))
            except ValueError:
                out["photo_size"] = 0
    return out


def _minutes(duration):
    """'-PT15M', '-PT1H30M', '-P1D' -> minutes before start."""
    m = re.fullmatch(r"-?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?", duration)
    if not m:
        return None
    w, d, h, mi, _ = (int(x) if x else 0 for x in m.groups())
    return ((w * 7 + d) * 24 + h) * 60 + mi


def parse_event_details(data):
    """all_day, start (date, or local time), rrule and alarm minutes of the main VEVENT."""
    out = {"all_day": False, "start": None, "rrule": None, "alarm": None}
    for path, name, params, value in _components(data):
        if path.endswith("VEVENT") and name == "DTSTART":
            if any(p.upper() == "VALUE=DATE" for p in params) or len(value) == 8:
                out["all_day"], out["start"] = True, "%s-%s-%s" % (value[0:4], value[4:6], value[6:8])
            else:
                out["start"] = parse_start(data)[0]
        elif path.endswith("VEVENT") and name == "RRULE":
            out["rrule"] = value
        elif path.endswith("VEVENT/VALARM") and name == "TRIGGER" and out["alarm"] is None:
            out["alarm"] = _minutes(value)
    return out


def parse_start(data):
    for name, params, value in _lines(data):
        if name == "DTSTART":
            tz = next((p.split("=", 1)[1] for p in params if p.upper().startswith("TZID=")), None)
            v = value
            iso = "%s-%s-%sT%s:%s:%s%s" % (v[0:4], v[4:6], v[6:8], v[9:11], v[11:13], v[13:15], "Z" if v.endswith("Z") else "")
            return iso, tz
    return None


def with_name(data, name):
    """The item with its FN (and N) or SUMMARY replaced, everything else untouched."""
    out, stack = [], []
    for line in _unfold(data):
        head, _, value = line.partition(":")
        prop = head.split(";")[0].upper()
        if prop == "BEGIN":
            stack.append(value.upper())
        elif prop == "END":
            stack.pop()
        elif stack and stack[-1] in ("VCARD", "VEVENT"):
            if prop in ("FN", "SUMMARY"):
                line = "%s:%s" % (prop, escape(name))
            elif prop == "N":
                line = "N:%s;;;;" % escape(name)
        out.append(line)
    return _join(out)
