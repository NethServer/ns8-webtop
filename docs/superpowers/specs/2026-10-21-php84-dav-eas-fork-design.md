# WebDAV and ActiveSync on PHP 8.4

## Why

The `webtop-webdav` and `webtop-z-push` images run Sonicle's WebDAV
(CalDAV/CardDAV) and ActiveSync (Z-Push) servers on PHP 7.3. PHP 7.3 is
end of life and exposed to the reported session upload progress bugs
(CVE-2026-109618 / CVE-2026-109619); `session.upload_progress.enabled = Off`
only closes one of the two reported paths. Sonicle has not released a PHP 8
version of these servers.

We build our own PHP 8.4 version inside `ns8-webtop`: unmodified upstream
libraries, Sonicle's released code, and a small patch of ours. The fork is
temporary: on each Sonicle release we refresh the patch, and once Sonicle
ships PHP 8 support we drop the fork and go back to their packages.

Phones must not notice. The phone sync end-to-end tests (PR #328:
`21_pre_upgrade`, `23_post_upgrade`, `40_carddav`, `41_caldav`,
`50_activesync`) are the acceptance gate and must pass unchanged.

## Goals

- `webtop-webdav` and `webtop-z-push` run on PHP 8.4 (official
  `php:8.4-fpm` image family), with the `imap` extension from PECL.
