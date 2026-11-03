"""Parse z-push-admin output with the same rules as WebTop's ZPushManager (the admin Devices panel)."""

import re

DATE = re.compile(r"^\d{4}-\d\d-\d\d \d\d:\d\d$")


def parse_lastsync(text):
    """[{"device", "user", "last_sync"}] from `-a lastsync`; last_sync is None for "never"."""
    lines = text.splitlines()
    header = next((i for i, line in enumerate(lines)
                   if "Device id" in line and "Synchronized user" in line and "Last sync time" in line), None)
    if header is None:
        return []
    rows = []
    for line in lines[header + 2:]:
        if not line.strip():
            continue
        device, user, rest = (line.split(None, 2) + ["", ""])[:3]
        last = rest[:16]
        if last == "never" or rest.startswith("never"):
            last = None
        elif not DATE.match(last):
            raise ValueError("WebTop cannot read the last sync time %r of %s" % (rest, device))
        rows.append({"device": device, "user": user, "last_sync": last})
    return rows


def parse_list(text):
    """{device: [users]} from `-a list`."""
    lines = text.splitlines()
    start = next((i for i, line in enumerate(lines) if "All synchronized devices" in line), None)
    if start is None:
        return {}
    out = {}
    for line in lines[start + 4:]:
        if line.strip():
            device, users = (line.split(None, 1) + [""])[:2]
            out[device] = [u.strip() for u in users.split(",") if u.strip()]
    return out


def parse_info(text):
    """The device details WebTop shows: everything from the "Synchronized by user" line on."""
    lines = text.splitlines()
    start = next((i for i, line in enumerate(lines) if "Synchronized by user" in line), None)
    return "\n".join(lines[start:]).strip() if start is not None else ""


def run(args, text):
    if args.what == "lastsync":
        return {"devices": parse_lastsync(text)}
    if args.what == "list":
        return {"devices": parse_list(text)}
    return {"info": parse_info(text)}
