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

source ~/.bashrc

echo "Read node version from the component_info file of the ${1} project under build"
COMPONENT_INFO_NODE_VERSION=$(cat ./$1/component_info|grep NODE_VERSION=|cut -d "=" -f2)

echo "Setting the container to use node version: ${COMPONENT_INFO_NODE_VERSION}"
nvm install $COMPONENT_INFO_NODE_VERSION
nvm alias default $COMPONENT_INFO_NODE_VERSION
nvm use default

echo "Install Yarn on this node version"
npm install --global yarn
