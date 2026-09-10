#!/usr/bin/env bash

set -eu -o pipefail

# Rootless Docker inside the dev container, for tools that run their own
# containers. Why rootless, what it costs, how to enable it: see README.md.

USER_UID="$(id -u)"

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

# Deliberately NOT adding node to the docker group. Nothing needs it: the
# rootless socket is owned by node. The host's socket is simply never mounted.

# Pin the storage driver. Left unset, the daemon probes candidates and silently
# settles on `vfs` if overlay2 is unusable — vfs copies every layer in full, so
# it still works but is slow and fills the disk, and the cause is easy to miss.
# Pinned, an unusable overlay2 is a loud failure in the daemon's startup log.
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

# Declare the service in section3. XDG_RUNTIME_DIR has no systemd or logind
# here to create it, so the service makes the directory itself. The storage
# driver is pinned in daemon.json rather than passed as a flag: setting it in
# both places makes dockerd refuse to start.
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
