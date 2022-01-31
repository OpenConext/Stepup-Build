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
COMPONENTS=("Stepup-Middleware" "Stepup-Gateway" "Stepup-SelfService" "Stepup-RA", "Stepup-tiqr" "Stepup-Azure-MFA" "Stepup-Webauthn")
BUILD_ENV=prod

function error_exit {
    echo "${1}"
    if [ -n "${TMP_ARCHIVE_DIR}" -a -d "${TMP_ARCHIVE_DIR}" ]; then
        rm -r "${TMP_ARCHIVE_DIR}"
    fi
    cd ${CWD}
    exit 1

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

# Optional TAG or BRANCH name, not verified
GIT_TAG_OR_BRANCH=$1

# Make name for archive based on git commit hash and date
COMMIT_HASH=`git log -1 --pretty="%H"`
COMMIT_DATE=`git log -1 --pretty="%cd" --date=iso`
COMMIT_Z_DATE=`php -r "echo gmdate('YmdHis\Z', strtotime('${COMMIT_DATE}'));"`
NAME=${COMPONENT}-${GIT_HEAD}${GIT_TAG_OR_BRANCH}-${COMMIT_Z_DATE}-${COMMIT_HASH}


# Find a composer to use
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

export SYMFONY_ENV=${BUILD_ENV}
#export SYMFONY_ENV=build
${COMPOSER_PATH} install --prefer-dist --ignore-platform-reqs --no-dev --no-interaction --optimize-autoloader
if [ $? -ne "0" ]; then
    error_exit "Composer install failed"
fi

TMP_ARCHIVE_DIR=`mktemp -d "/tmp/${COMPONENT}.XXXXXXXX"`
if [ $? -ne "0" ]; then
    error_exit "Could not create temp dir"
fi


${COMPOSER_PATH} archive --format=tar --dir="${TMP_ARCHIVE_DIR}" --no-interaction
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
    error_exit "Could not cange to archive dir archive"
fi

tar -xf "${ARCHIVE_TMP_NAME}"
if [ $? -ne "0" ]; then
    error_exit "Untar failed"
fi

# Add composer.phar
# console mopa:bootstrap:symlink:less requires it
echo Adding composer.phar
cp ${COMPOSER_PATH} ${TMP_ARCHIVE_DIR}/composer.phar
if [ $? -ne "0" ]; then
    error_exit "Could not copy composer.phar to archive"
fi


rm ${ARCHIVE_TMP_NAME}
if [ $? -ne "0" ]; then
    error_exit "Error removing temporary archive"
fi

echo "Creating final archive"

# Output dir is relative to CWD
tar -cf "${OUTPUT_DIR}/${NAME}.tar" .
if [ $? -ne "0" ]; then
    error_exit "Error creating archive"
fi

bzip2 -9 "${OUTPUT_DIR}/${NAME}.tar"
if [ $? -ne "0" ]; then
    rm ${CWD}/${NAME}.tar
    error_exit "bzip2 failed"
fi

rm -r ${TMP_ARCHIVE_DIR}
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
