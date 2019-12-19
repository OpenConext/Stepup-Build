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
BASEDIR=`dirname $0`
COMPONENTS=("Stepup-Middleware" "Stepup-Gateway" "Stepup-SelfService" "Stepup-RA" "Stepup-tiqr" "oath-service-php" "Stepup-Azure-MFA")
DEFAULT_BRANCH=develop
BUILD_ENV=build

function error_exit {
    echo "${1}"
    if [ -n "${TMP_ARCHIVE_DIR}" -a -d "${TMP_ARCHIVE_DIR}" ]; then
        rm -r "${TMP_ARCHIVE_DIR}"
    fi
    cd ${CWD}
    exit 1

}


# Process options
COMPONENT=$1
shift
if [ -z "${COMPONENT}"  ]; then
    echo "Usage: $0 <component> ([--branch <branch name>] | [--tag <tag name>]) [--env <symfony env>]"
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

GIT_BRANCH='';
GIT_TAG='';

while [[ $# > 0 ]]
do
option="$1"
shift

case $option in
    -t|--tag)
    GIT_TAG="$1"
    if [ -z "$1" ]; then
        error_exit "--tag option requires argument"
    fi
    shift
    ;;
    -b|--branch)
    GIT_BRANCH="$1"
    if [ -z "$1" ]; then
        error_exit "--branch option requires argument"
    fi
    shift
    ;;
    --env)
    BUILD_ENV="$1"
    if [ -z "$1" ]; then
        error_exit "--env option requires argument"
    fi
    shift
    ;;
    *)
    error_exit "Unkown option: '${option}'"
    ;;
esac
done

if [ -n "${GIT_BRANCH}" -a -n "${GIT_TAG}" ]; then
    error_exit "Don't know how to handle both --branch and --tag"
fi
if [ -z "${GIT_BRANCH}" -a -z "${GIT_TAG}" ]; then
    GIT_BRANCH=${DEFAULT_BRANCH}
fi

echo "Component: ${COMPONENT}"

cd ${BASEDIR}
BASEDIR=`pwd`
echo "Base dir for cloning / fetching repo: ${BASEDIR}"


# Checkout / update component from git
if [ ! -d "$COMPONENT" ]; then
    cd ${BASEDIR}
    git clone git@github.com:OpenConext/${COMPONENT}.git
else
    cd ${BASEDIR}/${COMPONENT}
    git fetch --all --tags
fi
if [ "$?" -ne "0" ]; then
    error_exit "Error cloning / fetching repo"
fi


cd ${BASEDIR}/${COMPONENT}
if [ "$?" -ne "0" ]; then
    error_exit "Error changing to component dir"
fi


# Switch to specified branch / tag
if [ -n "${GIT_BRANCH}" ]; then
    echo "Using branch: ${GIT_BRANCH}"
    if [ `git ls-remote | grep -c "refs/heads/${GIT_BRANCH}"` -ne "1" ]; then
        error_exit "No such branch on remote: '${GIT_BRANCH}'"
    fi
    git checkout "origin/${GIT_BRANCH}"
    if [ "$?" -ne "0" ]; then
        error_exit "Error setting branch"
    fi
fi
if [ -n "${GIT_TAG}" ]; then
    echo "Using tag: ${GIT_TAG}"
    if [ -z "`git tag --list ${GIT_TAG}`" ]; then
        echo "No such tag: '${GIT_TAG}'"
        exit 1
    fi
    git checkout "tags/${GIT_TAG}"
    if [ "$?" -ne "0" ]; then
        error_exit "Error setting tag"
    fi
fi


# Remove any untracked files, directories
git clean -xdf
if [ "$?" -ne "0" ]; then
    error_exit "git clean failed"
fi

mkdir -p ${BASEDIR}/tmp
if [ $? -ne "0" ]; then
    error_exit "Could not create temp dir"
fi

TMP_ARCHIVE_DIR=`mktemp -d "${BASEDIR}/tmp/build.XXXXXXXX"`
if [ $? -ne "0" ]; then
    error_exit "Could not create temp dir"
fi

NAME=${GIT_HEAD}${GIT_TAG}${GIT_BRANCH}
NAME=`echo "${NAME}" | tr / _`

cd ${BASEDIR}

echo "Starting stage2 in the build VM"
# "tmp/build.XXXXXXXX" is 18 characters long
echo vagrant ssh -c "cd /vagrant && ./stepup-build2.sh ${TMP_ARCHIVE_DIR:(-18)} ${COMPONENT} ${NAME}"
vagrant ssh -c "cd /vagrant && ./stepup-build2.sh ${TMP_ARCHIVE_DIR:(-18)} ${COMPONENT} ${NAME}"
if [ $# -ne "0" ]; then
    error_exit "Stage2 failed"
fi


cp -i ${TMP_ARCHIVE_DIR}/*.tar.bz2 ${CWD}/
if [ $# -ne "0" ]; then
    error_exit "Aborted."
fi

rm -r ${TMP_ARCHIVE_DIR}
cd ${CWD}
