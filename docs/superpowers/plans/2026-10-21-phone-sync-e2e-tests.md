# Phone Sync End-to-End Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Robot tests that act like Android and iOS phones over CalDAV/CardDAV and ActiveSync, green on today's WebTop stack, including phones paired before an upgrade.

**Architecture:** A stdlib-only Python helper (`tests/phonesync/`) speaks DAV and ActiveSync (WBXML) and keeps per-phone client state in JSON files on the node. Robot suites upload it over SSH, drive it per phone profile, and check server-side truth through WebTop's PostgreSQL database and the mail module, never through the PHP services.

**Tech Stack:** Robot Framework + SSHLibrary (existing), Python 3.9+ stdlib (`urllib`, `xml.etree`, `json`, `argparse`, `unittest`), NS8 `api-cli` / `runagent`.

**Spec:** `docs/superpowers/specs/2026-10-21-phone-sync-e2e-tests-design.md`

## Global Constraints

- No PHPUnit or library unit tests; no real devices or emulators.
- Helper uses only the Python standard library, must run on the node's `python3` (3.9 or newer); nothing gets installed on the node.
- Server-side truth comes from outside the PHP services: WebTop PostgreSQL for reads, Java webapp REST API or the database for server-side writes, the mail module's mailbox for delivery.
- Phone owner is `u1@domain.test` / `Nethesis,1234`; mail recipient is `u3@domain.test`.
- ActiveSync starts at OPTIONS with the server entered by hand; autodiscover is not tested.
- Each ActiveSync profile negotiates the highest version offered by the server, capped at its profile maximum (iOS 16.1, Android 14.1); the helper supports 14.1 and 16.1.
- Every test creates uniquely named items (prefix `e2e-` + 8 random hex chars) and removes them.
- Must pass in `test-module.yml` (QEMU) for `SCENARIO` `install` and `update`, unchanged on Project 2 images.
- Develop against rl1 (`accessing-nethserver-test-vps` skill); CI is the final gate.

## Review Focus

- Non-ASCII names (`Niccolò Ürsula ☕`) on contacts and events must round-trip unchanged phone → WebTop → phone. Pinned in Tasks 6 and 9.
- An event created on the phone at 10:00 `Europe/Rome` in summer (DST) must be stored at 08:00 UTC and come back at 10:00 local. Pinned in Tasks 7 and 9.
- An item deleted in WebTop must disappear from the phone on the next sync. Pinned in Tasks 6, 7 and 9.
- Two phones of the same user: a change made by one profile must show up on the other's next sync. Pinned in Tasks 6, 7 and 9.
- More items than one ActiveSync sync window (12 contacts, `WindowSize` 5) must all arrive via `MoreAvailable` paging. Pinned in Task 9.

---

## File Structure

| File | Responsibility |
|---|---|
| `tests/phonesync/__main__.py` | CLI entry: argument parsing, JSON output, exit codes |
| `tests/phonesync/http.py` | HTTP transport: Basic auth, forwarded headers, no redirect following unless asked |
| `tests/phonesync/state.py` | Load/save per-phone client state JSON |
| `tests/phonesync/profiles.py` | Phone profile constants (user agents, device ids, protocol caps, DAV strategy) |
| `tests/phonesync/dav.py` | CalDAV/CardDAV client: discovery, item CRUD, both sync strategies |
| `tests/phonesync/wbxml.py` | WBXML codec + ActiveSync code pages |
| `tests/phonesync/eas.py` | ActiveSync client: OPTIONS, Provision, FolderSync, Sync, SendMail, ItemOperations |
| `tests/phonesync/test_*.py` | Offline unit tests, run locally with `python3 -m unittest discover -s tests/phonesync` |
| `tests/phonesync/fixtures/` | Server responses captured from rl1, used by unit tests |
| `tests/phonesync.resource` | Robot keywords: environment resolution, upload, run helper |
| `tests/webtop_server.resource` | Robot keywords: server-side truth and writes (DB, REST, mailbox) |
| `tests/20_webtop.robot` | Modify: drop the update test cases |
| `tests/30_pre_upgrade.robot` | Pair all phones on the stable module (update scenario only) |
| `tests/35_update.robot` | The update test cases moved out of `20_webtop.robot` |
| `tests/40_carddav.robot`, `tests/41_caldav.robot`, `tests/50_activesync.robot` | Protocol suites; continuity checks first |

