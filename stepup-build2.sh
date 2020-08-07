#!/bin/bash

# Copyright 2015 SURFnet bv
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

CWD=`pwd`
COMPONENTS=("Stepup-Middleware" "Stepup-Gateway" "Stepup-SelfService" "Stepup-RA" "Stepup-tiqr" "Stepup-Webauthn" "oath-service-php"  "Stepup-Azure-MFA")
BUILD_ENV=build
SYMFONY_ENV=prod

bold=$(tput bold)
normal=$(tput sgr0)
white=$(tput setaf 7)
gray=$(tput setaf 10)


function error_exit {
    echo "${1}"
    if [ -n "${TMP_ARCHIVE_DIR}" -a -d "${TMP_ARCHIVE_DIR}" ]; then
        rm -r "${TMP_ARCHIVE_DIR}"
    fi
    cd ${CWD}
    exit 1
}

function command {
    echo ""
    cur_dir=`pwd`
    # emulate terminal prompt to let command standout
    echo "${gray}[`whoami`@`hostname` `dirname $cur_dir`]$ ${white}${bold}${1}${normal}"
    ${1}
    rv=$?
    if [ $rv -ne 0 ]; then
      echo "Command failed with code $rv"
    fi
    return $rv
}

# Process options
OUTPUT_DIR=$1
if [ ! -d ${OUTPUT_DIR} ]; then
    error_exit "Output dir does not exist"
fi
shift
cd ${OUTPUT_DIR}
OUTPUT_DIR=`pwd`
echo "Using output dir: ${OUTPUT_DIR}"
cd ${CWD}

COMPONENT=$1
shift
if [ -z "${COMPONENT}"  ]; then
    echo "Usage: $0 <output dir> <component> (<TAG or BRANCH name>)"
    echo "Components: ${COMPONENTS[*]}"
    exit 1;
fi

found=0
for comp in "${COMPONENTS[@]}"; do
    if [ "$comp" = "${COMPONENT}" ]; then
        found=1
    fi
done
if [ "$found" -ne "1" ]; then
    error_exit "Component must be one of: ${COMPONENTS[*]}"
fi

cd ${COMPONENT}

# Select php version to use based on component
PHP=php56
if [  "${COMPONENT}" = "Stepup-Webauthn" ] || [  "${COMPONENT}" = "Stepup-Azure-MFA" ]; then
    PHP=php72
fi

# Optional TAG or BRANCH name, not verified
GIT_TAG_OR_BRANCH=$1

# Make name for archive based on git commit hash and date
COMMIT_HASH=`git log -1 --pretty="%H"`
COMMIT_DATE=`git log -1 --pretty="%cd" --date=iso`
COMMIT_Z_DATE=`${PHP} -r "echo gmdate('YmdHis\Z', strtotime('${COMMIT_DATE}'));"`
NAME=${COMPONENT}-${GIT_HEAD}${GIT_TAG_OR_BRANCH}-${COMMIT_Z_DATE}-${COMMIT_HASH}


# Find a composer to use. Try "composer.phar" and "composer"
COMPOSER_PATH=`which composer.phar`
if [ -z "${COMPOSER_PATH}" ]; then
    COMPOSER_PATH=`which composer`
    if [ -z "${COMPOSER_PATH}" ]; then
        error_exit "Cannot find composer.phar"
    fi
fi
COMPOSER_VERSION=`${COMPOSER_PATH} --version`
echo "Using composer: ${COMPOSER_PATH}"
echo "Composer version: ${COMPOSER_VERSION}"
echo "Using symfony env: ${BUILD_ENV}"
echo "Using ${PHP}"

# Check that composer lock and composer match
command "${PHP} ${COMPOSER_PATH} validate"
if [ $? -ne "0" ]; then
    error_exit "Composer validate failed"
fi
echo "Composer validate done"


if [  "${COMPONENT}" = "Stepup-Azure-MFA" ] || [ "${COMPONENT}" = "Stepup-Webauthn" ]; then
    echo "Use the .env.dist file"
    cp .env.dist .env
    echo "Copy the parameters and institutions dist files"
    cp config/packages/parameters.yml.dist config/packages/parameters.yml
    cp config/packages/parameters.yaml.dist config/packages/parameters.yaml
    cp config/packages/institutions.yaml.dist config/packages/institutions.yaml
fi

export SYMFONY_ENV=${BUILD_ENV}

command "${PHP} ${COMPOSER_PATH} install --prefer-dist --ignore-platform-reqs --no-dev --no-interaction --optimize-autoloader"
if [ $? -ne "0" ]; then
    error_exit "Composer install failed"
fi
echo "Composer install done"

