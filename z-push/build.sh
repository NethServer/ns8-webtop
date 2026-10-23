#!/bin/sh
#
# Build Sonicle's ActiveSync server for PHP 8.4: unpack the package, check
# that Sonicle did not change the dependency files we replace, drop the bundled
# libraries (Z-Push 2.4.5 included) and unused code, apply our patches and
# install our locked dependencies.
# Runs inside the PHP runtime image with composer and patch available.
# Usage: build.sh <webtop-eas-server.tgz> <output dir>
#
set -e
here=$(cd "$(dirname "$0")" && pwd)
package=$1
out=$2

rm -rf "${out:?}"/* "$out"/.[!.]* 2>/dev/null || :
tar -xzf "$package" -C "$out"
version=$(cat "$out/VERSION" 2>/dev/null || echo unknown)

# Sonicle is moving its sources from CRLF to LF line endings: normalise
# them so the checks and patches below do not depend on that
find "$out" -path "$out/vendor" -prune -o -type f \( -name '*.php' -o -name 'composer.json' -o -name 'composer.lock' \) \
    -exec sed -i 's/\r$//' {} +

# Our composer files replace Sonicle's: a new dependency there must be noticed
# (hashes of the LF-normalised files)
for file in composer.json composer.lock; do
    expected=$(awk -v f="$file" '$2 == f {print $1}' "$here/sonicle-composer.sha256")
    actual=$(sha256sum "$out/$file" | cut -d' ' -f1)
    if [ "$expected" != "$actual" ]; then
        echo "Sonicle changed $file in $version: review the dependency overlay (see z-push/README.md)" >&2
        exit 1
    fi
done

# Sonicle's bundled libraries (Z-Push 2.4.5 included), and code nothing loads:
# an old copy of Andrew's Web Libraries (Z-Push ships its own iCalendar) and a
# copy of the IMAP settings (backend/wtimap/config.php is the one in use)
rm -rf "$out/vendor" "$out/php-awl" "$out/backend/imap"
cp "$here/composer.json" "$here/composer.lock" "$out/"

# Apply patches in order: Sonicle's code before the libraries are installed,
# NN-temporary-<library>-*.patch (fixes to a library) after
apply_patches() {
    for p in "${ZPUSH_PATCHES:-$here/patches}"/*.patch; do
        [ -e "$p" ] || continue
        case "$(basename "$p")" in
            *-temporary-*) [ "$1" = libraries ] || continue ;;
            *) [ "$1" = sonicle ] || continue ;;
        esac
        echo "applying $(basename "$p")"
        if ! patch -d "$out" -p1 --forward --batch --no-backup-if-mismatch < "$p"; then
            echo "patch $(basename "$p") does not apply to $version (see z-push/README.md)" >&2
            exit 1
        fi
    done
}

apply_patches sonicle
(cd "$out" && composer install --no-dev --classmap-authoritative --no-interaction --no-progress)
apply_patches libraries

if ! sh "$here/verify.sh" "$out"; then
    echo "the built ActiveSync server failed its checks (see z-push/README.md)" >&2
    exit 1
fi
