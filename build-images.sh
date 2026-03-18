#!/bin/bash

# Terminate on error
set -e

# Prepare variables for later use
images=()
# The image will be pushed to GitHub container registry
repobase="${REPOBASE:-ghcr.io/nethserver}"

#Create webtop-webapp container
reponame="webtop-webapp"
# Bitnami no longer usable, reuse existing published image
buildah pull "ghcr.io/nethserver/webtop-webapp:1.4.4"
buildah tag "ghcr.io/nethserver/webtop-webapp:1.4.4" "${repobase}/${reponame}"

# Append the image URL to the images array
images+=("${repobase}/${reponame}")

#Create webtop-postgres container
reponame="webtop-postgres"
# Bitnami no longer usable, reuse existing published image
buildah pull "ghcr.io/nethserver/webtop-postgres:1.4.4"
buildah tag "ghcr.io/nethserver/webtop-postgres:1.4.4" "${repobase}/${reponame}"

# Append the image URL to the images array
images+=("${repobase}/${reponame}")


#Create webtop-apache container
reponame="webtop-apache"
# Bitnami no longer usable, reuse existing published image
buildah pull "ghcr.io/nethserver/webtop-apache:1.4.4"
buildah tag "ghcr.io/nethserver/webtop-apache:1.4.4" "${repobase}/${reponame}"

# Append the image URL to the images array
images+=("${repobase}/${reponame}")


#Create webtop-webdav container
reponame="webtop-webdav"
# Bitnami no longer usable, reuse existing published image
buildah pull "ghcr.io/nethserver/webtop-webdav:1.4.4"
buildah tag "ghcr.io/nethserver/webtop-webdav:1.4.4" "${repobase}/${reponame}"

# Append the image URL to the images array
images+=("${repobase}/${reponame}")

#Create webtop-z-push container
reponame="webtop-z-push"
# Bitnami no longer usable, reuse existing published image
buildah pull "ghcr.io/nethserver/webtop-z-push:1.4.4"
buildah tag "ghcr.io/nethserver/webtop-z-push:1.4.4" "${repobase}/${reponame}"

# Append the image URL to the images array
images+=("${repobase}/${reponame}")

reponame="webtop-phonebook"
# Bitnami no longer usable, reuse existing published image
buildah pull "ghcr.io/nethserver/webtop-phonebook:1.4.4"
buildah tag "ghcr.io/nethserver/webtop-phonebook:1.4.4" "${repobase}/${reponame}"

# Append the image URL to the images array
images+=("${repobase}/${reponame}")

# Configure the image name
reponame="webtop"

# Create a new empty container image
container=$(buildah from scratch)

# Reuse existing nodebuilder-webtop container, to speed up builds
if ! buildah containers --format "{{.ContainerName}}" | grep -q nodebuilder-webtop; then
    echo "Pulling NodeJS runtime..."
    buildah from --name nodebuilder-webtop -v "${PWD}:/usr/src:Z" docker.io/library/node:22.16.0-slim
fi

echo "Build static UI files with node..."
buildah run --env="NODE_OPTIONS=--openssl-legacy-provider" nodebuilder-webtop sh -c "cd /usr/src/ui && yarn install && yarn build"

# Add imageroot directory to the container image
buildah add "${container}" imageroot /imageroot
buildah add "${container}" ui/dist /ui
# Setup the entrypoint, ask to reserve one TCP port with the label and set a rootless container
buildah config --entrypoint=/ \
    --label="org.nethserver.authorizations=traefik@node:routeadm mail@any:mailadm cluster:accountconsumer nethvoice@any:pbookreader" \
    --label="org.nethserver.tcp-ports-demand=1" \
    --label="org.nethserver.rootfull=0" \
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
