#!/bin/bash
#
# Run verify.sh on a built ActiveSync server tree from the host, on the same
# base as the image: PHP with the imap and intl extensions. build.sh runs the
# same checks at the end of every build.
# Usage: check-tree.sh <dir>
#
set -e -o pipefail
dir=$(realpath "$1")
here=$(realpath "$(dirname "$0")")
php_image=${PHP_IMAGE:-docker.io/library/php:8.4.27-fpm-alpine}
container=$(buildah from -q "$php_image")
trap 'buildah rm "$container" >/dev/null' EXIT
buildah copy -q --from=docker.io/mlocati/php-extension-installer:2.11.34 "$container" /usr/bin/install-php-extensions /usr/local/bin/ >/dev/null
buildah run "$container" sh -c "install-php-extensions imap intl >/dev/null"
buildah run -v "$dir:/src:ro,Z" -v "$here:/z-push:ro,Z" "$container" sh /z-push/verify.sh /src
