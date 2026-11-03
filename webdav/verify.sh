#!/bin/sh
#
# Verify a built WebDAV server tree, inside the PHP runtime image: library
# versions, required files, no patch leftovers, PHP syntax of Sonicle's code
# and the smoke test. Usage: verify.sh <dir>
#
here=$(cd "$(dirname "$0")" && pwd)
dir=$1
fail=0

sabre=$(sed -n "s/.*const VERSION = '\([^']*\)'.*/\1/p" "$dir/vendor/sabre/dav/lib/DAV/Version.php" 2>/dev/null)
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

# Apache serves the tree: patch backups or rejects would be readable by anyone
leftovers=$(find "$dir" -path "$dir/vendor" -prune -o \( -name '*.orig' -o -name '*.rej' \) -print)
if [ -n "$leftovers" ]; then
    echo "FAIL: patch leftovers: $leftovers"; fail=1
else
    echo "ok: no patch leftovers"
fi

if find "$dir" -path "$dir/vendor" -prune -o -name '*.php' -print | \
        xargs -n1 php -d error_reporting="E_ALL & ~E_DEPRECATED" -l >/dev/null; then
    echo "ok: php -l on Sonicle code"
else
    echo "FAIL: php -l errors in Sonicle code"; fail=1
fi

if (cd "$dir" && php -d error_reporting=E_ALL "$here/smoke.php"); then
    :
else
    echo "FAIL: smoke test"; fail=1
fi
exit $fail
