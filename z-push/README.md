# WebTop ActiveSync server on PHP 8.4

The `webtop-z-push` image runs Sonicle's WebTop EAS server (Exchange
ActiveSync, built on Z-Push), built here instead of using Sonicle's package
as is: Sonicle ships it for PHP 7.3 with a hand-copied Z-Push 2.4.5 and
guzzle 6. This is a temporary fork: when Sonicle releases a PHP 8 version,
drop this directory and go back to their package.

## Notice

Sonicle's WebTop EAS server is licensed under the GNU Affero General Public
License v3 (`AGPL-3.0-only`, see `LICENSE`). The patches in `patches/`
modify Sonicle's code and are distributed under the same licence. The
libraries installed by Composer keep their own licences (Z-Push: AGPL-3.0).

## How the image is built

`build-images.sh` installs the `imap` extension on `php:8.4.27-fpm-alpine`
and uses that base for both the builder and the `webtop-z-push` image. The
builder (with Composer and `patch`) runs `build.sh`:

1. unpack Sonicle's `webtop5-build/webtop-eas-server-<version>.tgz`, the
   package selected by `webtop5-build/VERSION`, with LF line endings;
2. compare Sonicle's `composer.json` and `composer.lock` with
   `sonicle-composer.sha256` and stop if they changed;
3. drop Sonicle's bundled `vendor/` (Z-Push 2.4.5 included) and code nothing
   loads (`php-awl/`, the unused copy of the IMAP settings in
   `backend/imap/`), put our `composer.json` and `composer.lock` in place;
4. apply `patches/*.patch` in order, stopping at the first one that does not
   apply;
5. `composer install --no-dev --classmap-authoritative`;
6. `verify.sh`: Z-Push version, required files, no patch leftovers or dead
   code, `php -l` of Sonicle's code, `smoke.php` (boots like `index.php`,
   loads the mail backend, converts an address and a contact photo) and
   `z-push-admin -a list` as `www-data`; the build fails if any check does.

The resulting tree goes into both the `webtop-z-push` and `webtop-apache`
images. `check-tree.sh <dir>` runs `verify.sh` on a tree from the host.

Z-Push 2.7.7 is not published on Packagist, so `composer.json` defines it as
a `package` repository (`z-push/z-push`, the GitHub tag archive), which
installs it unmodified at `vendor/z-push/z-push`, where Sonicle's code loads
it. Renovate cannot update such a package: for a new Z-Push release, change
`version`, `url` and `reference` (the tag's commit) and run
`composer update z-push/z-push`.

`www-data` keeps uid 82 (Alpine, as the PHP 7.3 image), so the
`z-push_state` volume needs no ownership change. Going back to the PHP 7.3
image after the upgrade is not supported.

## Patches

| Patch | Why |
|---|---|
| `01-z-push-2.7.patch` | Z-Push 2.7: report the Z-Push version actually installed; let Z-Push's IMAP backend load Sonicle's IMAP settings instead of its own defaults (PHP 8 warns on every constant defined twice) |
| `02-php84.patch` | PHP 8.4: keep deprecation notices out of the logs (and drop `E_STRICT`, itself deprecated); create a `Mail_RFC822` object instead of calling its method statically, which PHP 8 refuses |
| `03-guzzle-7.patch` | guzzle 7 (guzzle 6 is blocked by security advisories): the generated REST clients use `Utils::jsonEncode` and `Psr7\Query::build` |
| `04-no-data-uri.patch` | contact photos: build and parse `data:` URIs in a few lines instead of the `data-uri` library, whose only dependency, `symfony/http-foundation` 2-4, is blocked by security advisories |

Patches change only Sonicle's code. If a library needs a fix, add it as a
separate patch named `NN-temporary-<library>-<issue>.patch`, list it here and
report it upstream.

## Refreshing for a new Sonicle release

When `webtop5-build/VERSION` moves to a new release (or a development or
staging build uses Sonicle's moving branches) the build stops on the first
problem, with a message naming it:

- `patch NN-…patch does not apply to <version>`: unpack the new package,
  convert it to LF line endings (`sed -i 's/\r$//'` on the PHP files),
  apply the patches one by one with `patch -p1`, fix the rejected hunks by
  hand and regenerate the patch with `diff -U1` (one line of context; labels
  `a/<path>` and `b/<path>`).
- `Sonicle changed composer.json` (or `composer.lock`): compare Sonicle's new
  dependency list with ours, update `composer.json`, regenerate
  `composer.lock` in the runtime image with the pinned Composer, then record
  the new hashes of the LF-normalised files:

  ```
  tar -xzf webtop5-build/webtop-eas-server-<version>.tgz composer.json composer.lock
  for f in composer.json composer.lock; do
      printf '%s  %s\n' "$(sed 's/\r$//' $f | sha256sum | cut -d' ' -f1)" $f
  done > z-push/sonicle-composer.sha256
  ```

Run `check-tree.sh` on the built tree and the phone sync tests
(`tests/50_activesync.robot`, `tests/55_activesync_push.robot`,
`tests/60_devices_panel.robot`) before releasing.
