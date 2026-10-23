# Phone sync end-to-end tests

## Why

WebDAV (CalDAV/CardDAV) and Z-Push (ActiveSync) run on PHP 7.3, which is
end of life and exposed to the reported session upload progress bugs
(CVE-2026-109618 / CVE-2026-109619). Sonicle does not keep these servers
current, so we will fork them onto the latest sabre/dav and Z-Push and a
current PHP 8 (Project 2, separate design).

Before touching that stack we need a safety net. The people at risk are
end users whose Android and iOS phones sync with WebTop. This project
writes end-to-end tests that behave like those phones, proves them green
on today's stack (known to work), and runs them in the existing CI. In
Project 2 the same tests, unchanged, decide whether the fork is ready.

## Goals

- Tests that act like Android and iOS phones over both protocols and
  cover what users do, in this priority order:
  1. Contacts: sync, create, delete, server-side change reaches the phone.
  2. Calendar: sync, create, read, modify, delete, server-side change
     reaches the phone.
  3. Mail (ActiveSync only): list folders, read a message, send a message
     that gets delivered.
- Each protocol starts with the account setup a phone performs, so a
  broken login or discovery fails early and clearly:
  - CalDAV/CardDAV: `/.well-known/caldav` and `/.well-known/carddav`
    redirects, current-user-principal, calendar-home-set and
    addressbook-home-set, listing calendars and address books.
  - ActiveSync: OPTIONS, Provision, FolderSync, with the server entered
    by hand. Autodiscover is out: today `/autodiscover/autodiscover.xml`
    is a static IMAP/SMTP file, so phones never get an ActiveSync answer
    and users enter the server manually. Serving real ActiveSync
    autodiscover moves to Project 2's scope, with its test written there.
- Phones set up before an upgrade keep working after it. In the `update`
  scenario each protocol pairs and syncs phones on the old (stable)
  module before `update-module` runs, saves the client state (device id,
  ActiveSync SyncKeys and policy key, DAV sync-tokens, ctags and etags),
  and after the upgrade continues with an incremental sync from that
  state. It must succeed without re-provisioning or a full resync, and
  no item may be lost or duplicated. This is the main risk for users in
  Project 2.
- Green on the current images (PHP 7.3, sabre/dav 3.2.3, Sonicle's
  bundled Z-Push) in both `install` and `update` scenarios.

## Non-goals

- Running PHPUnit or any library unit tests (sabre, Z-Push, Symfony).
- Real devices or emulators.
- Testing the WebTop web UI or the Java webapp beyond what sync needs.
- Changing PHP, sabre/dav or Z-Push versions (that is Project 2).

## Anti-goals

- Tests that pass only because they were shaped around the current
  implementation's quirks rather than what phones send. If a check would
  have to change when the stack is replaced, it is testing the wrong
  thing.
- Verifying a phone-side change only through the same PHP service that
  made it. Server-side truth must come from outside the PHP services.
- Flaky tests. A red run must mean users would be hurt.

## Decisions

Made with the user:

- Two projects, this one first; Project 2 starts only once this suite is
  green on the current stack.
- Tests replay the requests phones send; no real devices.
- Reuse the existing `test-module.yml` QEMU workflow and robot suite.
- No PHPUnit.
- Phones paired before an upgrade must keep syncing after it.
- ActiveSync autodiscover is not tested now; it becomes Project 2 work.
- Develop and iterate against the dev machine `rl1`
  (rl1.leader.default.gs.nethserver.net, see the
  `accessing-nethserver-test-vps` skill); CI is the final gate.

Claude's calls (user may override):

- The `update-module` step moves out of `20_webtop.robot` so the
  "before upgrade" pairing can run between install and upgrade. Suggested
  order: `20_webtop.robot` (install, login), `30_*` pre-upgrade pairing
  (update scenario only), `35_update.robot` (the existing update steps),
  then the protocol suites (`40_carddav.robot`, `41_caldav.robot`,
  `50_activesync.robot`), which in the update scenario first run the
  continuity checks. Client state is passed between suites via files on
  the node or global robot variables. They reuse `${webtop_module_id}`,
  `${backend_url}` and the existing users: `u1` is the phone owner, `u3`
  receives the sent mail.
- Like existing tests, requests run on the node over SSH. Protocol logic
  lives in one stdlib-only Python 3 helper under `tests/` (uploaded with
  SSHLibrary `Put File`, run with the node's `python3`), so nothing has to
  be installed on the node. It handles DAV XML and ActiveSync WBXML
  encoding/decoding; robot keywords call it and assert on its output.
- Two client profiles per protocol, sending the headers and request
  shapes of real clients:
  - DAV: DAVx⁵-style (Android; `sync-collection` / sync-token) and
    iOS-style (ctag/getetag polling with `calendar-multiget` /
    `addressbook-multiget`).
  - ActiveSync: iOS Mail-style and Android Gmail/Outlook-style, each
    with its own device id and `User-Agent`. Like real phones, each
    profile negotiates the highest protocol version the server offers in
    OPTIONS (iOS up to 16.1, Android up to 14.1). Today's bundled Z-Push
    stops at 14.1, so both run 14.1 now; the helper must still support
    16.1 so the unchanged tests exercise it once Project 2 offers it.
- Server-side truth comes from outside the PHP services:
  - Reads: WebTop's PostgreSQL database (`runagent ... podman exec
    postgres psql`, as `20_webtop.robot` already does).
  - Server-side writes ("changed in WebTop"): through the Java webapp
    (its REST API at `http://localhost:8080/webtop`, the same one the PHP
    services call) or the database, whichever proves reliable.
  - Mail delivery: check `u3`'s mailbox on the mail module, not through
    ActiveSync.
- Every test creates its own uniquely named items and removes them, so
  tests do not depend on each other's leftovers.

## Done when

- The new suite passes on `main` images in CI, in both `install` and
  `update` scenarios, including the upgrade continuity checks.
- Each protocol's tests are shown to fail when that service is broken
  (e.g. its container stopped on rl1), proving they can catch a
  regression.
- The tests do not need changes to run against the Project 2 images.

## Left to the builder

- Exact request bodies and headers per client profile, taken from
  protocol specs and well-documented client behavior, then confirmed
  against `rl1`.
- Authentication details for DAV and ActiveSync (user name form, Basic
  auth) and any `Host` / `X-Forwarded-*` headers needed when calling the
  backend directly instead of through Traefik.
- Whether the WebTop REST API or the database is the more reliable way
  to make server-side changes.
- How mail is seeded into `u1`'s inbox for the read test.
- File split and keyword names.
