#!/bin/bash

#
# Copyright (C) 2023 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#

# Terminate on error
set -e

# Prepare variables for later use
images=()
# The image will be pushed to GitHub container registry
repobase="${REPOBASE:-ghcr.io/phillopp}"
# Configure the image name
reponame="typo3"

# TYPO3-Image
typo3container=$(buildah from php:8.4-apache)
buildah run $typo3container -- apt-get update -yqq
buildah run $typo3container -- apt-get install git gettext libcurl4-gnutls-dev libicu-dev libmcrypt-dev libvpx-dev libjpeg-dev libpng-dev libxpm-dev zlib1g-dev libfreetype6-dev libxml2-dev libexpat1-dev libbz2-dev libgmp3-dev libldap2-dev unixodbc-dev libpq-dev libsqlite3-dev libaspell-dev libsnmp-dev libpcre3-dev libtidy-dev libzip-dev zip cron libmemcached-dev libssl-dev -yqq
buildah run $typo3container -- docker-php-ext-install pdo_pgsql curl intl gd xml zip bz2 opcache

buildah add $typo3container https://getcomposer.org/installer ./composer-setup.php
buildah run $typo3container -- php composer-setup.php
buildah run $typo3container -- php -r "unlink('composer-setup.php');"
buildah run $typo3container -- mv composer.phar /usr/local/bin/composer

buildah run $typo3container -- composer create-project typo3/cms-base-distribution typo3-project "^13"

buildah config --env APACHE_DOCUMENT_ROOT=/var/www/html/typo3 $typo3container

buildah run $typo3container -- sed -ri -e 's!/var/www/html!/var/www/html/typo3!g' /etc/apache2/sites-available/*.conf
buildah run $typo3container -- sed -ri -e 's!/var/www/!/var/www/html/typo3!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf

buildah commit "${typo3container}" "${repobase}/${reponame}-app"

# Append the image URL to the images array
images+=("${repobase}/${reponame}-app")

# Create a new empty container image
container=$(buildah from scratch)

# Reuse existing nodebuilder-typo3 container, to speed up builds
if ! buildah containers --format "{{.ContainerName}}" | grep -q nodebuilder-typo3; then
    echo "Pulling NodeJS runtime..."
    buildah from --name nodebuilder-typo3 -v "${PWD}:/usr/src:Z" docker.io/library/node:lts
fi

echo "Build static UI files with node..."
buildah run \
    --workingdir=/usr/src/ui \
    --env="NODE_OPTIONS=--openssl-legacy-provider" \
    nodebuilder-typo3 \
    sh -c "yarn install && yarn build"

# Add imageroot directory to the container image
buildah add "${container}" imageroot /imageroot
buildah add "${container}" ui/dist /ui
# Setup the entrypoint, ask to reserve one TCP port with the label and set a rootless container
# Select you image(s) with the label org.nethserver.images
# ghcr.io/xxxxx is the GitHub container registry or your own registry or docker.io for Docker Hub
# The image tag is set to latest by default, but can be overridden with the IMAGETAG environment variable
# --label="org.nethserver.images=docker.io/mariadb:10.11.5 docker.io/roundcube/roundcubemail:1.6.4-apache"
# rootfull=0 === rootless container
# tcp-ports-demand=1 number of tcp Port to reserve , 1 is the minimum, can be udp or tcp
buildah config --entrypoint=/ \
    --label="org.nethserver.authorizations=traefik@node:routeadm" \
    --label="org.nethserver.tcp-ports-demand=1" \
    --label="org.nethserver.rootfull=0" \
    --label="org.nethserver.images=docker.io/postgres:15.8-alpine3.19 ghcr.io/phillopp/typo3-app:latest" \
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
    printf "images=%s\n" "${images[*],,}" >> "${GITHUB_OUTPUT}"
else
    # Just print info for manual push
    printf "Publish the images with:\n\n"
    for image in "${images[@],,}"; do printf "  buildah push %s docker://%s:%s\n" "${image}" "${image}" "${IMAGETAG:-latest}" ; done
    printf "\n"
fi
