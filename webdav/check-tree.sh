#!/bin/bash
#
# Check a built WebDAV server tree: library versions, required files and
# PHP syntax of Sonicle's code on the runtime PHP. Usage: check-tree.sh <dir>
#
set -e -o pipefail
dir=$(realpath "$1")
here=$(realpath "$(dirname "$0")")
php_image=${PHP_IMAGE:-docker.io/library/php:8.4.27-fpm-alpine}
fail=0

sabre=$(sed -n "s/.*const VERSION = '\([^']*\)'.*/\1/p" "$dir/vendor/sabre/dav/lib/DAV/Version.php" 2>/dev/null || true)
case "$sabre" in
    4.7.*) echo "ok: sabre/dav $sabre" ;;
    *) echo "FAIL: sabre/dav is '${sabre:-missing}', expected 4.7.x"; fail=1 ;;
esac

# guzzle's RedirectMiddleware needs it; Sonicle's bundle lacks it
if [ -f "$dir/vendor/guzzlehttp/psr7/src/UriComparator.php" ]; then
    echo "ok: guzzlehttp/psr7 UriComparator present"
else
    echo "FAIL: guzzlehttp/psr7 src/UriComparator.php missing"; fail=1
fi

if podman run --rm -v "$dir:/src:ro,Z" "$php_image" sh -c \
    'find /src -name "*.php" -not -path "/src/vendor/*" -print0 | xargs -0 -n1 php -d error_reporting="E_ALL & ~E_DEPRECATED" -l >/dev/null'; then
    echo "ok: php -l on Sonicle code"
else
    echo "FAIL: php -l errors in Sonicle code"; fail=1
fi
if podman run --rm -v "$dir:/src:ro,Z" -v "$here/smoke.php:/smoke.php:ro,Z" -w /src "$php_image" \
    php -d error_reporting=E_ALL /smoke.php; then
    :
else
    echo "FAIL: smoke test"; fail=1
fi
exit $fail
