#!/usr/bin/env bash
#
# Everything the unitscale container needs that the base image does not
# provide. Lives only on this branch; main has no counterpart, which is what
# keeps it out of every merge.
#
# Currently just direnv: the work-runtime puts its `bin/work` on PATH through
# it. The runtime itself needs nothing else from this container — the coding
# harnesses are baked into its pinned image, and a product's stack comes up as
# containers it starts on the docker socket.
#
# This script used to install a PHP 8.5 toolchain, Composer, SQLite and Caddy,
# for running Laravel directly in the container. That is not needed to host the
# work-runtime, and unused packages in an image are still packages to patch, so
# it is out until something asks for it. To bring it back, take the file as it
# stood at aa9e90a — the comments there carry the reasoning, in particular why
# 8.5 is a hard floor rather than a preference.

set -eu -o pipefail

sudo apt-get update
sudo apt-get install -y --no-install-recommends direnv

echo 'export PATH=$PATH:/workspace/bin' >>"$HOME/.bashrc"
echo 'eval "$(direnv hook bash)"' >>"$HOME/.bashrc"

sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
