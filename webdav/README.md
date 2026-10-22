# WebTop WebDAV server on PHP 8.4

The `webtop-webdav` image runs Sonicle's WebTop DAV server (CalDAV and
CardDAV), built here instead of using Sonicle's package as is: Sonicle ships
it for PHP 7.3 with sabre/dav 3.2 and guzzle 6. This is a temporary fork:
when Sonicle releases a PHP 8 version, drop this directory and go back to
their package.

## Notice

Sonicle's WebTop DAV server is licensed under the GNU Affero General Public
License v3 (`AGPL-3.0-only`, see `LICENSE`). The patches in `patches/`
modify Sonicle's code and are distributed under the same licence. The
libraries installed by Composer keep their own licences (sabre/dav:
BSD-3-Clause).

## How the image is built

`build-images.sh` runs `build.sh` in the PHP runtime image
(`php:8.4.27-fpm-alpine`, with Composer and `patch`):

1. unpack Sonicle's `webtop5-build/webtop-dav-server-<version>.tgz`, the
   package selected by `webtop5-build/VERSION`;
2. compare Sonicle's `composer.json` and `composer.lock` with
   `sonicle-composer.sha256` and stop if they changed;
3. drop Sonicle's bundled `vendor/`, put our `composer.json` and
   `composer.lock` in its place;
4. apply `patches/*.patch` in order, stopping at the first one that does not
   apply;
5. `composer install --no-dev --classmap-authoritative`;
6. `verify.sh`: sabre/dav version, required files, no patch leftovers,
   `php -l` of Sonicle's code and `smoke.php`; the build fails if any check
   does.

The resulting tree goes into both the `webtop-webdav` and `webtop-apache`
images. `check-tree.sh <dir>` runs `verify.sh` on a tree from the host.

The base image is Alpine: on PHP 8.4.27 the `imap` extension, needed by the
ActiveSync server, builds and loads on both Alpine and Debian (2026-10-22),
and Alpine keeps the image family used before.

## Patches

| Patch | Why |
|---|---|
| `01-sabre-dav-4.patch` | sabre/dav 4: the exception logger also receives PHP errors (`\Throwable`); start the sabre server with `start()` |
| `02-php84.patch` | PHP 8.4: declare `AuthBackend::$currentUser`; pass log parameters as arrays (lf4php throws on a string under PHP 8); keep deprecation notices out of production logs |
| `03-guzzle-7.patch` | guzzle 7 (guzzle 6 is blocked by security advisories): the generated REST clients use `Utils::jsonEncode` and `Psr7\Query::build` |

Patches change only Sonicle's code. If a library needs a fix, add it as a
separate patch named `NN-temporary-<library>-<issue>.patch`, list it here and
report it upstream.

## Refreshing for a new Sonicle release

When `webtop5-build/VERSION` moves to a new release (or a development or
staging build uses Sonicle's moving branches) the build stops on the first
problem, with a message naming it:

- `patch NN-…patch does not apply to <version>`: unpack the new package,
  apply the patches one by one with `patch -p1`, fix the rejected hunks by
  hand and regenerate the patch with `diff -U1` (one line of context; labels `a/<path>` and
  `b/<path>`).
- `Sonicle changed composer.json` (or `composer.lock`): compare Sonicle's new
  dependency list with ours, update `composer.json`, regenerate
  `composer.lock` in the runtime image with the pinned Composer, then record
  the new hashes of the LF-normalised files:

  ```
  tar -xzf webtop5-build/webtop-dav-server-<version>.tgz ./composer.json ./composer.lock
  for f in composer.json composer.lock; do
      printf '%s  %s\n' "$(sed 's/\r$//' $f | sha256sum | cut -d' ' -f1)" $f
  done > webdav/sonicle-composer.sha256
  ```

Run `check-tree.sh` on the built tree and the phone sync tests
(`tests/40_carddav.robot`, `tests/41_caldav.robot`) before releasing.
