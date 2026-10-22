#!/bin/bash

# Terminate on error
set -e
cleanup_list=()
trap 'rm -rf "${cleanup_list[@]}"' EXIT

# Prepare variables for later use
images=()
# The image will be pushed to GitHub container registry
repobase="${REPOBASE:-ghcr.io/nethserver}"
#Get WebTop version
webtop_version=$(cat ${PWD}/webtop5-build/VERSION)

# Download of external deps and CHECKSUM verification:
if ! compgen -G "pecbridge-*.tar.gz"; then
    curl --netrc --fail -O "https://www.sonicle.com/nethesis/commercial/pecbridge/pecbridge-5.4.11.tar.gz"
fi
if ! sha256sum -c CHECKSUM; then
    echo "CHECKSUM to update: $(sha256sum pecbridge-*.tar.gz)"
    exit 1
fi

# Reuse existing webtopbuilder container, to speed up builds
if ! buildah containers --format "{{.ContainerName}}" | grep -q webtopbuilder; then
    echo "Pulling maven runtime..."
    buildah from --name webtopbuilder-tmp docker.io/library/maven:3.6-openjdk-8
    buildah run webtopbuilder-tmp  sed -i 's/deb.debian.org\|security.debian.org/archive.debian.org/' /etc/apt/sources.list
    buildah run webtopbuilder-tmp  apt-get  update
    buildah run webtopbuilder-tmp  apt-get  install -y  nodejs make
    buildah commit --rm webtopbuilder-tmp webtopbuilder-image
    buildah from --name webtopbuilder \
	    -v "${PWD}/webtop5-build:/webtop5-build:z" \
	    localhost/webtopbuilder-image
fi

if [ ! -e ${PWD}/webtop5-build/webtop-webapp-$webtop_version.war ]; then
    buildah run webtopbuilder sh -c "mkdir -p ~/.m2"
    buildah run webtopbuilder sh -c "cp webtop5-build/settings.xml  ~/.m2/"
    buildah run webtopbuilder sh -c "cd webtop5-build/ && ./prep-sources"
fi

if [ ! -e ${PWD}/webtop5-build/ListTimeZones.class ]; then
    buildah run webtopbuilder sh -c "cd webtop5-build/ && javac ListTimeZones.java"
fi

if [ ! -e ${PWD}/webtop5-build/WebtopPassEncode.class ]; then
    buildah run webtopbuilder sh -c "cd webtop5-build/ && javac WebtopPassEncode.java"
fi

jcharset_tmp_dir=$(mktemp -d)
cleanup_list+=("${jcharset_tmp_dir}")
(
    cd "${jcharset_tmp_dir}"
    echo "Downloading jcharset-2.0.jar..."
    curl -O https://distfeed.nethserver.org/webtop/jcharset-2.0.jar
)

webapp_tmp_dir=$(mktemp -d)
cleanup_list+=("${webapp_tmp_dir}")
(
    mkdir -p "${webapp_tmp_dir}/webtop/"
    python -mzipfile -e  ${PWD}/webtop5-build/webtop-webapp-$webtop_version.war "${webapp_tmp_dir}/webtop/"
)

pecbridge_tmp_dir=$(mktemp -d)
cleanup_list+=("${pecbridge_tmp_dir}")
tar -C "${pecbridge_tmp_dir}" -x -v -z -f pecbridge-*.tar.gz

#Create webtop-webapp container
reponame="webtop-webapp"
container=$(buildah from docker.io/library/tomcat:9.0.123-jre8)
buildah add ${container} ${webapp_tmp_dir}/webtop /usr/local/tomcat/webapps/webtop/
buildah add ${container} ${PWD}/webtop5-build/context.xml /usr/local/tomcat/webapps/webtop/META-INF/context.xml
buildah add ${container} ${PWD}/webtop5-build/webtop-login/ /usr/local/tomcat/webapps/webtop/WEB-INF/classes/
buildah add ${container} ${jcharset_tmp_dir}/jcharset-2.0.jar /opt/java/openjdk/lib/ext/
buildah add ${container} ${PWD}/webtop5-build/ListTimeZones.class /usr/share/webtop/
buildah add ${container} ${PWD}/webtop5-build/WebtopPassEncode.class /usr/share/webtop/
buildah add ${container} ${PWD}/zfaker/wrappers/php /usr/share/webtop/bin/php
buildah add ${container} ${PWD}/zfaker/wrappers/z-push-admin-wapper /usr/share/webtop/bin/z-push-admin-wrapper
buildah add ${container} ${pecbridge_tmp_dir}/pecbridge /usr/share/pecbridge
buildah add ${container} ${PWD}/webapp/ /
# Hide Tomcat version from error pages; fail if the valve was not added
buildah run ${container} sh -c "sed -i 's|</Host>|  <Valve className=\"org.apache.catalina.valves.ErrorReportValve\" showReport=\"false\" showServerInfo=\"false\" />\\n      </Host>|' /usr/local/tomcat/conf/server.xml && grep -q 'ErrorReportValve' /usr/local/tomcat/conf/server.xml"
# Commit the image
buildah commit --rm "${container}" "${repobase}/${reponame}"

