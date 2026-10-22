# Known-Issue Fixes Implementation Plan (Phase 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two of the phone sync known issues are fixed with one small patch each to Sonicle's code: WebDAV tells the phone when WebTop refuses to store an item, and a phone waiting in ActiveSync Ping is woken by contact, calendar and task changes made in WebTop.

**Architecture:** Same machinery as Phases 1 and 2. A new `webdav/patches/04-report-backend-errors.patch` makes Sonicle's DAV backends rethrow WebTop REST errors as sabre exceptions instead of swallowing them. A new `z-push/patches/05-push-webtop-changes.patch` makes Sonicle's `ChangesSink` check fresh folder state once per call, which is what Z-Push 2.7.7's `BackendCombined` expects. Each patch gets one row in its README's patch table.

**Tech Stack:** Sonicle WebDAV and EAS servers `wt-5.35.7` on PHP 8.4.27, sabre/dav 4.7, Z-Push 2.7.7, Robot Framework phone sync suites, phonesync helper.

**Spec:** `docs/superpowers/specs/2026-10-21-php84-dav-eas-fork-design.md`
**Previous phases:** `docs/superpowers/plans/2026-10-22-webdav-php84.md`, `docs/superpowers/plans/2026-10-22-z-push-php84.md`

## Global Constraints

- **Spec override (user, 2026-10-22):** for these two issues only, the spec's "behaviour stays as today" and "all current-stack findings dismissed" rules do not apply. Everything else in the spec still holds.
- Patches touch only Sonicle's code, never Z-Push, sabre or other libraries. Format: `diff -U1`, LF line endings, `a/` and `b/` labels, one purpose per patch. Each patch applies after the existing ones (webdav 01-03, z-push 01-04; webdav `02-php84.patch` already edits log calls in `Backend.php`).
- Development and staging builds apply the same patches. A patch that does not apply fails the build, naming the patch.
- Tests stay unchanged except for removing the `known-issue robot:skip-on-failure` tag and the known-issue documentation from the two fixed cases. Adding tests is allowed.
- Out of scope: the third known issue (`50_activesync.robot`, an ActiveSync contact rename keeps the old display name). It needs a change in WebTop's Java code.
- Sonicle sources for writing the patches:
  - WebDAV `wt-5.35.7`, LF: `/tmp/claude-1000/-home-giacomo-projects-ns8-ns8-webtop/e20b09b8-6b08-4ac3-9cca-148a828b687b/scratchpad/dav-lf`. If it is missing, use `git archive wt-5.35.7 src` of `/home/giacomo/projects/ns8/ns8-webtop/webtop5-build/webtop-gate/modules/webtop-dav-server`.
  - EAS: `/tmp/claude-1000/-home-giacomo-projects-ns8-ns8-webtop/4d01f2bf-03bb-45d9-942b-d896306fc875/scratchpad/eas-pkg` (ignore its `vendor/`).
  - Z-Push 2.7.7, for reading only: `/tmp/claude-1000/-home-giacomo-projects-ns8-ns8-webtop/4d01f2bf-03bb-45d9-942b-d896306fc875/scratchpad/zp277/Z-Push-2.7.7/src`.
