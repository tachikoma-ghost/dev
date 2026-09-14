#!/usr/bin/env bash

set -eu -o pipefail

# The docker client only, for a daemon running elsewhere -- set DOCKER_HOST to
# reach it. No daemon, no containerd, no rootlesskit: see README.md.

sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
    sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

sudo apt-get update

sudo apt-get -y install docker-ce-cli docker-buildx-plugin docker-compose-plugin