## Shared Interfaces

These are the contracts every task relies on.

**Helper CLI.** Run on the node as `python3 /root/phonesync <proto> <command> [options]`. Common options: `--state FILE` (default `/root/phonesync-state/<profile>.json`), `--profile {davx5,ios-dav,ios-eas,android-eas}`, `--url BASE` (the `${backend_url}`), `--host webtop.domain.com`, `--user`, `--password`. Success: exit 0, one JSON object on stdout. Failure: exit 1, `{"error": "<message>", "http_status": <int or null>}` on stdout.

| Command | Output JSON |
|---|---|
| `dav discover` | `{"principal": str, "calendar_home": str, "addressbook_home": str, "calendars": [{"href","displayname","ctag","sync_token"}], "addressbooks": [same]}` |
| `dav put --kind {contact,event} --name NAME [--start ISO --end ISO --tz TZID]` | `{"href": str, "uid": str, "etag": str}` |
| `dav get --href H` | `{"etag": str, "name": str, "start": str or null}` (`start` local time with TZID for events) |
| `dav update --href H --name NAME` | `{"etag": str}` (sends `If-Match`) |
| `dav delete --href H` | `{}` |
| `dav sync --kind {contact,event}` | `{"added": [{"href","uid","name"}], "changed": [same], "deleted": [href], "full_resync": bool}` |
| `eas setup` | `{"protocol": "14.1"|"16.1", "policy_key": str, "folders": [{"id","type","name"}]}` |
| `eas sync --class {Contacts,Calendar,Email} [--window N]` | `{"added": [{"server_id","name"}], "changed": [same], "deleted": [server_id], "full_resync": bool, "status": int}` |
| `eas add --class {Contacts,Calendar} --name NAME [--start ISO --end ISO --tz TZID]` | `{"server_id": str}` |
| `eas change --class C --server-id ID --name NAME` | `{}` |
| `eas delete --class C --server-id ID` | `{}` |
| `eas fetch --server-id ID` | `{"subject": str, "body": str}` |
| `eas send --to ADDR --subject S --body B` | `{}` |

`name` means the contact's display name (vCard `FN`, ActiveSync `FileAs`) or the event's summary/subject. `full_resync` is true when the server rejected the stored sync token/SyncKey and the helper had to start over (`dav`: 403 `valid-sync-token` or ctag strategy with no usable state; `eas`: Sync/FolderSync status 3 or HTTP 449 forcing re-provision). The helper never hides a full resync: it reports it.

**Profiles** (`profiles.py`, exact values):

| Profile | Protocol | User-Agent | Device | Strategy / cap |
|---|---|---|---|---|
| `davx5` | DAV | `DAVx5/4.4.3.2-ose (2024/09/27; dav4jvm; okhttp/4.12.0) Android/14` | — | `sync-collection` with stored sync-token |
| `ios-dav` | DAV | `iOS/17.6.1 (21G93) dataaccessd/1.0` | — | ctag check, then PROPFIND Depth 1 `getetag`, then `*-multiget` for new/changed hrefs |
| `ios-eas` | EAS | `Apple-iPhone15C2/2107.93` | `DeviceType=iPhone`, `DeviceId=e2eiphone0000001` | max 16.1 |
| `android-eas` | EAS | `Android-Mail/2024.09.08.672383104.Release` | `DeviceType=Android`, `DeviceId=e2eandroid000001` | max 14.1 |

**Robot keywords** (`tests/phonesync.resource`):
- `Resolve test environment` — sets `${webtop_module_id}`, `${MID}`, `${backend_url}` when not already defined (first `webtopN` / `mailN` user from `getent passwd`, route from `module/traefik1/get-route`).
- `Upload phonesync helper` — `Put Directory` of `tests/phonesync` to `/root/phonesync`, creates `/root/phonesync-state`.
- `Phonesync  ${proto}  ${command}  ${profile}  @{args}` → returns the decoded JSON dict; fails the test with the helper's `error` on exit 1.
- `Unique name  ${base}` → `e2e-<8 hex>-${base}`.