# Append the image URL to the images array
images+=("${repobase}/${reponame}")

#Create webtop-postgres container
reponame="webtop-postgres"
container=$(buildah from docker.io/library/postgres:17.11)
buildah add ${container} ${PWD}/webtop5-build/sql-scripts-$webtop_version.tar.gz /docker-entrypoint-initdb.d/
buildah add ${container} ${PWD}/postgres/data /docker-entrypoint-initdb.d/data
buildah add ${container} ${PWD}/postgres/postgres /docker-entrypoint-initdb.d/postgres
buildah add ${container} ${PWD}/postgres/webtop-init.sh /docker-entrypoint-initdb.d/
buildah run ${container} chmod 755 /docker-entrypoint-initdb.d
buildah config -e POSTGRES_DB=webtop5 ${container}
# Commit the image
buildah commit --rm "${container}" "${repobase}/${reponame}"

# Append the image URL to the images array
images+=("${repobase}/${reponame}")


# Build Sonicle's WebDAV server for PHP 8.4 (see webdav/README.md); both the
# apache and the webdav images need the same tree
webdav_php_image="docker.io/library/php:8.4.27-fpm-alpine"
webdav_tree=$(mktemp -d)
cleanup_list+=("${webdav_tree}")
container=$(buildah from ${webdav_php_image})
buildah copy --from=docker.io/library/composer:2.10.3 ${container} /usr/bin/composer /usr/local/bin/composer
buildah run ${container} sh -c "apk add --no-cache patch"
buildah run \
    -v "${PWD}/webdav:/webdav:ro,z" \
    -v "${PWD}/webtop5-build:/webtop5-build:ro,z" \
    -v "${webdav_tree}:/out:z" \
    ${container} sh /webdav/build.sh /webtop5-build/webtop-dav-server-$webtop_version.tgz /out
buildah rm ${container}

# Build Sonicle's ActiveSync server for PHP 8.4 (see z-push/README.md) on a
# base with the imap extension, shared by the builder (its checks run
# z-push-admin) and the runtime image; apache needs the same tree
container=$(buildah from ${webdav_php_image})
buildah copy --from=docker.io/mlocati/php-extension-installer:2.11.34 ${container} /usr/bin/install-php-extensions /usr/local/bin/
buildah run ${container} sh -c "install-php-extensions imap"
zpush_php_image=$(buildah commit -q --rm ${container})
zpush_tree=$(mktemp -d)
cleanup_list+=("${zpush_tree}")
container=$(buildah from ${zpush_php_image})
buildah copy --from=docker.io/library/composer:2.10.3 ${container} /usr/bin/composer /usr/local/bin/composer
buildah run ${container} sh -c "apk add --no-cache patch"
buildah run \
    -v "${PWD}/z-push:/z-push:ro,z" \
    -v "${PWD}/webtop5-build:/webtop5-build:ro,z" \
    -v "${zpush_tree}:/out:z" \
    ${container} sh /z-push/build.sh /webtop5-build/webtop-eas-server-$webtop_version.tgz /out
buildah rm ${container}

#Create webtop-apache container
reponame="webtop-apache"
container=$(buildah from docker.io/library/httpd:2.4.69)
buildah add ${container} ${PWD}/apache/vhosts/ /usr/local/apache2/conf.d/
buildah add ${container} ${PWD}/apache/httpd.conf /usr/local/apache2/conf
buildah add ${container} ${webdav_tree} /usr/share/webtop/webdav/
buildah add ${container} ${zpush_tree} /usr/share/webtop/z-push/
buildah add ${container} ${PWD}/zfaker/src/ /usr/share/webtop/zfacker/
# Commit the image
buildah commit --rm "${container}" "${repobase}/${reponame}"

# Append the image URL to the images array
images+=("${repobase}/${reponame}")


