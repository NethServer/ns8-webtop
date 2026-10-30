# Phone Sync Tests Phase 0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the phone sync end-to-end tests so they also cover tasks, all-day/recurring events with reminders, contacts with phone/email/address/photo, ActiveSync push and the Devices panel data, green on today's PHP 7.3 images.

**Architecture:** Builds on the phonesync helper and suites from PR #328. New item fields go through `items.py` (DAV) and `eas.py` (ActiveSync); server-side truth stays in WebTop's database, the WebTop Java REST API and the mail module. Push uses a new `eas ping` command; the Devices panel check runs `z-push-admin` the way WebTop does and parses its output with the same rules as WebTop's `ZPushManager`.

**Tech Stack:** Robot Framework + SSHLibrary, Python 3.9+ stdlib helper (`tests/phonesync/`), NS8 `runagent`, psql, doveadm.

**Spec:** `docs/superpowers/specs/2026-10-21-php84-dav-eas-fork-design.md` (section "Phase 0"); test design from Project 1: `docs/superpowers/specs/2026-10-21-phone-sync-e2e-tests-design.md`.

## Global Constraints

- The manual checklist (NS7-migrated install, Outlook with KOE) is not part of this plan; it runs on the testing release (Plan 3).

- Green on the current PHP 7.3 images in CI, `install` and `update` scenarios, before Phase 1 starts.
- Same rules as Project 1: stdlib-only helper on the node's `python3` (3.9+); server-side truth from outside the PHP services; every test creates `e2e-`-prefixed items and removes them; tests never edited to fit an implementation quirk.
- A behaviour that is wrong today gets a test asserting the right behaviour, tagged `known-issue robot:skip-on-failure` and documented, so it reports SKIP until fixed.
- Branch `test/phone-sync-e2e` (PR #328, back to draft until Phase 0 is green).
- Development on rl1 (`webtop5`, u1/u3 in `example.org`), robot venv and root self-SSH key recreated for the session only and removed at the end (Task 9). Never run install/update suites on rl1.

## Review Focus

- An all-day event on 15 July must show as 15 July on the other phone, not 14 July (WebTop stores local midnight). Pinned in Tasks 2 and 5.
- A contact photo must come back the same size it went in. Pinned in Tasks 2 and 5.
- A task completed on one phone must show as completed on the other phone and in WebTop. Pinned in Task 5.
- New mail delivered while a phone waits in Ping must wake it within one heartbeat. Pinned in Task 6.
- Phones paired before the upgrade must still be listed by `z-push-admin` after it. Pinned in Task 8.

---

## File Structure

| File | Change |
|---|---|
| `tests/phonesync/transport.py` | `request(..., timeout=60)` parameter |
| `tests/phonesync/items.py` | vCard extra fields + photo; event all-day, RRULE, VALARM; parsers |
| `tests/phonesync/dav.py`, `__main__.py` | `dav put/update` take `--fields JSON`, `--all-day`, `--rrule`, `--alarm`; `dav get` returns them |
| `tests/phonesync/eas.py` | Tasks class; contact/calendar extra fields; `ping()` |
| `tests/phonesync/webtop.py` | task create/rename/complete/delete via REST v2 |
| `tests/phonesync/devices.py` (new) | `z-push-admin` output parsers mirroring `ZPushManager` |
| `tests/phonesync/test_*.py` | unit tests for all of the above |
| `tests/webtop_server.resource` | SQL keywords for task, contact fields, event details; z-push-admin runner; SMTP mail delivery |
| `tests/40_carddav.robot`, `41_caldav.robot`, `50_activesync.robot` | new cases |
| `tests/55_activesync_push.robot` (new) | Ping |
| `tests/60_devices_panel.robot` (new) | z-push-admin data |
| `tests/21_pre_upgrade.robot`, `23_post_upgrade.robot` | tasks and device list across the upgrade |

## Shared Interfaces

**Field dict** (JSON on the CLI, same keys for DAV and ActiveSync): `{"mobile": str, "email": str, "street": str, "city": str, "photo": "png"}`. `"photo": "png"` means the fixed 1×1 PNG `items.TEST_PNG` (bytes constant, 67 bytes). Reads return the same keys, with `"photo_size": int` instead of `"photo"`.

**Event options:** `all_day: bool` (start/end are dates `YYYY-MM-DD`, end exclusive), `rrule: str` (e.g. `FREQ=WEEKLY;COUNT=4`), `alarm: int` minutes before start (use 15).

**WebTop DB reads** (`webtop_server.resource`), all filter `revision_status <> 'D'` and owner `u1`:
- `Contact fields in WebTop  ${name}` → dict `mobile`(work_mobile), `email`(work_email), `street`(work_address), `city`(work_city), `photo_size` (octet_length of contacts_pictures.bytes or 0).
- `Event details in WebTop  ${name}` → dict `all_day` (bool), `start_local` (`YYYY-MM-DDTHH:MM:SS` in Europe/Rome), `reminder` (int or None), `rrule` (events_recurrences.rule or None).
- `Task in WebTop  ${name}` → dict `subject`, `due_utc`, `status`, `completed` (bool: completed_on not null).

---

### Task 1: Item fields in the helper core

**Files:** Modify `tests/phonesync/transport.py`, `tests/phonesync/items.py`; Test `tests/phonesync/test_items.py`

**Interfaces:**
- Produces: `transport.request(method, url, *, user, password, host, headers=None, body=None, timeout=60)`; `items.TEST_PNG: bytes`; `items.vcard(uid, name, fields=None) -> str`; `items.event(uid, name, start, end, tz, all_day=False, rrule=None, alarm=None) -> str`; `items.parse_fields(data) -> dict` (field dict keys above, `photo_size`); `items.parse_event_details(data) -> {"all_day", "start", "rrule", "alarm"}`.

- [ ] **Step 1: Failing tests:** `test_vcard_fields_roundtrip` (TEL;TYPE=CELL, EMAIL;TYPE=WORK, ADR;TYPE=WORK with street/city, PHOTO;ENCODING=b;TYPE=PNG → `parse_fields` returns the same values and `photo_size == 67`); `test_parse_fields_data_uri_photo` (vCard 4 `PHOTO:data:image/png;base64,...`); `test_all_day_event` (`DTSTART;VALUE=DATE:20260715`, `DTEND;VALUE=DATE:20260716`, no TZID; details `all_day True`, `start "2026-07-15"`); `test_recurring_event_with_alarm` (`RRULE:FREQ=WEEKLY;COUNT=4`, `VALARM` with `TRIGGER:-PT15M` → details `rrule` and `alarm == 15`); `test_with_name_keeps_fields`.
- [ ] **Step 2: Run** `python3 -m unittest discover -s tests/phonesync -p test_items.py` → FAIL.
- [ ] **Step 3: Implement** in `items.py` (fold long PHOTO lines at 75 octets) and add the `timeout` parameter in `transport.py`.
- [ ] **Step 4: Run** all helper unit tests → OK.
- [ ] **Step 5: Commit** `test: add contact fields and event options to phonesync`.

### Task 2: Rich items over CalDAV/CardDAV

**Files:** Modify `tests/phonesync/dav.py`, `tests/phonesync/__main__.py`, `tests/phonesync/test_dav.py`, `tests/webtop_server.resource`, `tests/40_carddav.robot`, `tests/41_caldav.robot`

**Interfaces:**
- Consumes: Task 1.
- Produces: CLI `dav put --kind contact --name N --fields JSON`, `dav put --kind event --name N --start D --end D [--tz TZ] [--all-day] [--rrule R] [--alarm MIN]`; `dav get` adds `"fields"` (contacts) or `"details"` (events). Keywords `Contact fields in WebTop`, `Event details in WebTop`.

- [ ] **Step 1: Failing unit test** `test_put_passes_fields` (DavClient builds the vCard with the fields; use a fake transport).
- [ ] **Step 2: Run** → FAIL; **Step 3: implement**; **Step 4: run** → OK.
- [ ] **Step 5: Explore on rl1** the SQL for the two keywords (columns listed in Shared Interfaces; `calendar.events_recurrences.rule`, `contacts.contacts_pictures`), and write them.
- [ ] **Step 6: Robot cases** (both `davx5` and `ios-dav`):
  - 40 `Contact with details reaches WebTop` — fields `{"mobile":"+39 333 1234567","email":"niccolo@example.test","street":"Via Roma 1","city":"Pesaro","photo":"png"}` → `Contact fields in WebTop` equal (photo_size 67).
  - 40 `Contact details reach the second phone` — reader's `dav get` of the synced href returns the same fields and `photo_size == 67`.
  - 41 `All-day event keeps its day` — `--all-day --start 2026-07-15 --end 2026-07-16` → WebTop `all_day True`, `start_local 2026-07-15T00:00:00`; second phone reads `start 2026-07-15`, `all_day True`.
  - 41 `Recurring event with reminder` — `--rrule FREQ=WEEKLY;COUNT=4 --alarm 15`, 10:00 Europe/Rome → WebTop `rrule` contains `FREQ=WEEKLY` and `COUNT=4`, `reminder 15`; second phone reads the same rule and alarm.
- [ ] **Step 7: Run on rl1** `40 Carddav` and `41 Caldav` → all PASS (a field WebTop drops today becomes a `known-issue` case, not a weaker assertion).
- [ ] **Step 8: Commit** `test: check rich contacts and events over DAV`.

### Task 3: Tasks on the WebTop side

**Files:** Modify `tests/phonesync/webtop.py`, `tests/phonesync/__main__.py`, `tests/webtop_server.resource`

**Interfaces:**
- Produces: CLI `webtop task-create --name N --due YYYY-MM-DDTHH:MM:SSZ`, `task-rename --name N --new-name M`, `task-complete --name N`, `task-delete --name N`; `cleanup` also removes `e2e-`/`pre-upgrade-` tasks. REST base `/webtop/api/com.sonicle.webtop.tasks/v2/eas/folders`, default folder = entry with `"deflt": true`; dates `yyyyMMdd'T'HHmmss'Z'`; complete = set `complOn`. Keywords `Task in WebTop`, `Task does not exist in WebTop`, `Create task in WebTop`, `Rename task in WebTop`, `Complete task in WebTop`, `Delete task in WebTop`.

- [ ] **Step 1: Failing robot scratch suite** (not committed) creating, renaming, completing and deleting a task, asserting `Task in WebTop` after each step.
- [ ] **Step 2: Run on rl1** → FAIL (keywords missing).
- [ ] **Step 3: Implement** (task lookup by subject via SQL on `tasks.tasks` joined to `tasks.categories` user `u1`).
- [ ] **Step 4: Run** → PASS; **Step 5: Commit** `test: add WebTop task keywords`.

### Task 4: ActiveSync tasks and rich items in the helper

**Files:** Modify `tests/phonesync/eas.py`, `tests/phonesync/__main__.py`, `tests/phonesync/test_eas.py`

**Interfaces:**
- Consumes: Task 1 (`TEST_PNG`, field keys).
- Produces: class `Tasks` (folder types `["7", "15"]`); `eas add --class Tasks --name N --due ISOZ`, `eas change --class Tasks --server-id ID [--name N] [--complete]`; `eas add/change --class Contacts --fields JSON`; `eas add --class Calendar ... [--all-day] [--rrule R] [--alarm MIN]`. Sync entries gain `"fields"` (Contacts), `"details"` (Calendar: `all_day`, `start`, `rrule`, `alarm`), `"complete"` (Tasks). Field mapping: mobile→`Contacts:MobilePhoneNumber`, email→`Contacts:Email1Address` (plain address), street→`Contacts:BusinessAddressStreet`, city→`Contacts:BusinessAddressCity`, photo→`Contacts:Picture` (base64). Recurrence: `Calendar:Recurrence` Type 1 weekly with `Occurrences 4`, `Interval 1`, `DayOfWeek` from the start date; rrule string in entries is rebuilt as `FREQ=WEEKLY;COUNT=<n>`. Reminder → `Calendar:Reminder`. All-day → `Calendar:AllDayEvent 1` with start/end at local midnight.

- [ ] **Step 1: Failing tests** `test_task_data`, `test_task_complete_change`, `test_contact_fields_data`, `test_calendar_all_day_and_recurrence`, `test_sync_entries_carry_fields`.
- [ ] **Step 2: Run** → FAIL; **Step 3: implement**; **Step 4: run** all unit tests → OK.
- [ ] **Step 5: Commit** `test: add ActiveSync tasks and item fields`.

### Task 5: ActiveSync suite additions

**Files:** Modify `tests/50_activesync.robot`

- [ ] **Step 1: Cases** (both `ios-eas` and `android-eas` unless noted):
  - `Phone sets up account` also requires a tasks folder (type 7 or 15).
  - `Tasks initial sync`, `Task created on phone reaches WebTop` (due 2026-07-20T08:00:00Z), `Task changed in WebTop reaches phone`, `Task completed on phone shows completed` (WebTop `completed True`, second phone entry `complete 1`), `Task deleted in WebTop leaves phone`, `Task deleted on phone leaves WebTop`.
  - `Contact with details reaches WebTop` and `Contact details reach the second phone` (same values as Task 2; second phone's `fields` equal, `photo_size 67`).
  - `All-day event keeps its day` and `Recurring event with reminder` (same values as Task 2, checked in WebTop and on the second phone).
- [ ] **Step 2: Run on rl1** `50 Activesync` → PASS (known-issue rule as in Task 2).
- [ ] **Step 3: Prove it can fail:** stop `z-push.service` on webtop5 → new cases FAIL; start it.
- [ ] **Step 4: Commit** `test: check tasks and rich items over ActiveSync`.

### Task 6: ActiveSync push

**Files:** Modify `tests/phonesync/eas.py`, `tests/phonesync/__main__.py`, `tests/phonesync/test_eas.py`, `tests/webtop_server.resource`; Create `tests/55_activesync_push.robot`

**Interfaces:**
- Produces: `EasClient.ping(classes: list[str], heartbeat: int) -> {"status": int, "folders": [id], "seconds": float}` sending `Ping:Ping` with `Ping:LifeTime` and `Ping:Folders/Ping:Folder/{Ping:ServerEntryId, Ping:FolderType}` (tag names as in `wbxml.py`), HTTP timeout `heartbeat + 30`; CLI `eas ping --classes Email,Contacts --heartbeat 45`. Keyword `Deliver mail by SMTP  ${to}  ${subject}` (through the mail module's postfix, so delivery is real, not `doveadm save`).

- [ ] **Step 1: Failing unit tests** `test_ping_request_shape`, `test_ping_parses_changed_folders`, `test_ping_requires_synced_folders` (raises if a class has sync key 0).
- [ ] **Step 2: Run** → FAIL; **Step 3: implement**; **Step 4: run** → OK.
- [ ] **Step 5: Suite** (`ios-eas`; SSHLibrary `Start Command` for the waiting ping, `Read Command Output` to collect it; no other request with the same DeviceId while it waits):
  - `Quiet ping times out` — sync Email, ping Email heartbeat 45 → status 1, `seconds` between 40 and 60.
  - `New mail wakes the phone` — sync Email, start ping (Email, 45), sleep 5s, `Deliver mail by SMTP  ${PHONE_USER}  e2e-…`, read → status 2, folders contain the Inbox id, `seconds < 45`.
  - `Contact change wakes the phone` — `known-issue robot:skip-on-failure` (Sonicle's backend caches the folder list for the whole request, so WebTop changes never wake a Ping): sync Contacts, start ping (Contacts, 45), `Create contact in WebTop`, read → status 2 with the contacts folder.
- [ ] **Step 6: Run on rl1** → first two PASS, third SKIP; **Step 7: prove it can fail:** stop `z-push.service` on webtop5 → both non-skipped cases FAIL; start it again. **Step 8: Commit** `test: check ActiveSync push`.

### Task 7: Devices panel data and the zfaker injection fix

**Files:** Create `tests/phonesync/devices.py`, `tests/phonesync/test_devices.py`, `tests/phonesync/fixtures/zpush-admin/{lastsync,list,info}.txt`, `tests/60_devices_panel.robot`; Modify `tests/phonesync/__main__.py`, `tests/webtop_server.resource`, `zfaker/src/index.php`

**Interfaces:**
- Produces: `devices.parse_lastsync(text) -> [{"device", "user", "last_sync"}]` (header line contains `Device id`, `Synchronized user` and `Last sync time`; rows start 2 lines later; split on whitespace into at most 3 tokens; `last_sync` = first 16 chars of token 3, `None` for `never`, must match `YYYY-MM-DD HH:MM`); `devices.parse_list(text) -> {device: [users]}` (after `All synchronized devices`, rows start 4 lines later); `devices.parse_info(text) -> str` (from the line containing `Synchronized by user`, empty string if missing). CLI `devices parse --what lastsync|list|info` reading stdin. Keyword `Run z-push-admin  ${params}` → `runagent -m ${webtop_module_id} podman exec webapp curl -s -H 'Content-Type: application/json' -d '{"params": "<params>"}' http://localhost:8081/z-push-admin`.

- [ ] **Step 1: Capture fixtures on rl1** with `Run z-push-admin` for `-a lastsync`, `-a list`, `-a list -d e2eiphone0000001 -u <user>`.
- [ ] **Step 2: Failing unit tests** against the fixtures (both e2e devices listed with user and a valid date; info non-empty and starts with `Synchronized by user`).
- [ ] **Step 3: Run** → FAIL; **Step 4: implement**; **Step 5: run** → OK.
- [ ] **Step 6: Suite** `60_devices_panel.robot`: after `eas setup` + a Contacts sync for both EAS profiles, `lastsync` lists both device ids for `${PHONE_USER}` with today's date; `list` lists both; info for each device is non-empty.
- [ ] **Step 7: Run on rl1** → PASS; **Step 8: Commit** `test: check data shown in the WebTop devices panel`.
- [ ] **Step 9: Failing injection test** in `60_devices_panel.robot`: `zfaker rejects shell syntax` — `Run z-push-admin  -a lastsync; touch /tmp/e2e-injected` must not create `/tmp/e2e-injected` in the `z-push` container (`podman exec z-push test ! -e /tmp/e2e-injected`) and must answer HTTP 400; `-a list -d e2eiphone0000001 -u ${PHONE_USER}` still works. Run on rl1 → FAIL (file created).
- [ ] **Step 10: Fix `zfaker/src/index.php`:** split `params` on whitespace; every word must match `^[A-Za-z0-9@._:+-]+$`, else HTTP 400 and no command; build the command from `escapeshellarg()` of each word. Rebuild and deploy only the `webtop-z-push` image to webtop5 on rl1 (`podman build`-free: copy the file into the running container for the dev check), run → PASS; CI checks the built image.
- [ ] **Step 11: Commit** `fix(zfaker): reject shell syntax in z-push-admin parameters`.

### Task 8: Tasks and devices across the upgrade

**Files:** Modify `tests/21_pre_upgrade.robot`, `tests/23_post_upgrade.robot`

- [ ] **Step 1:** 21: each EAS profile also adds `pre-upgrade-<profile>-task` (due 2026-07-20T08:00:00Z) and syncs Tasks in the catch-up round.
- [ ] **Step 2:** 23: `Paired phone keeps syncing` adds `<profile> Tasks` rows; `Phones still know every pre-upgrade item once` checks tasks for EAS phones; new `Devices panel still lists paired phones` (`lastsync` contains both EAS device ids for `${PHONE_USER}`).
- [ ] **Step 3: Run on rl1** 21 → 23 → 50 with `SCENARIO:update` (no real upgrade) → PASS; **Step 4: Commit** `test: check tasks and devices survive the upgrade`.

### Task 9: CI, PR and rl1 cleanup

- [ ] **Step 1:** All helper unit tests OK; push `test/phone-sync-more`; CI `Test module` green in `install` and `update` (check the report: new cases PASS, only `known-issue` cases SKIP).
- [ ] **Step 2:** Open a draft PR (shipping-draft-pr skill) listing new coverage and every `known-issue` case.
- [ ] **Step 3:** Remove from rl1: `/root/robot-venv`, `/root/e2e`, `/root/phonesync`, `/root/phonesync-state`, `/root/.ssh/id_ecdsa{,.pub}` and its `robot-localhost` line in `authorized_keys`. Keep `webtop5` and u1/u3.