**Robot keywords** (`tests/webtop_server.resource`):
- `Contact exists in WebTop  ${name}` / `Contact does not exist in WebTop  ${name}`
- `Event in WebTop  ${name}` → dict `{"start_utc": str, "summary": str}` or fails
- `Event does not exist in WebTop  ${name}`
- `Create contact in WebTop  ${name}`, `Rename contact in WebTop  ${old}  ${new}`, `Delete contact in WebTop  ${name}`
- `Create event in WebTop  ${name}  ${start_utc}  ${end_utc}`, `Rename event in WebTop  ${old}  ${new}`, `Delete event in WebTop  ${name}`
- `Put message in mailbox  ${user}  ${subject}  ${body}`
- `Mailbox has message  ${user}  ${subject}` (retries up to 60 s)
- `Delete all test items in WebTop` — removes every `u1` contact and event whose name starts with `e2e-`; used as suite teardown by 40, 41 and 50 (not by 30, whose items must survive the upgrade)

---

### Task 1: WBXML codec

**Files:**
- Create: `tests/phonesync/wbxml.py`
- Test: `tests/phonesync/test_wbxml.py`

**Interfaces:**
- Produces: `encode(root: Element) -> bytes`, `decode(data: bytes) -> Element` (`xml.etree.ElementTree.Element`, tags as `"<CodePage>:<Tag>"`, e.g. `"AirSync:Sync"`). Code pages from MS-ASWBXML for: 0 AirSync, 1 Contacts, 2 Email, 4 Calendar, 7 FolderHierarchy, 14 Provision, 17 AirSyncBase, 18 Settings, 20 ItemOperations, 21 ComposeMail, 22 Email2.

- [ ] **Step 1: Write the failing tests**

```python
class WbxmlTest(unittest.TestCase):
    def test_roundtrip_foldersync(self):
        root = ET.Element("FolderHierarchy:FolderSync")
        ET.SubElement(root, "FolderHierarchy:SyncKey").text = "0"
        self.assertEqual(ET.tostring(decode(encode(root))), ET.tostring(root))

    def test_known_bytes_foldersync(self):
        # header 03 01 6A 00, SWITCH_PAGE 7, FolderSync(0x16|0x40), SyncKey(0x12|0x40), STR_I "0", END, END
        root = ET.Element("FolderHierarchy:FolderSync")
        ET.SubElement(root, "FolderHierarchy:SyncKey").text = "0"
        self.assertEqual(encode(root),
                         bytes.fromhex("03016a00 0007 56 52 03 3000 01 01".replace(" ", "")))

    def test_utf8_text_roundtrip(self):  # Review Focus: non-ASCII names
        ...  # Contacts:FileAs text "Niccolò Ürsula ☕" survives encode/decode

    def test_opaque_mime_roundtrip(self):
        ...  # ComposeMail:Mime with bytes payload uses OPAQUE (0xC3) and decodes back to the same bytes

    def test_unknown_tag_raises(self):
        with self.assertRaises(KeyError): encode(ET.Element("AirSync:NoSuchTag"))
```

- [ ] **Step 2: Run to verify they fail**

Run: `python3 -m unittest discover -s tests/phonesync -p 'test_wbxml.py' -v`
Expected: FAIL, `ModuleNotFoundError: No module named 'wbxml'`

- [ ] **Step 3: Implement `encode` / `decode` in `tests/phonesync/wbxml.py`**

Tag tables are dicts per code page copied from MS-ASWBXML; text as `STR_I` UTF-8; elements whose `.text` is `bytes` encode as `OPAQUE`, and on decode `ComposeMail:Mime` and `AirSyncBase:Data` keep bytes; empty elements omit the content bit.

- [ ] **Step 4: Run to verify they pass**

Run: `python3 -m unittest discover -s tests/phonesync -p 'test_wbxml.py' -v`
Expected: 5 tests OK

- [ ] **Step 5: Commit**

```bash
git add tests/phonesync/wbxml.py tests/phonesync/test_wbxml.py
git commit  # test: add WBXML codec for ActiveSync tests
```

### Task 2: Helper skeleton, state, transport and robot plumbing

**Files:**
- Create: `tests/phonesync/__main__.py`, `tests/phonesync/http.py`, `tests/phonesync/state.py`, `tests/phonesync/profiles.py`, `tests/phonesync/test_state.py`, `tests/phonesync.resource`
- Create (throwaway, not committed): `tests/99_scratch.robot`