#Create webtop-webdav container
reponame="webtop-webdav"
container=$(buildah from ${webdav_php_image})
buildah add ${container} ${webdav_tree} /usr/share/webtop/webdav/
buildah run ${container} sh -c "mv \$PHP_INI_DIR/php.ini-production \$PHP_INI_DIR/php.ini"
buildah add ${container} ${PWD}/php/zz-banner-grabbing.ini /usr/local/etc/php/conf.d/zz-banner-grabbing.ini
buildah add ${container} ${PWD}/php/zz-session-upload-progress.ini /usr/local/etc/php/conf.d/zz-session-upload-progress.ini
buildah add ${container} ${PWD}/php/zz-fpm-mitigations.ini /usr/local/etc/php/conf.d/zz-fpm-mitigations.ini
buildah add ${container} ${PWD}/php/zz-webdav.ini /usr/local/etc/php/conf.d/zz-webdav.ini
# Pool sizes, and one request per worker: mitigates CVE-2026-109619 (stale
# state reused by the next request). Fail if the stock www.conf no longer has
# the lines we change
buildah run ${container} sh -c "sed -i 's/pm.max_children = 5/pm.max_children = 40/; s/pm.start_servers = 2/pm.start_servers = 5/; s/pm.min_spare_servers = 1/pm.min_spare_servers = 5/; s/pm.max_spare_servers = 3/pm.max_spare_servers = 30/; s/;pm.max_requests = 500/pm.max_requests = 1/' /usr/local/etc/php-fpm.d/www.conf"
for setting in 'pm.max_children = 40' 'pm.start_servers = 5' 'pm.min_spare_servers = 5' 'pm.max_spare_servers = 30' '^pm.max_requests = 1$'; do
    buildah run ${container} grep -q "${setting}" /usr/local/etc/php-fpm.d/www.conf
done
# Hide the per-request "child exited" and "child started" notices
buildah run ${container} sh -c "sed -i 's/;log_level = notice/log_level = warning/' /usr/local/etc/php-fpm.conf"
buildah run ${container} grep -q '^log_level = warning$' /usr/local/etc/php-fpm.conf
# Commit the image
buildah commit --rm "${container}" "${repobase}/${reponame}"

# Append the image URL to the images array
images+=("${repobase}/${reponame}")

#Create webtop-z-push container
reponame="webtop-z-push"
container=$(buildah from ${zpush_php_image})
# The PHP modules the PHP 7.3 image had (but ftp, which nothing calls):
# Sonicle's code and Z-Push call into them
for module in ctype curl date dom fileinfo filter hash iconv imap json libxml mbstring mysqlnd openssl pcre PDO pdo_sqlite Phar posix readline Reflection session SimpleXML sodium SPL sqlite3 standard tokenizer xml xmlreader xmlwriter zlib; do
    buildah run ${container} sh -c "php -m | grep -qx ${module}" || { echo "PHP module ${module} missing from the z-push image" >&2; exit 1; }
done
buildah add ${container} ${zpush_tree} /usr/share/webtop/z-push/
buildah add ${container} ${PWD}/zfaker/src/ /usr/share/webtop/zfacker/
buildah run ${container} sh -c "mv \$PHP_INI_DIR/php.ini-production \$PHP_INI_DIR/php.ini"
buildah add ${container} ${PWD}/php/zz-banner-grabbing.ini /usr/local/etc/php/conf.d/zz-banner-grabbing.ini
buildah add ${container} ${PWD}/php/zz-session-upload-progress.ini /usr/local/etc/php/conf.d/zz-session-upload-progress.ini
buildah add ${container} ${PWD}/php/zz-fpm-mitigations.ini /usr/local/etc/php/conf.d/zz-fpm-mitigations.ini
buildah run ${container} sh -c "mkdir -p /var/log/z-push/state && chown www-data:www-data /var/log/z-push /var/log/z-push/state"
# Pool sizes, memory, and one request per worker: mitigates CVE-2026-109619
# (stale state reused by the next request). Fail if the stock files no longer
# have the lines we change
buildah run ${container} sh -c "sed -i 's/pm.max_children = 5/pm.max_children = 50/; s/pm.start_servers = 2/pm.start_servers = 5/; s/pm.min_spare_servers = 1/pm.min_spare_servers = 5/; s/pm.max_spare_servers = 3/pm.max_spare_servers = 35/; s/;pm.max_requests = 500/pm.max_requests = 1/; s/;php_admin_value\[memory_limit\] = 32M/php_admin_value[memory_limit] = 512M/' /usr/local/etc/php-fpm.d/www.conf"
for setting in 'pm.max_children = 50' 'pm.start_servers = 5' 'pm.min_spare_servers = 5' 'pm.max_spare_servers = 35' '^pm.max_requests = 1$' '^php_admin_value\[memory_limit\] = 512M$'; do
    buildah run ${container} grep -q "${setting}" /usr/local/etc/php-fpm.d/www.conf
