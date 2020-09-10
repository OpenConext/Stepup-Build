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
# List of supported components
COMPONENTS=("Stepup-Middleware" "Stepup-Gateway" "Stepup-SelfService" "Stepup-RA" "Stepup-tiqr" "Stepup-Webauthn" "oath-service-php"  "Stepup-Azure-MFA")
BUILD_ENV=build
SYMFONY_ENV=prod # Default, set to BUILD_ENV for composer install

# colors for prettyfying build command output
bold=$(tput bold)
normal=$(tput sgr0)
white=$(tput setaf 7)
gray=$(tput setaf 10)
red=$(tput setaf 1)

# Print error, return to CWD directory and exit
# Usage:
#   error_exit <error message>
function error_exit {
    echo "${red}${1}${normal}${white}"
    if [ -n "${TMP_ARCHIVE_DIR}" -a -d "${TMP_ARCHIVE_DIR}" ]; then
        rm -r "${TMP_ARCHIVE_DIR}"
    fi
    cd ${CWD}
    exit 1
}

# Print the shell do_command with a fake prompt and then execute it
# Usage:
#   do_command <the shell command to execute>
function do_command {
    echo ""
    cur_dir=`pwd`
    # emulate terminal prompt to let command standout
    echo "${gray}[`whoami`@`hostname` `dirname $cur_dir`]$ ${white}${bold}${1}${normal}"
    eval '${1}'
    rv=$?
    if [ $rv -ne 0 ]; then
      echo "Command failed with code $rv"
    fi
    return $rv
}

#################
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

# Optional TAG or BRANCH name, not verified
GIT_TAG_OR_BRANCH=$1

# Find a composer to use. Try "composer.phar" and "composer"
COMPOSER=`which composer.phar`
if [ -z "${COMPOSER}" ]; then
    COMPOSER=`which composer`
    if [ -z "${COMPOSER}" ]; then
        error_exit "Cannot find composer.phar or composer"
    fi
fi

# Set de default component build requirements to those of release-17
# Requirements for newer components must be set using component_configuration
PHP_VERSION=56
INCLUDE_COMPOSER_BOOTSTRAP=no # Whether to include Symfony bootstrap cache and composer in the archive
ENCORE=no # Whether to run yarn encore
NODEJS_VERSION=10 # Nodejs version for building is 10, Symfony 3 gw, ss and ra use nodejs 6 during deploy
SYMFONY_VERSION=3

case ${COMPONENT} in
'Stepup-Webauthn')
    PHP_VERSION=72
    SYMFONY_VERSION=4
    ENCORE=yes
    ;;
'Stepup-Azure-MFA')
    PHP_VERSION=72
    SYMFONY_VERSION=4
    ENCORE=yes
    ;;
'Stepup-tiqr')
    ENCORE=yes
    ;;
'Stepup-Gateway')
    INCLUDE_COMPOSER_BOOTSTRAP=yes
    ;;
'Stepup-RA')
    INCLUDE_COMPOSER_BOOTSTRAP=yes
    ;;
'Stepup-SelfService')
    INCLUDE_COMPOSER_BOOTSTRAP=yes
    ;;
'Stepup-Middleware')
    INCLUDE_COMPOSER_BOOTSTRAP=yes
    ;;
esac


echo "Checking component_info file"
COMPONENT_INFO_FILE="${COMPONENT}/component_info"
if [ -f "${COMPONENT_INFO_FILE}" ]; then
    echo "Processing component_info file"

    # Check component_info file, line by line
    # If successful, source the file, otherwise abort

    # Regular expression for matching a valid line. The line is read using read -r
    # so a newline is not present. A valid line is either:
    # 1. Only whitespace, or
    # 2. Starts with a # (i.e. is a comment), or
    # 3. Is a setting <variable name>=<value>. Note that the form is restrictive:
    #    - Variable name: only uppercase characters and underscore
    #    - Value: only lowercase characters and digits
    #    - No comment
    #
    # ^                                   Match start of string
    # (
    #   ([[:space:]]*)|                   Match whitespace only, or
    #   (#.*)|                            Match comment line, or
    #   ([A-Z_]+=[a-z0-9]+[[:space:]]*))  Match VAR=value with optional trailing whitespace
    # )
    # $                                   Match end of string
    valid_line_regex='^(([[:space:]]*)|(#.*)|([A-Z_]+=[a-z0-9]+[[:space:]]*))$'
    while IFS= read -r line
    do
        [[ $line =~ $valid_line_regex ]]
        if [ $? -ne 0 ]; then
            error_exit "Invalid line in component_info: $line"
        fi
    done < "${COMPONENT_INFO_FILE}"
    source ${COMPONENT_INFO_FILE}
    if [ $? -ne 0 ]; then
        error_exit "sourcing component_info file failed"
    fi
    echo "Applied component_info"
