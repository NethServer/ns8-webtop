"""Phone sync helper: acts like a phone over CalDAV/CardDAV and ActiveSync.

Prints one JSON object on stdout; exit 1 with {"error", "http_status"} on failure.
"""

import argparse
import json
import os
import sys

VERSION = "1"
STATE_DIR = "/root/phonesync-state"

WEBTOP_COMMANDS = ["contact-create", "contact-create-sparse", "event-create-untitled", "contact-rename", "contact-delete",
                   "event-create", "event-rename", "event-delete",
                   "task-create", "task-rename", "task-complete", "task-delete", "cleanup"]


def add_common(parser):
    parser.add_argument("--url", required=True, help="WebTop backend URL")
    parser.add_argument("--host", required=True, help="public host name of WebTop")
    parser.add_argument("--insecure", action="store_true",
                        help="do not check the HTTPS certificate (the node's own Traefik)")
    parser.add_argument("--user", required=True)
    parser.add_argument("--password", required=True)
    parser.add_argument("--profile")
    parser.add_argument("--state")


def build_parser():
    parser = argparse.ArgumentParser(prog="phonesync")
    sub = parser.add_subparsers(dest="proto", required=True)
    sub.add_parser("version")
    webtop = sub.add_parser("webtop")
    webtop.add_argument("command", choices=WEBTOP_COMMANDS)
    add_common(webtop)
    webtop.add_argument("--module", required=True, help="WebTop module id, for database lookups")
    webtop.add_argument("--name")
    webtop.add_argument("--new-name")
    webtop.add_argument("--start")
    webtop.add_argument("--end")
    webtop.add_argument("--tz")
    webtop.add_argument("--due", help="task due time, ISO UTC")
    webtop.add_argument("--attendee", help="event-create: email address of an invited attendee")
    dav = sub.add_parser("dav")
    dav.add_argument("command", choices=["discover", "put", "get", "update", "delete", "sync", "lookup"])
    add_common(dav)
    dav.add_argument("--kind", choices=["contact", "event"])
    dav.add_argument("--name")
    dav.add_argument("--href")
    dav.add_argument("--start")
    dav.add_argument("--end")
    dav.add_argument("--tz")
    dav.add_argument("--fields", help="JSON: mobile, email, street, city, photo")
    dav.add_argument("--all-day", action="store_true")
    dav.add_argument("--rrule")
    dav.add_argument("--alarm", type=int, help="minutes before start")
    devices = sub.add_parser("devices", help="parse z-push-admin output read from stdin")
    devices.add_argument("command", choices=["parse"])
    devices.add_argument("--what", choices=["lastsync", "list", "info"], required=True)
    eas = sub.add_parser("eas")
    eas.add_argument("command", choices=["setup", "sync", "add", "change", "delete", "fetch", "send", "lookup", "ping"])
    add_common(eas)
    eas.add_argument("--class", dest="cls", choices=["Contacts", "Calendar", "Email", "Tasks"])
    eas.add_argument("--window", type=int, default=25)
    eas.add_argument("--name")
    eas.add_argument("--server-id")
    eas.add_argument("--start")
    eas.add_argument("--end")
    eas.add_argument("--tz")
    eas.add_argument("--to")
    eas.add_argument("--subject")
    eas.add_argument("--body")
    eas.add_argument("--fields", help="JSON: mobile, email, street, city, photo")
    eas.add_argument("--all-day", action="store_true")
    eas.add_argument("--rrule")
    eas.add_argument("--alarm", type=int, help="minutes before start")
    eas.add_argument("--due", help="task due time, ISO UTC")
    eas.add_argument("--complete", action="store_true")
    eas.add_argument("--classes", help="comma-separated classes to ping")
    eas.add_argument("--heartbeat", type=int, default=45)
    return parser


def main(argv):
    args = build_parser().parse_args(argv)
    if getattr(args, "profile", None) and not args.state:
        args.state = os.path.join(STATE_DIR, args.profile + ".json")
    try:
        if args.proto == "version":
            result = {"version": VERSION}
        elif args.proto == "webtop":
            import webtop
            result = webtop.run(args)
        elif args.proto == "dav":
            import dav
            result = dav.run(args)
        elif args.proto == "devices":
            import devices
            result = devices.run(args, sys.stdin.read())
        elif args.proto == "eas":
            import eas
            result = eas.run(args)
        print(json.dumps(result, ensure_ascii=False))
        return 0
    except Exception as err:  # every failure must reach robot as JSON
        print(json.dumps({"error": str(err), "http_status": getattr(err, "http_status", None)}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
