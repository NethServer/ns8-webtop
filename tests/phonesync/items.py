"""vCard and iCalendar items as phones write them, and the few fields tests read back."""

import datetime

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


def vcard(uid, name):
    return (
        "BEGIN:VCARD\r\n"
        "VERSION:3.0\r\n"
        "UID:%s\r\n"
        "FN:%s\r\n"
        "N:%s;;;;\r\n"
        "END:VCARD\r\n" % (uid, escape(name), escape(name))
    )


def _ical_time(value):
    """"2026-07-15T10:00:00" -> "20260715T100000", keeping a trailing Z."""
    return value.replace("-", "").replace(":", "")


def event(uid, name, start, end, tz):
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    tzparam = ";TZID=%s" % tz if tz else ""
    return (
        "BEGIN:VCALENDAR\r\n"
        "VERSION:2.0\r\n"
        "PRODID:-//NethServer//phonesync//EN\r\n"
        + (VTIMEZONES[tz] if tz else "")
        + "BEGIN:VEVENT\r\n"
        "UID:%s\r\n"
        "DTSTAMP:%s\r\n"
        "DTSTART%s:%s\r\n"
        "DTEND%s:%s\r\n"
        "SUMMARY:%s\r\n"
        "END:VEVENT\r\n"
        "END:VCALENDAR\r\n" % (uid, stamp, tzparam, _ical_time(start), tzparam, _ical_time(end), escape(name))
    )


def _lines(data):
    """Unfolded content lines of the main component (VCARD or VEVENT), as (name, params, value)."""
    unfolded = []
    for line in data.replace("\r\n", "\n").split("\n"):
        if line[:1] in (" ", "\t") and unfolded:
            unfolded[-1] += line[1:]
        elif line:
            unfolded.append(line)
    out, stack = [], []
    for line in unfolded:
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


def parse_start(data):
    for name, params, value in _lines(data):
        if name == "DTSTART":
            tz = next((p.split("=", 1)[1] for p in params if p.upper().startswith("TZID=")), None)
            v = value
            iso = "%s-%s-%sT%s:%s:%s%s" % (v[0:4], v[4:6], v[6:8], v[9:11], v[11:13], v[13:15], "Z" if v.endswith("Z") else "")
            return iso, tz
    return None