**Interfaces:**
- Produces: `state.load(path: str) -> dict` (empty dict when missing), `state.save(path: str, data: dict) -> None` (atomic write via temp file + rename); `http.request(method: str, url: str, *, user: str, password: str, host: str, headers: dict, body: bytes | None) -> Response` with `.status: int`, `.headers: dict` (lower-case keys), `.body: bytes`; never follows redirects; sets `X-Forwarded-Host: <host>`, `X-Forwarded-Proto: https`, `Host: <host>`. `PROFILES: dict[str, dict]` with the Shared Interfaces values. CLI subcommand `version` → `{"version": "1"}`. The robot keywords from Shared Interfaces in `phonesync.resource`.

- [ ] **Step 1: Write the failing tests** — `test_state.py`: `test_load_missing_returns_empty`, `test_save_then_load_roundtrip` (unicode value `"Niccolò"`), `test_save_is_atomic` (no `*.tmp` left in the directory); `test_profiles.py`: `test_profiles_have_required_keys` (`user_agent` for all; `max_protocol` and `device_id` for EAS ones; `strategy` in `{"sync-collection","ctag"}` for DAV ones).
- [ ] **Step 2: Run** `python3 -m unittest discover -s tests/phonesync -v` → FAIL (missing modules).
- [ ] **Step 3: Implement** `state.py`, `profiles.py`, `http.py`, `__main__.py` (argparse with `dav`/`eas`/`version` subparsers; any exception → exit 1 with the error JSON).
- [ ] **Step 4: Run** `python3 -m unittest discover -s tests/phonesync -v` → all OK.
- [ ] **Step 5: Prepare rl1.** Follow the `accessing-nethserver-test-vps` skill. Install ldap+mail+webtop once:
  `robot -v NODE_ADDR:rl1.leader.default.gs.nethserver.net -v IMAGE_URL:ghcr.io/nethserver/webtop:latest -v SCENARIO:install -v SSH_KEYFILE:<key> --suite "Tests.10 Install Mail" --suite "Tests.20 Webtop" --outputdir tests/outputs tests`
  Expected: all PASS. Later runs pick the installed modules up via `Resolve test environment`.
- [ ] **Step 6: Smoke on rl1.** `99_scratch.robot` with `Resolve test environment`, `Upload phonesync helper`, `Phonesync  version  ""  ""` asserting `version == "1"`; also `curl -sI -H 'Host: webtop.domain.com' -H 'X-Forwarded-Host: webtop.domain.com' -H 'X-Forwarded-Proto: https' ${backend_url}/.well-known/caldav` shows `301` to `https://webtop.domain.com/webtop-dav/server.php/`.
  Run: `robot -v NODE_ADDR:... -v SSH_KEYFILE:<key> --suite "Tests.99 Scratch" tests` → PASS.
- [ ] **Step 7: Commit** (without `99_scratch.robot`): `test: add phonesync helper skeleton`.

### Task 3: Server-side truth and writes

**Files:**
- Create: `tests/webtop_server.resource`

**Interfaces:**
- Consumes: `Resolve test environment`, `Unique name` (Task 2).
- Produces: the `webtop_server.resource` keywords listed in Shared Interfaces.

- [ ] **Step 1: Explore the schema on rl1.** Run `runagent -m ${webtop_module_id} podman exec postgres psql -U postgres webtop5 -c '\d contacts.contacts'` and `'\d calendar.events'`; note the name, start, owner (`user_uid`/category) and soft-delete (`revision_status`) columns. Create a contact and an event in the WebTop web UI as `u1` and confirm the rows.
- [ ] **Step 2: Write the failing check in `99_scratch.robot`:** create unique contact and event with `Create … in WebTop`; `Contact exists in WebTop`; `Event in WebTop` returns the given `start_utc`; rename; delete; `Contact does not exist in WebTop`. `Put message in mailbox  u1@domain.test  ${subject}  hello` then `Mailbox has message  u1@domain.test  ${subject}`.
- [ ] **Step 3: Run** `robot ... --suite "Tests.99 Scratch" tests` → FAIL (keywords missing).
- [ ] **Step 4: Implement the keywords.** Reads: `psql -tA` queries filtering out soft-deleted rows. Writes: first try the WebTop REST API the PHP services call (`http://localhost:8080/webtop/api/...`, observe the URLs in `/var/log/webtop-dav` with `loglevel DEBUG` on rl1); fall back to SQL that also bumps the revision timestamp. Pick the method whose change is seen by a `curl` PROPFIND `getctag` on the address book; write the choice and reason as a comment at the top of the resource. Mailbox: `doveadm save` / `doveadm search` inside the mail module's dovecot container via `runagent -m ${MID}` (confirm the container name with `runagent -m ${MID} podman ps`).
- [ ] **Step 5: Run** the scratch suite → PASS, then delete the test data it made.
- [ ] **Step 6: Commit** `tests/webtop_server.resource`: `test: add WebTop server-side test keywords`.

