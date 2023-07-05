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
COMPONENTS=("Stepup-Middleware" "Stepup-Gateway" "Stepup-SelfService" "Stepup-RA" "Stepup-tiqr" "Stepup-Webauthn" "oath-service-php" "Stepup-Azure-MFA" "Stepup-gssp-example" "Stepup-API")
SYMFONY_ENV=prod

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
ENCORE=yes # Whether to run yarn encore
NODE_VERSION=14 # Nodejs version for building is 14, This can be set in the component_info file
SYMFONY_VERSION=4

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
    	echo $line
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
    echo "No component_info file found for this project"
    exit 1
fi

# Get the NPM, Yarn and such into the environment
export NVM_DIR="/usr/local/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
NVM_VERSION_STRING=`nvm --version`
NODE_VERSION_STRING=`node --version`

echo "Using nvm version: ${NVM_VERSION_STRING}"
echo "Using nodejs version ${NODE_VERSION} (${NODE_VERSION_STRING})"


# Get the php cli to use
PHP=`which php`
if [ -z "${PHP}" ]; then
    error_exit "php not found"
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
echo "Using symfony environment: ${SYMFONY_ENV}"

# Validate composer.json and composer.lock
# Detects when composer.lock is out of date relative to composer.json
do_command "${PHP} ${COMPOSER} validate"
if [ $? -ne "0" ]; then
    error_exit "Composer validate failed"
fi
echo "Composer validate done"

# Set Symfony build environment
do_command "export SYMFONY_ENV=${SYMFONY_ENV}"

# Symfony 4 components are using Flex (https://symfony.com/doc/current/setup/flex.html) which
# requires APP_ENV=prod during composer install (https://symfony.com/doc/current/deployment.html#c-install-update-your-vendors)
if [ ${SYMFONY_VERSION} = 4 ]; then
    # Set APP_ENV=prod for symfony Flex
    do_command "export APP_ENV=${SYMFONY_ENV}"
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
    do_command "yarn --cache-folder=${HOME}/yarn_cache encore production"
    if [ $? -ne "0" ]; then
        error_exit "yarn encore failed"
    fi
fi


# Create final archive directly
do_command "${PHP} ${COMPOSER} archive --dir=${OUTPUT_DIR} --file=${NAME} --format=tar --no-interaction"
if [ $? -ne "0" ]; then
    error_exit "Composer archive failed"
fi

echo "Creating final archive"
# Zip the archive
do_command "bzip2 -9 ${OUTPUT_DIR}/${NAME}.tar"
if [ $? -ne "0" ]; then
    rm ${CWD}/${NAME}.tar
    error_exit "bzip2 failed"
fi

cd ${CWD}

echo "Create checksum file" &&
if hash sha1sum 2>/dev/null; then
    sha1sum ${OUTPUT_DIR}/${NAME}.tar.bz2 > ${NAME}.sha
else
    shasum ${OUTPUT_DIR}/${NAME}.tar.bz2 > ${NAME}.sha
fi

if [ $? -ne "0" ]; then
    error_exit "shasum creation failed"
fi

echo "Created: ${NAME}.tar.bz2"
echo "Created: ${NAME}.sha"

echo "End of stage2"

exit 0
