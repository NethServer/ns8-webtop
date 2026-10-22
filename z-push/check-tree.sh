#!/bin/bash
#
# Run verify.sh on a built ActiveSync server tree in the PHP runtime image, from
# the host. build.sh runs the same checks at the end of every build.
# Usage: check-tree.sh <dir>
#
set -e -o pipefail
dir=$(realpath "$1")
here=$(realpath "$(dirname "$0")")
php_image=${PHP_IMAGE:-docker.io/library/php:8.4.27-fpm-alpine}
podman run --rm -v "$dir:/src:ro,Z" -v "$here:/z-push:ro,Z" "$php_image" sh /z-push/verify.sh /src