done
# Port 9001, as webdav in the same pod has 9000: fail if php-fpm would still
# listen on 9000 anywhere (the official image moved the setting before)
buildah run ${container} sh -c "sed -i 's/^listen = 9000$/listen = 9001/' /usr/local/etc/php-fpm.d/docker.conf"
buildah run ${container} sh -c "grep -q '^listen = 9001$' /usr/local/etc/php-fpm.d/docker.conf && ! grep -rq '^listen = 9000' /usr/local/etc/php-fpm.d/"
# Hide the per-request "child exited" and "child started" notices
buildah run ${container} sh -c "sed -i 's/;log_level = notice/log_level = warning/' /usr/local/etc/php-fpm.conf"
buildah run ${container} grep -q '^log_level = warning$' /usr/local/etc/php-fpm.conf
# Commit the image
buildah commit --rm "${container}" "${repobase}/${reponame}"
buildah rmi ${zpush_php_image}

# Append the image URL to the images array
images+=("${repobase}/${reponame}")

reponame="webtop-phonebook"
container=$(buildah from docker.io/library/php:8.4.27-cli-alpine)
buildah copy --from=docker.io/mlocati/php-extension-installer:2.12.3 ${container} /usr/bin/install-php-extensions /usr/local/bin/
buildah run ${container} sh -c "install-php-extensions pgsql mysqli"
buildah add ${container} ${PWD}/phonebook/webtop2phonebook.php /usr/share/phonebooks/scripts/
buildah add ${container} ${PWD}/phonebook/pbook2webtop.php /usr/share/phonebooks/post_scripts/
buildah add ${container} ${PWD}/phonebook/start.sh /usr/share/phonebooks/
buildah add ${container} ${PWD}/php/zz-session-upload-progress.ini /usr/local/etc/php/conf.d/zz-session-upload-progress.ini
buildah config --cmd /usr/share/phonebooks/start.sh ${container}
# Commit the image
buildah commit --rm "${container}" "${repobase}/${reponame}"

# Append the image URL to the images array
images+=("${repobase}/${reponame}")

# Configure the image name
reponame="webtop"

# Create a new empty container image
container=$(buildah from scratch)

# Reuse existing nodebuilder-webtop container, to speed up builds
if ! buildah containers --format "{{.ContainerName}}" | grep -q nodebuilder-webtop; then
    echo "Pulling NodeJS runtime..."
    buildah from --name nodebuilder-webtop -v "${PWD}:/usr/src:Z" docker.io/library/node:24.22.0-slim
fi

echo "Build static UI files with node..."
buildah run --env="NODE_OPTIONS=--openssl-legacy-provider" nodebuilder-webtop sh -c "cd /usr/src/ui && corepack enable && yarn install && yarn build"

# Add imageroot directory to the container image
buildah add "${container}" imageroot /imageroot
buildah add "${container}" ui/dist /ui
# Setup the entrypoint, ask to reserve one TCP port with the label and set a rootless container
buildah config --entrypoint=/ \
    --label="org.nethserver.authorizations=traefik@node:routeadm mail@any:mailadm cluster:accountconsumer nethvoice@any:pbookreader" \
    --label="org.nethserver.min-core=3.20.1" \
    --label="org.nethserver.tcp-ports-demand=1" \
    --label="org.nethserver.rootfull=0" \
    --label="org.nethserver.min-from=1.4.4" \
    --label="org.nethserver.images=${repobase}/webtop-webapp:${IMAGETAG:-latest} \
    ${repobase}/webtop-postgres:${IMAGETAG:-latest} \
    ${repobase}/webtop-apache:${IMAGETAG:-latest} \
    ${repobase}/webtop-webdav:${IMAGETAG:-latest} \
    ${repobase}/webtop-z-push:${IMAGETAG:-latest} \
    ${repobase}/webtop-phonebook:${IMAGETAG:-latest}" \
    "${container}"
# Commit the image
buildah commit "${container}" "${repobase}/${reponame}"

# Append the image URL to the images array
images+=("${repobase}/${reponame}")

#
# NOTICE:
#
# It is possible to build and publish multiple images.
#
# 1. create another buildah container
# 2. add things to it and commit it
# 3. append the image url to the images array
#

#
# Setup CI when pushing to Github. 
# Warning! docker::// protocol expects lowercase letters (,,)
if [[ -n "${CI}" ]]; then
    # Set output value for Github Actions
    echo "images=${images[*],,}" >> "$GITHUB_OUTPUT"
else
    # Just print info for manual push
    printf "Publish the images with:\n\n"
    for image in "${images[@],,}"; do printf "  buildah push %s docker://%s:%s\n" "${image}" "${image}" "${IMAGETAG:-latest}" ; done
    printf "\n"
fi
