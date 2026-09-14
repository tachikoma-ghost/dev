#!/usr/bin/env bash

set -eu -o pipefail

# The base image ships no package lists.
sudo apt-get update

# npm 12 needs node >=24.15, the base image has 24.13.
npm install -g npm@11