### Task 4: Split the update steps out of 20_webtop.robot

**Files:**
- Modify: `tests/20_webtop.robot` (remove the five `… update …` test cases, keep `Login as u1`, `Get the database id of u1` keywords and `${u1_uid}` as a global variable)
- Create: `tests/35_update.robot` (those five test cases, same names and bodies; imports `api.resource`)

**Interfaces:**
- Consumes: `${webtop_module_id}`, `${mail_modules_id}`, `${backend_url}`, `${u1_uid}` set by `20_webtop.robot` — make them `Set Global Variable`.

- [ ] **Step 1:** Move the test cases; move the keywords they use into `35_update.robot` or a shared resource if `20` still needs them.
- [ ] **Step 2: Run on rl1, update scenario, full suite:** `robot -v SCENARIO:update -v IMAGE_URL:ghcr.io/nethserver/webtop:<branch> ... tests` → all PASS, `35 Update` cases run and pass, `90` uninstalls.
- [ ] **Step 3: Commit:** `test: move module update checks to own suite`.

### Task 5: DAV client

**Files:**
- Create: `tests/phonesync/dav.py`, `tests/phonesync/test_dav.py`, `tests/phonesync/fixtures/dav/*.xml`
- Modify: `tests/phonesync/__main__.py` (wire `dav` subcommands)

**Interfaces:**
- Consumes: `http.request`, `state.load/save`, `PROFILES` (Task 2).
- Produces: the `dav` CLI commands in Shared Interfaces. State keys per kind: `{"collection": href, "sync_token": str | None, "ctag": str | None, "items": {href: {"etag", "uid", "name"}}}`.

- [ ] **Step 1: Capture fixtures from rl1** with `curl` as `u1`: PROPFIND current-user-principal, home-set, Depth 1 on both homes, `sync-collection` (initial and with token), `addressbook-multiget`, `calendar-multiget`, and a 403 `valid-sync-token` response (send a made-up token). Save under `fixtures/dav/`.
- [ ] **Step 2: Write the failing tests:** `test_parse_discovery` (homes and collections from fixtures); `test_vcard_build_and_parse` and `test_ical_build_and_parse` (`Niccolò Ürsula ☕`; event `2026-07-15T10:00` with `TZID=Europe/Rome` and a `VTIMEZONE`); `test_sync_collection_diff` (fixture → added/changed/deleted against a given state); `test_ctag_strategy_skips_when_ctag_unchanged`; `test_invalid_sync_token_reports_full_resync`.
- [ ] **Step 3: Run** `python3 -m unittest discover -s tests/phonesync -p 'test_dav.py' -v` → FAIL.
- [ ] **Step 4: Implement `dav.py`.** Discovery follows the `/.well-known/*` 301 to its path. `put` uses `If-None-Match: *` and new `<uid>.vcf`/`.ics` hrefs; vCard 3.0 for contacts, iCalendar 2.0 events with `VTIMEZONE`. Sync strategy from the profile.
- [ ] **Step 5: Run** unit tests → OK; on rl1 run `python3 /root/phonesync dav discover --profile davx5 ...` and `--profile ios-dav` → both list at least one calendar and one address book.
- [ ] **Step 6: Commit:** `test: add CalDAV and CardDAV client`.

### Task 6: CardDAV suite

**Files:**
- Create: `tests/40_carddav.robot`

**Interfaces:**
- Consumes: Tasks 2, 3, 5.

Each test runs for both `davx5` and `ios-dav` (test template with the profile as argument). Suite setup: `Resolve test environment`, `Upload phonesync helper`. Suite teardown: `Delete all test items in WebTop` (same for Tasks 7 and 9). Continuity cases are added in Task 10.

