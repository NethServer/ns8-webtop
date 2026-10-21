"""Phone sync helper: acts like a phone over CalDAV/CardDAV and ActiveSync.

Prints one JSON object on stdout; exit 1 with {"error", "http_status"} on failure.
"""

import argparse
import json
import sys

VERSION = "1"


def build_parser():
    parser = argparse.ArgumentParser(prog="phonesync")
    sub = parser.add_subparsers(dest="proto", required=True)
    sub.add_parser("version")
    return parser


def main(argv):
    args = build_parser().parse_args(argv)
    try:
        if args.proto == "version":
            result = {"version": VERSION}
        print(json.dumps(result, ensure_ascii=False))
        return 0
    except Exception as err:  # every failure must reach robot as JSON
        print(json.dumps({"error": str(err), "http_status": getattr(err, "http_status", None)}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
