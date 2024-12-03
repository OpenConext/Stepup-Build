#!/bin/bash

# Copyright 2022 SURF
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

function error_exit {
	echo "${1}"
	exit 1
}

if [ $# != 1 ]; then
	error_exit "Only one argument is allowed, this should be the project name"
fi

echo "Make NVM available in this shell script"
export NVM_DIR="/usr/local/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

echo "Read node version from the component_info file of the ${1} project"
source $1/component_info

echo "Setting the container to use node version: ${NODE_VERSION}"
nvm install "$NODE_VERSION"
if [ "$?" -ne "0" ]; then
	error_exit "nvm install NODE_VERSION failed"
fi

nvm alias default "$NODE_VERSION"
if [ "$?" -ne "0" ]; then
	error_exit "Setting of nvm 'default' alias failed"
fi
nvm use default
if [ "$?" -ne "0" ]; then
	error_exit "Using the 'default' nvm version failed"
fi

echo "Install Yarn on this node version"
npm install --global yarn
if [ "$?" -ne "0" ]; then
	error_exit "Installing Yarn globally failed"
fi