- [ ] **Step 1: Write the test cases:**
  - `Phone discovers address book` — `dav discover` has ≥1 address book.
  - `Phone initial sync` — `dav sync --kind contact`; `full_resync` false on the second call; second call `added == []`.
  - `Contact created on phone reaches WebTop` — `dav put`, then `Contact exists in WebTop`.
  - `Non-ASCII contact round-trips` — name `Niccolò Ürsula ☕`: `Contact exists in WebTop` with exact name; `dav get` name equal.
  - `Contact changed in WebTop reaches phone` — `Rename contact in WebTop`; `dav sync` lists the href in `changed` with the new name.
  - `Contact deleted in WebTop leaves phone` — `Delete contact in WebTop`; `dav sync` has it in `deleted`.
  - `Contact deleted on phone leaves WebTop` — `dav delete`; `Contact does not exist in WebTop`.
  - `Second phone sees first phone's contact` — `davx5` puts, `ios-dav` sync lists it in `added`.
- [ ] **Step 2: Run on rl1** `robot ... --suite "Tests.40 Carddav" tests` → all PASS.
- [ ] **Step 3: Prove it can fail:** on rl1 `runagent -m ${webtop_module_id} systemctl --user stop webdav` (confirm the unit name with `systemctl --user list-units` under `runagent`), rerun → FAIL in `Phone discovers address book`; start it again.
- [ ] **Step 4: Commit:** `test: add CardDAV phone sync tests`.

### Task 7: CalDAV suite

**Files:**
- Create: `tests/41_caldav.robot`

Same structure as Task 6 for events, both profiles.

- [ ] **Step 1: Write the test cases:** `Phone discovers calendar`; `Phone initial sync`; `Event created on phone reaches WebTop` (start `2026-07-15T10:00`, end `11:00`, `Europe/Rome` → `Event in WebTop` `start_utc == 2026-07-15T08:00:00Z`); `Phone reads event back` (`dav get` start `2026-07-15T10:00` with `Europe/Rome`); `Event modified on phone reaches WebTop` (`dav update`, WebTop summary equal); `Non-ASCII event round-trips`; `Event changed in WebTop reaches phone`; `Event deleted in WebTop leaves phone`; `Event deleted on phone leaves WebTop`; `Second phone sees first phone's event`.
- [ ] **Step 2: Run on rl1** `--suite "Tests.41 Caldav"` → all PASS.
- [ ] **Step 3: Prove it can fail** (stop `webdav` as in Task 6) → FAIL; restart.
- [ ] **Step 4: Commit:** `test: add CalDAV phone sync tests`.

### Task 8: ActiveSync client

**Files:**
- Create: `tests/phonesync/eas.py`, `tests/phonesync/test_eas.py`, `tests/phonesync/fixtures/eas/*.wbxml`
- Modify: `tests/phonesync/__main__.py` (wire `eas` subcommands)

**Interfaces:**
- Consumes: `wbxml.encode/decode` (Task 1), `http.request`, `state`, `PROFILES` (Task 2).
- Produces: the `eas` CLI commands in Shared Interfaces. State: `{"protocol", "policy_key", "folder_sync_key", "folders": [...], "sync": {class: {"collection_id", "sync_key", "items": {server_id: name}}}}`. Requests go to `/Microsoft-Server-ActiveSync?Cmd=<Cmd>&User=u1@domain.test&DeviceId=<id>&DeviceType=<type>` with `MS-ASProtocolVersion`, `X-MS-PolicyKey`, `Content-Type: application/vnd.ms-sync.wbxml`.

- [ ] **Step 1: Write the failing tests:** `test_negotiate_version` (`"2.5,12.0,12.1,14.0,14.1"` → ios `14.1`, android `14.1`; `"…,14.1,16.0,16.1"` → ios `16.1`, android `14.1`; `"12.1"` → error); `test_provision_two_step` (builds initial request with `PolicyKey` absent, then ack with the temp key; 14.1 includes `Settings:DeviceInformation`); `test_sync_paging` (two fixture responses with `MoreAvailable` → helper loops until absent, items merged); `test_sync_status_3_reports_full_resync`; `test_calendar_add_shape` (14.1 has `Calendar:UID` and `Calendar:Timezone` blob; 16.1 uses `AirSyncBase:Location` and omits `Calendar:UID`); `test_contact_add_utf8` (`Niccolò Ürsula ☕`); `test_sendmail_shape` (14.1 and 16.1 `ComposeMail:SendMail` with `ClientId`, `SaveInSentItems`, opaque `Mime`).
- [ ] **Step 2: Run** `python3 -m unittest discover -s tests/phonesync -p 'test_eas.py' -v` → FAIL.
- [ ] **Step 3: Implement `eas.py`.** HTTP 449 or Status 142–144 → re-provision, reported as `full_resync: true`. `--window` default 25. `Calendar:Timezone` is the base64 `TIME_ZONE_INFORMATION` for `Europe/Rome`. Capture `fixtures/eas/` from rl1 with the helper's `--dump DIR` debug option.
- [ ] **Step 4: Run** unit tests → OK; on rl1 `eas setup --profile ios-eas` and `--profile android-eas` → both `protocol == "14.1"`, folders include types 9 (Contacts) and 8 (Calendar).
- [ ] **Step 5: Commit:** `test: add ActiveSync client`.

