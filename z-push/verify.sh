#!/bin/sh
#
# Verify a built ActiveSync server tree, inside the PHP runtime image: Z-Push
# version, required files, no patch leftovers or dead code, PHP syntax of
# Sonicle's code, the smoke test and z-push-admin. Usage: verify.sh <dir>
#
here=$(cd "$(dirname "$0")" && pwd)
dir=$1
fail=0

zpush=$(cat "$dir/vendor/z-push/z-push/src/version" 2>/dev/null)
if [ "$zpush" = "2.7.7" ]; then
    echo "ok: Z-Push $zpush"
else
    echo "FAIL: Z-Push is '${zpush:-missing}', expected 2.7.7"; fail=1
fi

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

if [ -e "$dir/php-awl" ]; then
    echo "FAIL: unused php-awl/ still shipped"; fail=1
else
    echo "ok: no unused php-awl/"
fi

# PHP reports deprecated declarations once, when OPcache first compiles a file,
# straight to the log and past Z-Push's error handler: Sonicle's code must have none
lint=$(find "$dir" -path "$dir/vendor" -prune -o -name '*.php' -print | \
        xargs -n1 php -d error_reporting=E_ALL -d display_errors=stdout -d log_errors=0 -l 2>&1)
if [ $? -ne 0 ]; then
    echo "FAIL: php -l errors in Sonicle code:"; printf '%s\n' "$lint" | grep -v '^No syntax errors'; fail=1
elif printf '%s\n' "$lint" | grep -q 'Deprecated:'; then
    echo "FAIL: PHP deprecations in Sonicle code:"; printf '%s\n' "$lint" | grep 'Deprecated:' | head -20; fail=1
else
    echo "ok: php -l on Sonicle code, no deprecations"
fi

# Z-Push's code that runs here (not its other backends): no deprecations either
zp="$dir/vendor/z-push/z-push/src"
lint=$({ find "$zp" -path "$zp/backend" -prune -o -name '*.php' -print
        ls "$zp"/backend/combined/*.php "$zp"/backend/imap/*.php; } | \
        xargs -n1 php -d error_reporting=E_ALL -d display_errors=stdout -d log_errors=0 -l 2>&1)
if printf '%s\n' "$lint" | grep -q 'Deprecated:'; then
    echo "FAIL: PHP deprecations in Z-Push:"; printf '%s\n' "$lint" | grep 'Deprecated:' | head -20; fail=1
else
    echo "ok: no deprecations in the Z-Push code in use"
fi

# The smoke test and z-push-admin need a config.json and writable state: run
# them on a scratch copy so the built tree stays as it is
scratch=$(mktemp -d)
chmod 755 "$scratch"
trap 'rm -rf "$scratch"' EXIT
cp -a "$dir" "$scratch/tree"
mkdir -p "$scratch/state" /var/log/z-push
cat > "$scratch/tree/config.json" <<EOF
{
    "timezone": "Europe/Rome",
    "log": {"level": "ERROR", "file": "php://stderr"},
    "mail": {"imapServer": "imap.smoke.test", "smtpServer": "smtp.smoke.test", "smtpPort": "25"},
    "webtop": {"apiBaseUrl": "http://127.0.0.1:18080/webtop"},
    "state": {"useLegacyFolderIds": false, "dir": "$scratch/state"}
}
EOF

if (cd "$scratch/tree" && php -d error_reporting="E_ALL & ~E_DEPRECATED" "$here/smoke.php"); then
    :
else
    echo "FAIL: smoke test"; fail=1
fi

# as in production: Z-Push refuses a state directory owned by root when run as root
chown -R www-data:www-data "$scratch/state" /var/log/z-push
admin=$(cd "$scratch/tree" && su -s /bin/sh www-data -c 'php z-push-admin.php -a list' 2>&1)
case "$admin" in
    *"no devices found"*|*"All synchronized devices"*) echo "ok: z-push-admin lists devices" ;;
    *) echo "FAIL: z-push-admin -a list: $admin"; fail=1 ;;
esac
exit $fail
