#!/bin/sh
#
# Build Sonicle's WebDAV server for PHP 8.4: unpack the package, check that
# Sonicle did not change the dependency files we replace, drop the bundled
# libraries, apply our patches and install our locked dependencies.
# Runs inside the PHP runtime image with composer and patch available.
# Usage: build.sh <webtop-dav-server.tgz> <output dir>
#
set -e
here=$(cd "$(dirname "$0")" && pwd)
package=$1
out=$2

rm -rf "${out:?}"/* "$out"/.[!.]* 2>/dev/null || :
tar -xzf "$package" -C "$out"
version=$(cat "$out/VERSION" 2>/dev/null || echo unknown)

# Our composer files replace Sonicle's: a new dependency there must be noticed
for file in composer.json composer.lock; do
    expected=$(awk -v f="$file" '$2 == f {print $1}' "$here/sonicle-composer.sha256")
    actual=$(sha256sum "$out/$file" | cut -d' ' -f1)
    if [ "$expected" != "$actual" ]; then
        echo "Sonicle changed $file in $version: review the dependency overlay (see webdav/README.md)" >&2
        exit 1
    fi
done

rm -rf "$out/vendor"
cp "$here/composer.json" "$here/composer.lock" "$out/"

for p in "$here"/patches/*.patch; do
    [ -e "$p" ] || continue
    if ! patch -d "$out" -p1 --forward --batch --silent < "$p"; then
        echo "patch $(basename "$p") does not apply to $version (see webdav/README.md)" >&2
        exit 1
    fi
done

cd "$out"
composer install --no-dev --classmap-authoritative --no-interaction --no-progress