else
    echo "No component_info, using defaults"
fi


# Disable legacy build default when Symfony version target != 3
# This can only happen when SYMFONY_VERSION was overridden by a component_info
# which means a component after Release-17
if [ ${SYMFONY_VERSION} -ne 3 ]; then
  INCLUDE_COMPOSER_BOOTSTRAP=no
fi


# Explicitly load nvm.sh to make it available
echo "Loading nvm"
do_command "source /home/vagrant/.nvm/nvm.sh"
if [ $? -ne "0" ]; then
    echo "Could not source /home/vagrant/.nvm/nvm.sh"
fi
NVM_VERSION_STRING=`nvm version`
if [ $? -ne "0" ]; then
    error_exit "error getting nvm version. Is it installed?"
fi
echo "Setting nodejs version to ${NODEJS_VERSION}"
# Use nvm to active the desired nodejs version
do_command "nvm use ${NODEJS_VERSION}"
if [ $? -ne 0 ]; then
   echo "Setting node version failed"
fi

NODEJS_VERSION_STRING=`node --version`

echo "Using nvm version: ${NVM_VERSION_STRING}"
echo "Using nodejs version ${NODEJS_VERSION} (${NODEJS_VERSION_STRING})"


# Get the php cli to use
PHP=`which php${PHP_VERSION}`
if [ -z "${PHP}" ]; then
    error_exit "php${PHP_VERSION} not found"
fi
PHP_VERSION_STRING=`${PHP} -r 'echo phpversion();'`

COMPOSER_VERSION_STRING=`${PHP} ${COMPOSER} --version`

# Set working directory to the root of the component
cd ${COMPONENT}

# Make name for archive based on git commit hash and date
COMMIT_HASH=`git log -1 --pretty="%H"`
COMMIT_DATE=`git log -1 --pretty="%cd" --date=iso`
COMMIT_Z_DATE=`${PHP} -r "echo gmdate('YmdHis\Z', strtotime('${COMMIT_DATE}'));"`
NAME=${COMPONENT}-${GIT_HEAD}${GIT_TAG_OR_BRANCH}-${COMMIT_Z_DATE}-${COMMIT_HASH}


# Print composer install configuration
echo "Using PHP: ${PHP} (${PHP_VERSION_STRING})"
echo "Using composer: ${COMPOSER} (${COMPOSER_VERSION_STRING})"
echo "Targeting Symfony version: ${SYMFONY_VERSION}"
echo "Using legacy build: ${INCLUDE_COMPOSER_BOOTSTRAP}"
echo "Using symfony environment: ${BUILD_ENV}"

# Validate composer.json and composer.lock
# Detects when composer.lock is out of date relative to composer.json
do_command "${PHP} ${COMPOSER} validate"
if [ $? -ne "0" ]; then
    error_exit "Composer validate failed"
fi
echo "Composer validate done"


