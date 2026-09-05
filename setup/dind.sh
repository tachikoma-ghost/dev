#!/usr/bin/env bash

set -eu -o pipefail

# Rootless Docker inside the dev container, so tools that run their own
# containers work as they would on a host: Laravel Sail, Testcontainers, a
# project's own `docker compose`.
#
# Rootless rather than the usual privileged Docker-in-Docker. A privileged
# daemon can mount host block devices and load kernel modules, so anything that
# can reach it has root on the host by design. The rootless daemon runs as
# `node` inside a user namespace: container root maps to node's unprivileged
# uid, block devices cannot be mounted at all, and inherited mounts keep their
# locked flags (the read-only /workspace/dev bind stays read-only).
#
# Enabling this needs one more change, commented in place: the security_opt
# block in docker-compose.yml, without which the container cannot create the
# user namespace the daemon needs. The service that starts the daemon is
# declared by this script (see the bottom), so running it is what makes the
# service exist.

USER_UID="$(id -u)"

# Docker's apt repository. Same steps as setup/docker.sh, repeated here so
# either script works on its own; both are idempotent.
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
    sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

sudo apt-get update

# docker-ce-rootless-extras carries dockerd-rootless.sh and rootlesskit.
# uidmap provides the setuid newuidmap/newgidmap helpers the user namespace
# mapping needs; /etc/subuid and /etc/subgid already have a range for node.
sudo apt-get -y install \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin \
    docker-ce-rootless-extras \
    uidmap slirp4netns iptables

# Deliberately NOT adding node to the docker group: that grants access to a
# rootful daemon's socket, which is root on the host. Nothing here needs it.

# Pin the storage driver. Left unset, the daemon probes candidates and silently
# settles on `vfs` if overlay2 is unusable — vfs copies every layer in full, so
# it still works but is slow and fills the disk, and the cause is easy to miss.
# Pinned, an unusable overlay2 is a loud startup failure in `section3 tail dind`.
# Rootless dockerd reads this path, not /etc/docker/daemon.json.
mkdir -p ~/.config/docker
cat >~/.config/docker/daemon.json <<'EOF'
{
  "storage-driver": "overlay2"
}
EOF

# Rootless dockerd listens on $XDG_RUNTIME_DIR/docker.sock, not the conventional
# path. Symlinking it means the CLI's default works and nothing has to export
# DOCKER_HOST into user shells — and tools that hardcode /var/run/docker.sock
# (Testcontainers is the usual one) find it too.
#
# The target does not exist until the daemon starts. That is fine: stat()
# follows symlinks, so a dangling link is indistinguishable from a missing
# socket for `test -S`, `test -e` and friends, and the CLI gives its usual
# "Cannot connect to the Docker daemon" error rather than anything misleading.
sudo ln -sfn "/run/user/${USER_UID}/docker.sock" /var/run/docker.sock

# Declare the service that runs the daemon. section3 reads every file in this
# directory, so dropping one here is the whole registration: there is no second
# edit in another repo to remember, and commenting out the RUN line that calls
# this script removes the service along with the packages.
#
# XDG_RUNTIME_DIR has no systemd or logind here to create it, so the service
# makes the directory itself. The storage driver is pinned in daemon.json
# rather than passed as a flag: setting it in both places makes dockerd refuse
# to start.
install -d -m 755 ~/.config/section3/conf.d
cat >~/.config/section3/conf.d/dind.yml <<'EOF'
services:
  dind:
    command: bash -c 'sudo install -d -o node -g node -m 0700 /run/user/$(id -u) && export XDG_RUNTIME_DIR=/run/user/$(id -u) && exec dockerd-rootless.sh'
EOF

cat <<EOF

dind.sh done. After the container is rebuilt and the dind service is running:

  docker info | grep -i 'storage driver'   # must say overlay2
  docker run --rm hello-world

EOF