### Task 9: ActiveSync suite

**Files:**
- Create: `tests/50_activesync.robot`

Contacts and calendar tests run for both `ios-eas` and `android-eas`; mail tests run once with `ios-eas`.

- [ ] **Step 1: Write the test cases:**
  - `Phone sets up account` — `eas setup`, folders contain Contacts, Calendar, Inbox.
  - Contacts: `Initial sync`, `Contact created on phone reaches WebTop`, `Non-ASCII contact round-trips`, `Contact changed in WebTop reaches phone`, `Contact deleted in WebTop leaves phone`, `Contact deleted on phone leaves WebTop`, `Second phone sees first phone's contact`, `Large address book pages` (create 12 contacts in WebTop, `eas sync --window 5` returns all 12 in `added`).
  - Calendar: same set as Task 7 with `eas add/change/delete`, including the 10:00 `Europe/Rome` → `08:00Z` check.
  - Mail: `Phone reads a message` (`Put message in mailbox  u1@domain.test`, `eas sync --class Email` lists the subject, `eas fetch` body equal); `Phone sends a message` (`eas send --to u3@domain.test`, `Mailbox has message  u3@domain.test`).
- [ ] **Step 2: Run on rl1** `--suite "Tests.50 Activesync"` → all PASS.
- [ ] **Step 3: Prove it can fail:** stop the `z-push` unit, rerun → FAIL in `Phone sets up account`; restart.
- [ ] **Step 4: Commit:** `test: add ActiveSync phone sync tests`.

### Task 10: Upgrade continuity

**Files:**
- Create: `tests/30_pre_upgrade.robot`
- Modify: `tests/40_carddav.robot`, `tests/41_caldav.robot`, `tests/50_activesync.robot` (add continuity cases as the first tests)

**Interfaces:**
- Consumes: everything above. State files in `/root/phonesync-state/` carry across suites; created names go to `/root/phonesync-state/pre-upgrade.json` (`{"contacts": {profile: name}, "events": {profile: name}}`).

- [ ] **Step 1: Write `30_pre_upgrade.robot`** (every case `Skip If  '${SCENARIO}' != 'update'`): upload helper; for each of the four profiles: discover/setup, create one contact and one event, full sync of contacts and calendar; record names.
- [ ] **Step 2: Write the continuity cases** in each protocol suite (skip unless update), before any other case, using the saved state with no new setup:
  - `Paired phone keeps syncing after upgrade` — incremental sync of contacts and calendar: `full_resync == false`, `added == []`, `deleted == []` (EAS also: no HTTP 449, `status == 1`).
  - `Pre-upgrade items survive` — the recorded contact and event exist in WebTop and in the phone's state, each exactly once (`Contact exists in WebTop` row count 1).
  - `Paired phone can still write` — create one new contact; it reaches WebTop.
- [ ] **Step 3: Run on rl1, full update scenario** `robot -v SCENARIO:update -v IMAGE_URL:ghcr.io/nethserver/webtop:<branch> ... tests` → all PASS. Also run `SCENARIO:install` → continuity cases SKIP, rest PASS.
- [ ] **Step 4: Commit:** `test: check phone sync survives module upgrade`.

### Task 11: CI run and draft PR

- [ ] **Step 1:** `python3 -m unittest discover -s tests/phonesync -v` → all OK; delete `tests/99_scratch.robot` if still present.
- [ ] **Step 2:** Push `test/phone-sync-e2e`; wait for `Publish images` → `Test module` on the branch. Expected: green in both scenarios (check the robot report artifact: no unexpected SKIP in 40/41/50 for `install`).
- [ ] **Step 3:** Open a draft PR (shipping-draft-pr skill). Body lists what each suite covers, the "prove it can fail" results from Tasks 6, 7 and 9, and the server-side write method picked in Task 3.