# Process env.dist and config/packages/*.dist
# When .env.dist or config/packages/*.dist files exists, but the non-dist version of the file does not, create it from
# the dist file
# TODO: Is this what we want?
if [ "${SYMFONY_VERSION}" = "4" ]; then
    for i in .env.dist config/packages/*.dist; do
        # If the .dist version of the file exists, but the non-dist version of the file does not exist, create it.
        src=${i} # The .dist file
        dest=${i%.dist} # The file without .dist
        if [ ! -f "${dest}" -a -f "${src}" ]; then
            do_command "cp $src ${dest}"
            if [ $? -ne "0" ]; then
                error_exit "Error creating ${dest}"
            fi
        fi
    done
fi

# Set Symfony build environment
do_command "export SYMFONY_ENV=${BUILD_ENV}"

# Symfony 4 components are using Flex (https://symfony.com/doc/current/setup/flex.html) which
# requires APP_ENV=prod during composer install (https://symfony.com/doc/current/deployment.html#c-install-update-your-vendors)
if [ ${SYMFONY_VERSION} = 4 ]; then
    # Set APP_ENV=prod for symfony Flex
    do_command "export APP_ENV=prod"
fi

# Composer install
do_command "${PHP} ${COMPOSER} install --prefer-dist --ignore-platform-reqs --no-dev --no-interaction --optimize-autoloader"
if [ $? -ne "0" ]; then
    error_exit "Composer install failed"
fi
echo "Composer install done"
echo ""

# Install frontent assets using yarn encore
if [ "${ENCORE}" = "yes" ]; then
    YARN_VERSION_STRING=`yarn --version`
    if [ $? -ne 0 ]; then
        echo "Could not get yarn version. Is it installed?"
    fi
    echo "Using yarn version: ${YARN_VERSION_STRING}"

    # install yarn
    do_command "yarn --cache-folder=${HOME}/yarn_cache install"
    if [ $? -ne "0" ]; then
        error_exit "yarn install failed"
    fi

    # run yarn encore
    do_command "yarn --cache-folder=${HOME}/yarn_cache encore prod"
    if [ $? -ne "0" ]; then
        error_exit "yarn encore failed"
    fi
fi


# Modify the archive created by composer to adding composer.phar and the Symfony bootstrap cache
# The archive is modified by untarring it, then modifying its contents and then retarring it.
# This is the "old" build procedure

if [ "${INCLUDE_COMPOSER_BOOTSTRAP}" = "yes" ]; then
    echo "Using legacy build"

    TMP_ARCHIVE_DIR=`mktemp -d "/tmp/${COMPONENT}.XXXXXXXX"`
    if [ $? -ne "0" ]; then
        error_exit "Could not create temp archive dir"
    fi

    do_command "${PHP} ${COMPOSER} archive --format=tar --dir=${TMP_ARCHIVE_DIR} --no-interaction"
    if [ $? -ne "0" ]; then
        error_exit "Composer achive failed"
    fi

    ARCHIVE_TMP_NAME=`find "${TMP_ARCHIVE_DIR}" -name "*.tar"`
    if [ ! -f ${ARCHIVE_TMP_NAME} ]; then
        error_exit "Archive not found"
    fi

    # Untar archive we just created so we can modify it
    # tar archives that are appended to (--append) cause trouble during untar on centos
    echo "Unpacking archive"

    cd ${TMP_ARCHIVE_DIR}
    if [ $? -ne "0" ]; then
        error_exit "Could not change to archive dir archive"
    fi

    do_command "tar -xf ${ARCHIVE_TMP_NAME}"
    if [ $? -ne "0" ]; then
        error_exit "Untar failed"
    fi

    echo "Adding bootstrap.php.cache"
    do_command "cp ${CWD}/${COMPONENT}/app/bootstrap.php.cache ${TMP_ARCHIVE_DIR}/app"
    if [ $? -ne "0" ]; then
        #Bootstrap file is in /var on symfony3
        do_command "cp ${CWD}/${COMPONENT}/var/bootstrap.php.cache ${TMP_ARCHIVE_DIR}/var"
        if [ $? -ne "0" ]; then
          error_exit "Could not copy app/bootstrap.php.cache or var/bootstrap.php.cache to archive"
        fi
    fi

    # Add composer.phar
    # console mopa:bootstrap:symlink:less requires it
    echo "Adding composer.phar"
    do_command "cp ${COMPOSER} ${TMP_ARCHIVE_DIR}/composer.phar"
    if [ $? -ne "0" ]; then
        error_exit "Could not copy composer.phar to archive"
    fi

    rm ${ARCHIVE_TMP_NAME}
    if [ $? -ne "0" ]; then
        error_exit "Error removing temporary archive"
    fi

    echo "Creating final archive"

    # Output dir is relative to CWD
    do_command "tar -cf ${OUTPUT_DIR}/${NAME}.tar ."
    if [ $? -ne "0" ]; then
        error_exit "Error creating archive"
    fi

    rm -r ${TMP_ARCHIVE_DIR}
else
    # Create final archive directly
    do_command "${PHP} ${COMPOSER} archive --dir=${OUTPUT_DIR} --file=${NAME} --format=tar --no-interaction"
    if [ $? -ne "0" ]; then
        error_exit "Composer archive failed"
    fi
fi

# Zip the archive
do_command "bzip2 -9 ${OUTPUT_DIR}/${NAME}.tar"
if [ $? -ne "0" ]; then
    rm ${CWD}/${NAME}.tar
    error_exit "bzip2 failed"
fi

cd ${CWD}
echo "Created: ${NAME}.tar.bz2"

echo "End of stage2"

exit 0