- WebDAV: sabre/dav 4.7.x (latest 4.7 release, currently 4.7.1) with its
  matching sabre/* libraries.
- ActiveSync: Z-Push 2.7.7, unmodified.
- Sonicle's own code (glue to the WebTop Java REST API: DAV `lib/`,
  `server.php`; EAS `lib/`, `backend/webtop`, `backend/wtimap`, `inc/`,
  `index.php` and CLIs) comes from the Sonicle release selected by
  `webtop5-build/VERSION` (today `wt-5.35.7`), exactly as now.
- Behaviour stays as today. Only what Z-Push 2.7.7, sabre/dav 4.7 and
  PHP 8.4 require changes.
- Refreshing the patch for a new Sonicle release is a routine task: the
  patch is small, split by purpose, and applies with a clear failure when
  it no longer fits.
- Existing installs upgrade in place: phones paired before the upgrade
  keep syncing without re-provisioning, full resync, lost or duplicated
  items (checked by `21_pre_upgrade` / `23_post_upgrade`).

## Non-goals

- Anything from Sonicle's unreleased Bitbucket branch
  `feature/WT-1456-bump-zpush-version-to-support-php8` (it changes folder
  types, calendar sync window, user details source, adds autodiscover).
- ActiveSync autodiscover.
- Fixing current-stack behaviours found by the tests (no address book
  before first web login, ActiveSync contact rename keeps the old display
  name, one-second etag/ctag resolution, REST calendar listing error).
- The Java webapp, pecbridge, phonebook (`php:8-cli`) and apache images,
  except where apache needs the same file layout.
- Upgrading library majors that PHP 8.4 does not force (e.g. guzzle 6 stays,
  so Sonicle's generated REST clients keep working unchanged).

## Anti-goals

- Changing what phones see: folder ids and types, sync windows, item
  contents, user details. A phone that has to be set up again, or resyncs
  everything after the upgrade, is a failure even if the tests were edited
  to pass.
- Editing the phone sync tests to make the fork pass.
- Patching Z-Push or sabre themselves. If a fix is needed there, it belongs
  upstream; our patch only touches Sonicle's code.
- A patch so entangled with Sonicle's code that every Sonicle release needs
  re-engineering.

## What we know (recon, 2026-10-21)

- Sonicle's packages are byte-identical to `src/` of their repos
  (github.com/sonicle-webtop/webtop-{dav,eas}-server, mirrors of
  bitbucket.org/sonicle). `vendor/` is committed, not built.
- EAS bundles Z-Push 2.4.5 copied by hand, changed in one place that is
  already fixed upstream. Z-Push 2.4.5 does not even parse on PHP 8.
- Sonicle extends Z-Push via `BackendCombined` / `BackendDiff` /
  `BackendIMAP` subclasses. Between 2.4.5 and 2.7.7 these interfaces are
  compatible; state format is unchanged (`STATEVERSION_02`), so device
  state should survive. Known differences: `IpcSharedMemoryProvider`
  constructor gains a 4th parameter, `BackendCombined::ChangesSink` polls
  differently, Z-Push 2.7 refuses some config constant combinations (none
  defined by Sonicle today), `KOE_CAPABILITY_IMPERSONATE` is safe again in
  2.7.7.
- DAV ships what is really sabre/dav 3.2.2 (lock says 3.2.3) and a
  guzzlehttp/psr7 missing `UriComparator.php` (latent fatal on REST
  redirects). A clean Composer install fixes both.
- sabre/dav 3.2 → 4.7 for Sonicle's DAV code: no signature changes in the
  backend interfaces it implements. Expected edits: `ExceptionLoggerPlugin`
  must accept `\Throwable`; `Server::exec()` → `start()`; declare the dynamic
  `AuthBackend::$currentUser`; runtime TypeErrors from strict types if
  backends return nulls/wrong types (only visible with real data).
- PHP 8.4: Sonicle's code has no syntax errors, only deprecations. The
  `imap` extension is still needed (Z-Push mail backend, two Sonicle calls)
  and must come from PECL; its C library may not be packaged for the
  Debian 13 base of `php:8.4` — unverified.
- Licence: composer.json says AGPL-3.0-only; repos lack a LICENSE file.
  Z-Push is AGPLv3, sabre is BSD-3.

## Decisions

Made with the user:

- The fork lives inside `ns8-webtop`; built from upstream sources plus
  patch files.
- PHP 8.4.
- Our own port of Sonicle's released code; nothing from WT-1456.
- Behaviour parity; all current-stack findings and autodiscover dismissed.
- Maintenance: refresh the patch per Sonicle release; drop the fork when
  Sonicle supports PHP 8.
- **When fixed rules clash:** if the `imap` extension cannot be built for
  PHP 8.4 on any official `php:8.4-fpm` variant, fall back to PHP 8.3. If
  Z-Push 2.7.7 or sabre/dav 4.7.x has a PHP 8.x bug that breaks a test or
  logs a fatal, carry a temporary patch to that library, kept in its own
  clearly named patch file, listed in the README, and sent upstream.
- **Development and staging builds** (`VERSION` = `development-*` /
  `staging-*`, built from Sonicle's moving `develop` / `release` branches)
  apply the same patches. If a patch does not apply, the build fails with a
  message naming the patch, so Sonicle changes surface early.
- **Rollback is not supported:** going back to the PHP 7.3 images after the
  upgrade (or restoring a `z-push_state` backup taken after it into an
  older module) is out of scope; the release note says so. Add a check
  only if one turns out cheap.
- **Licence:** `webdav/` and `z-push/` get their own AGPL-3.0 LICENSE file
  and a notice that the patches modify Sonicle's AGPL code. Sonicle is
  informed, not asked for approval first.
- **Rollout:** a testing (pre-release) version first, used for a few days
  on real phones (iOS, Samsung, Gmail, Outlook with KOE) before stable.
- **Phase 0, before porting: extend the phone sync tests** on the current
  PHP 7.3 stack, green there first, so the oracle covers the most-used
  paths the port could break:
  - tasks over ActiveSync;
  - recurring and all-day events; contacts with phone numbers, emails,
    addresses and a photo (sabre 4 strict types bite on fields the
    current tests never send);
  - ActiveSync push (`Ping`): a change made in WebTop wakes a waiting phone;
  - the WebTop admin Devices panel data: `z-push-admin` output that
    WebTop's `ZPushManager` parses (`-a list`, `lastsync`, `list -u`),
    asserted on the fields WebTop reads.
  Manual checklist (not automated): an NS8 install migrated from NS7 with
  `Z_PUSH_USE_LEGACY_FOLDER_IDS=True`, and Outlook through KOE.

Claude's calls (user may override):

- **Where the patch is applied: at image build, not in `prep-sources`.**
  `prep-sources` and its Maven build stay untouched (and stay cached in CI).
  `build-images.sh` unpacks the Sonicle tgz in a builder container, drops
  its committed `vendor/`, applies our patch files, installs dependencies
  with Composer from our committed `composer.json` / `composer.lock`, and
  copies the result into the PHP 8.4 runtime image. The existing
  `webtop5-build/patches/` hook (applied inside Sonicle's Maven build) is
  not used.
- **Layout:** one directory per server, e.g. `webdav/` and `z-push/` at the
  repo root (next to `apache/`, `php/`), each with `composer.json`,
  `composer.lock` and `patches/NN-purpose.patch` (small, ordered, one
  purpose each: library bump, PHP 8 fixes, sabre 4 / Z-Push 2.7 adaptation,
  config). A `README.md` there explains how to refresh the patches for a new
  Sonicle release.
- **Z-Push** comes in through Composer as the upstream package at tag
  2.7.7 (no hand-copied tree), loaded the way Sonicle's code expects.
- **Library majors** stay as today unless PHP 8.4 or sabre 4.7 / Z-Push 2.7.7
  require a newer one; Renovate keeps `composer.lock` current.
- **Dead code** Sonicle ships but never uses (`php-awl/`,
  `backend/imap/config.php`, bundled unused Z-Push backends) is dropped from
  the image.
- **Version strings:** EAS derives `ZPUSH_VERSION` from its VERSION file;
  ours reports the Z-Push version actually shipped (2.7.7).
- **First step is a spike** that proves `imap` builds and loads on the chosen
  `php:8.4-fpm` variant (Debian or Alpine), before any porting. The base
  variant is picked by that spike.
- Existing PHP settings carry over: `zz-banner-grabbing.ini`,
  `zz-session-upload-progress.ini`, fpm pool sizes, memory limit, z-push
  fpm port 9001, the sabre/dav log-noise workaround (re-evaluated: drop if
  no longer needed).

## Done when

- Phase 0 tests exist and are green on the current PHP 7.3 images in CI.
- `webtop-webdav` and `webtop-z-push` images run PHP 8.4 with sabre/dav
  4.7.x and Z-Push 2.7.7 respectively.
- Module CI is green in both `install` and `update` scenarios with the
  phone sync tests unchanged, including `23_post_upgrade` (upgrade from the
  current stable module on PHP 7.3).
- Container logs show no PHP fatal errors or uncaught exceptions during the
  test run; deprecation notices are acceptable but not logged at error
  level in production.
- The refresh procedure in the README has been followed once from a clean
  checkout and works.
- The manual checklist (NS7-migrated install with legacy folder ids,
  Outlook with KOE) has been run on the testing release.
- The testing release has run for a few days on real phones without
  sync problems before it goes stable.

## Left to the builder

- The exact patch split and contents.
- Debian vs Alpine `php:8.4-fpm` variant (decided by the imap spike).
- How the builder container and Composer are pinned (image tags, Composer
  version).
- Whether the apache image still needs the DAV/EAS files
  (`build-images.sh` adds both tgz to it today) and in which form.
- How to keep PHP deprecation noise out of production logs.
- Base variant details found by the reviewer: Debian (bookworm/trixie) vs
  Alpine, the www-data uid change for the `z-push_state` volume (33 on
  Debian, 82 on Alpine) and how existing state files keep working, how the
  `z-push/z-push-dev` Composer package lands where Sonicle's code loads it,
  new Z-Push 2.7.7 config constants.
