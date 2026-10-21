"""Phone sync helper: acts like a phone over CalDAV/CardDAV and ActiveSync.

Prints one JSON object on stdout; exit 1 with {"error", "http_status"} on failure.
"""

import argparse
import json
import os
import sys

VERSION = "1"
STATE_DIR = "/root/phonesync-state"

WEBTOP_COMMANDS = ["contact-create", "contact-rename", "contact-delete",
                   "event-create", "event-rename", "event-delete", "cleanup"]


def add_common(parser):
    parser.add_argument("--url", required=True, help="WebTop backend URL")
    parser.add_argument("--host", required=True, help="public host name of WebTop")
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
    dav = sub.add_parser("dav")
    dav.add_argument("command", choices=["discover", "put", "get", "update", "delete", "sync"])
    add_common(dav)
    dav.add_argument("--kind", choices=["contact", "event"])
    dav.add_argument("--name")
    dav.add_argument("--href")
    dav.add_argument("--start")
    dav.add_argument("--end")
    dav.add_argument("--tz")
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
        print(json.dumps(result, ensure_ascii=False))
        return 0
    except Exception as err:  # every failure must reach robot as JSON
        print(json.dumps({"error": str(err), "http_status": getattr(err, "http_status", None)}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