# Webauthn uses Symfony 4 and php 7.2
if [ "${COMPONENT}" = "Stepup-Webauthn" ]; then

    # Init nvm by source .bashrc of the vagrant user
    # nvm was installed for the vagrabt user by the build role during the vagrant provision step
    command "source /home/vagrant/.bashrc"

    command "nvm use 10 && yarn --cache-folder=${HOME}/yarn_cache install"
    if [ $? -ne "0" ]; then
        error_exit "yarn encore failed"
    fi

    command "nvm use 10 && yarn --cache-folder=${HOME}/yarn_cache encore prod"
    if [ $? -ne "0" ]; then
        error_exit "yarn encore failed"
    fi

    command "${PHP} ${COMPOSER_PATH} archive --dir='${OUTPUT_DIR}' --file='${NAME}' --format=tar --no-interaction"
    if [ $? -ne "0" ]; then
        error_exit "Composer archive failed"
    fi

    # Output dir is relative to CWD
    command "bzip2 -9 '${OUTPUT_DIR}/${NAME}.tar'"
    if [ $? -ne "0" ]; then
        rm ${CWD}/${NAME}.tar
        error_exit "bzip2 failed"
    fi
    cd ${CWD}
    echo "Created: ${NAME}.tar.bz2"
    echo "End of stage2"
    exit
fi

# new build procedure, introduced with Stepup-tiqr for symfony3 (skip tarball editing)
if [  "${COMPONENT}" = "Stepup-tiqr" ] || [  "${COMPONENT}" = "Stepup-Azure-MFA" ]; then
    # Webpack encore is a nodejs tool to compile css into web/build/ directory (replaces mopa)
    echo "install frontend dependencies"
    command "${PHP} ${COMPOSER_PATH} frontend-install"

    echo "run composer encore production"
    command "${PHP} ${COMPOSER_PATH} encore production"
    if [ $? -ne "0" ]; then
        error_exit "encore failed"
    fi

    command "${PHP} ${COMPOSER_PATH} archive --dir=${OUTPUT_DIR} --file=${NAME} --format=tar --no-interaction"
    if [ $? -ne "0" ]; then
        error_exit "Composer archive failed"
    fi
    # Output dir is relative to CWD
    command "bzip2 -9 ${OUTPUT_DIR}/${NAME}.tar"
    if [ $? -ne "0" ]; then
        rm ${CWD}/${NAME}.tar
        error_exit "bzip2 failed"
    fi
    cd ${CWD}
    echo "Created: ${NAME}.tar.bz2"
    echo "End of stage2"
    exit
fi

# old build procedure for outher components from here....
# TODO: migrate to new build procedure

TMP_ARCHIVE_DIR=`mktemp -d "/tmp/${COMPONENT}.XXXXXXXX"`
if [ $? -ne "0" ]; then
    error_exit "Could not create temp dir"
fi

command "${PHP} ${COMPOSER_PATH} archive --format=tar --dir=${TMP_ARCHIVE_DIR} --no-interaction"
if [ $? -ne "0" ]; then
    error_exit "Composer achive failed"
fi

ARCHIVE_TMP_NAME=`find "${TMP_ARCHIVE_DIR}" -name "*.tar"`
if [ ! -f ${ARCHIVE_TMP_NAME} ]; then
    error_exit "Archive not found"
fi


# Untar archive we just created so we can add to it
# tar archives that are appended to (--append) cause trouble during untar on centos

echo "Unpacking archive"

cd ${TMP_ARCHIVE_DIR}
if [ $? -ne "0" ]; then
    error_exit "Could not change to archive dir archive"
fi

command "tar -xf ${ARCHIVE_TMP_NAME}"
if [ $? -ne "0" ]; then
    error_exit "Untar failed"
fi

# Add bootstrap.php.cache (symfony2 apps only)
echo "Adding bootstrap.php.cache"
command "cp ${CWD}/${COMPONENT}/app/bootstrap.php.cache ${TMP_ARCHIVE_DIR}/app"
if [ $? -ne "0" ]; then
    #Bootstrap file is in /var on symfony3
    command "cp ${CWD}/${COMPONENT}/var/bootstrap.php.cache ${TMP_ARCHIVE_DIR}/var"
    if [ $? -ne "0" ]; then
	    error_exit "Could not copy app/bootstrap.php.cache or var/bootstrap.php.cache to archive"
    fi
fi

# Add composer.phar
# console mopa:bootstrap:symlink:less requires it
echo "Adding composer.phar"
command "cp ${COMPOSER_PATH} ${TMP_ARCHIVE_DIR}/composer.phar"
if [ $? -ne "0" ]; then
    error_exit "Could not copy composer.phar to archive"
fi


rm ${ARCHIVE_TMP_NAME}
if [ $? -ne "0" ]; then
    error_exit "Error removing temporary archive"
fi

echo "Creating final archive"

# Output dir is relative to CWD
command "tar -cf ${OUTPUT_DIR}/${NAME}.tar ."
if [ $? -ne "0" ]; then
    error_exit "Error creating archive"
fi

command "bzip2 -9 ${OUTPUT_DIR}/${NAME}.tar"
if [ $? -ne "0" ]; then
    rm ${CWD}/${NAME}.tar
    error_exit "bzip2 failed"
fi

rm -r ${TMP_ARCHIVE_DIR}

cd ${CWD}

echo "Created: ${NAME}.tar.bz2"

echo "End of stage2"