- Development loop, as in Phase 2:
  1. Build locally with the scratchpad scripts `build-webdav-local.sh` (in the `e20b09b8…/scratchpad` directory) and `build-zpush-local.sh` (in the `4d01f2bf…/scratchpad` directory).
  2. Push to `test/phone-sync-e2e` (PR #328, stays draft) and wait for CI `Publish images`.
  3. Update rl1 `webtop5` to `ghcr.io/nethserver/webtop:test-phone-sync-e2e`.
  4. Run the suites with the scratchpad `rt <suite>` script.
  5. Never run the install or update suites on rl1.

## Review Focus

- **Many phones waiting in Ping:** every waiting phone costs about three folder REST calls (contacts, calendar, tasks) every `PING_INTERVAL` (30 s). Sonicle's backends must make no REST call when nothing is being watched. Pinned in Task 2 Step 4, where an Email-only Ping must not call the webtop backends.
- **WebTop REST error during a Ping** (for example while the webapp restarts): the Ping must go on waiting, without a crash, a `trace error:` line or a PHP warning, and must wake no phone. Pinned in Task 2 Step 5, by stopping the webapp during a Ping and then running `85_php_logs`.
- **WebTop temporarily down, as seen over WebDAV:** a PUT or DELETE now gets HTTP 500 instead of a false 201 or 204. DAVx5 shows a sync error and retries on the next sync; iOS keeps the change pending and retries. That is the correct behaviour. The new `CRITICAL` log line must not match `85_php_logs`' `${PHP_ERRORS}`. Pinned in Task 1 Step 5.
- **A contact WebTop always rejects** (bad data): every sync now fails on it, and the phone shows an error until the user fixes or deletes the item. This is accepted (user decision): telling the phone is the point of the fix, and before it the data was lost silently.
- **Legacy folder ids** (NS7-migrated installs with `Z_PUSH_USE_LEGACY_FOLDER_IDS=True`): Z-Push hands `ChangesSinkInitialize` an encoded folder id. Sonicle's sink compares it with raw WebTop ids, and calling `encodeFolderId` again throws `FatalException`. The fix must decode the id on input and return the id Z-Push gave. Pinned in Task 2 Step 5.

---

## File Structure

| File | Responsibility |
|---|---|
| `webdav/patches/04-report-backend-errors.patch` | CardDAV and CalDAV create, update and delete report WebTop REST errors to the phone |
| `webdav/smoke.php`, `webdav/README.md` | smoke check of the status mapping; new patch-table row |
| `z-push/patches/05-push-webtop-changes.patch` | `ChangesSink` reads fresh folder state for contacts, calendar and tasks |
| `z-push/README.md` | new patch-table row |
| `tests/40_carddav.robot`, `tests/41_caldav.robot` | known-issue tag removed; update rejection cases |
| `tests/55_activesync_push.robot` | known-issue tag removed; calendar, tasks and quiet WebTop-folder Ping cases |

---

### Task 1: WebDAV reports WebTop errors to the phone

**Files:** Create `webdav/patches/04-report-backend-errors.patch`; Modify `webdav/smoke.php`, `webdav/README.md`, `tests/40_carddav.robot`, `tests/41_caldav.robot`

**Interfaces:**
- Produces: `WT\Util::toDavException(\Exception $ex, string $message): \Sabre\DAV\Exception`, in `lib/webtop/Util.php`. It maps `$ex->getCode()` as follows: 400 → `Exception\BadRequest`, 403 → `Exception\Forbidden`, 404 → `Exception\NotFound`, any other code (including 0, no answer) → `\Sabre\DAV\Exception` (500). The exception carries `$message`, a fixed text such as `WebTop could not save the contact`, never WebTop's response body, and the text must not contain `Error: `.

- [ ] **Step 1: Check the CalDAV side.** Read Sonicle's `lib/webtop/DAV/CalDAV/Backend.php`. In `wt-5.35.7`, `createCalendarObject` (about line 407) rethrows a plain 500, while `updateCalendarObject` (about 444) and `deleteCalendarObject` (about 472) swallow the error. Decision: the patch covers all six methods, `createCard`, `updateCard` and `deleteCard`, plus the three CalDAV object methods, and all go through `toDavException`. Calendar-level methods (`createCalendar` etc.) are left alone, because phones do not create calendars. If the code differs from this, stop and report.
- [ ] **Step 2: RED, add tests.**
  - In `40_carddav.robot`, add `Contact edit WebTop cannot save is reported to the phone`. It creates a contact with `dav put davx5`, PUTs the corrupt-PHOTO vCard to that contact's href, and asserts the status does not start with `2`. Then `Contact fields in WebTop` still shows the original name. Give `Phone puts a contact WebTop rejects` an optional `${href}` argument for this.
  - In `41_caldav.robot`, add `Event WebTop cannot save is reported to the phone`, but only if an iCalendar body that WebTop answers with 4xx or 5xx can be found. Check this with `curl` PUT on rl1 and WebTop's log. If none exists, ledger it, add no test, and rely on Step 3's smoke check.
  - Push and run `rt 40_carddav` (and `41` if a case was added).
  Expected: `Contact WebTop cannot save is reported to the phone` fails with `201`, still reported as skipped. The new cases FAIL with `201` or `204`.
- [ ] **Step 3: Smoke check.** Extend `webdav/smoke.php`: `toDavException` with codes 400, 403, 404, 500 and 0 returns `BadRequest`, `Forbidden`, `NotFound`, then plain `\Sabre\DAV\Exception` twice. Each `getHTTPCode()` is 400, 403, 404, 500, 500, and `getMessage()` equals the given text. Run `check-tree.sh` on a tree built with the existing patches.
  Expected: FAIL (`toDavException` undefined).
- [ ] **Step 4: Write the patch.** In each of the six catch blocks, keep `$logger->error($ex)`, then `throw \WT\Util::toDavException($ex, '<fixed text>')`. `deleteCard` and `deleteCalendarObject` no longer `return false`. Add the README row: "report WebTop errors to the phone (400/403/404 as such, other errors as 500) instead of answering 201 or 204 for an item WebTop did not store". Build with `build-webdav-local.sh`, then run `check-tree.sh`.
  Expected: PASS.
- [ ] **Step 5: GREEN.** Remove the known-issue tag and documentation from `Contact WebTop cannot save is reported to the phone`. Push, update rl1, then run `rt 40_carddav`, `rt 41_caldav`, `rt 85_php_logs` in one invocation.
  Expected: all PASS, no skips in 40 and 41, and 85 clean (the `CRITICAL: Sabre\DAV\Exception…` lines do not match).
- [ ] **Step 6:** Commit `fix(webdav): report WebTop save errors to the phone`.

### Task 2: ActiveSync Ping wakes on WebTop changes

**Files:** Create `z-push/patches/05-push-webtop-changes.patch`; Modify `z-push/README.md`, `tests/55_activesync_push.robot`

**Interfaces:**
- Consumes: Sonicle's `AbstractWebTopBackendDiff` (`backend/webtop/AbstractWebTopBackendDiff.php`):
  - `doGetApiFolders()`: an uncached REST call that returns `null` on `ApiException` (confirmed in `contacts.php`, `calendar.php`, `tasks.php`);
  - `getApiSyncFolders()`: cached for the whole request;
  - `folderMessagesCache`, also cached for the whole request;
  - `encodeFolderId()` and `decodeFolderId()`;
  - the private `$sinkFolders` and `$sinkStates`.
- Produces: `ChangesSinkInitialize($folderid): bool` and `ChangesSink($timeout): array`. `ChangesSink` returns immediately, with no sleep and with the ids Z-Push gave, and is safe to call with `$timeout = 1`. Z-Push 2.7.7's `BackendCombined::ChangesSink` (`backend/combined/combined.php:455`) calls it that way, then sleeps itself until `PING_INTERVAL` is over.

- [ ] **Step 1: RED, add tests** to `55_activesync_push.robot`:
  - `Event change wakes the phone`: Calendar, `Create event in WebTop`.
  - `Task change wakes the phone`: Tasks, `Create task in WebTop`.

  Both follow `Contact change wakes the phone`, and also assert `5 <= seconds < ${HEARTBEAT}`.
  - `Quiet ping on WebTop folders times out`: `--classes Contacts,Calendar,Tasks`, `status` 1, `40 <= seconds <= 60`. It catches a busy loop, an early return and false wakes. The existing `Quiet ping times out` pings Email only, so it covers Z-Push's own loop timing but not Sonicle's sink.

  Push, then `rt 55_activesync_push`.
  Expected: the contact case is skipped (it fails with status 1), the event and task cases FAIL with status 1, and the quiet case passes.
- [ ] **Step 2: Confirm the cause in the log.** Set the z-push log level to `DEBUG` with `configure-module`, run the contact case, and read the log.
  Expected: Sonicle's ChangesSink logs no `Checking changes` lines, because the loop never runs with `$timeout` 1. Set the level back to `ERROR`.
- [ ] **Step 3: Write the patch.** Decisions:
  - `ChangesSinkInitialize` decodes the id, stores `sinkFolders[<id Z-Push gave>] = <decoded id>`, and records `sinkStates` from `getApiSyncFolders()`. That is the state at Ping start, so a change made right after it is still seen.
  - `ChangesSink` returns `[]` at once when `sinkFolders` is empty.
  - Otherwise it makes one `doGetApiFolders()` call. On `null` it returns `[]` and keeps the states.
  - For each folder whose etag changed, it returns the id Z-Push gave, updates `sinkStates`, and drops that folder's `folderMessagesCache` entry. This is needed because Z-Push's first-iteration `CountChanges` filled that cache before the change. Without dropping it, `CountChange` after the notification sees the old list and logs `not relevant`, so the phone is not woken.
  - It replaces `foldersCache` with the fresh map.
  - Sonicle's `sleep()` and loop go away.
  - Confirm that Sonicle's backends run only under `BackendCombined` (`backend/webtop/webtop.php`). A direct caller would otherwise busy-loop.

  Add the README row: "ActiveSync push: check WebTop's contact, calendar and task folders on every Z-Push 2.7 sink call, so changes made in WebTop wake a waiting phone (Sonicle's loop never ran with Z-Push 2.7's 1 s call, and read the folders once per request)".
- [ ] **Step 4: Build check.** Build with `build-zpush-local.sh`, then run `check-tree.sh`.
  Expected: PASS. Extending `z-push/smoke.php` is skipped: it would need WebTop's REST API, so `55` is the test. Push, update rl1, set the log to `DEBUG`, and run `Quiet ping times out` alone.
  Expected: no `getFolders()` REST line during the Email-only Ping.
- [ ] **Step 5: GREEN.** Remove the known-issue tag and documentation from `Contact change wakes the phone`, then run `rt 55_activesync_push` and `rt 85_php_logs` in one invocation.
  Expected: all PASS, with no skips in 55.
  - **Webtop down:** start a Contacts Ping with `--heartbeat 90`, `podman stop` the webapp for about 40 s, then start it again.
    Expected: status 1 after about 90 s (or 2 if WebTop's etag changed on restart, which is acceptable), and `85` still clean.
  - **Legacy ids:** if the module lets rl1 set `Z_PUSH_USE_LEGACY_FOLDER_IDS=True`, run `55` once with it (the suite pairs again) and expect PASS, then set it back. Otherwise ledger "legacy ids: code review only".
- [ ] **Step 6:** Commit `fix(z-push): wake waiting phones on WebTop changes`.

### Task 3: CI and wrap-up

- [ ] **Step 1:** CI `Test module` is green in both `install` and `update`. Only the out-of-scope `known-issue` case (the ActiveSync contact rename) may be skipped.
- [ ] **Step 2:** Run `build-webdav-local.sh` and `build-zpush-local.sh` against the development packages in `/home/giacomo/projects/ns8/ns8-webtop/webtop5-build/` (`*-development-20261014-142343-CEST.tgz`).
  Expected: the new patches apply. Update the z-push README's development-build line and add the same line to the webdav README.
- [ ] **Step 3:** Update PR #328's description (two known issues fixed, one left, with the reason). Keep the PR draft.
