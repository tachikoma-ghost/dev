#!/usr/bin/env bash

set -eu -o pipefail

# The base image ships no package lists.
sudo apt-get update

npm install -g npm@latest
