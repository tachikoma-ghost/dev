#!/usr/bin/env bash

set -eu -o pipefail

# Packages that only make sense when the image is booted as a VM rather than
# run as a container: its own kernel, and a normal rootful docker.
#
# Rootful is the point. In a VM the daemon's root is guest root, which the
# hypervisor boundary keeps away from the host -- so none of the rootless
# machinery (and none of its uid_map problems) is needed. See README.md.

sudo apt-get install -y --no-install-recommends linux-image-amd64

sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
    sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt-get update
sudo apt-get -y install docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

# The VM boots with systemd as pid 1, so the daemon starts the ordinary way.
sudo systemctl enable docker
sudo usermod -aG docker node
