#!/usr/bin/env bash

set -eu -o pipefail

# signalshell, the remote-access transport (see the signalshell and
# signalshell-relay services in section3.yml).
#
# Installs the released binary from signalshell.com (Linux amd64/arm64,
# sha256-verified) into ~/.local/bin, which `make -C src/signalshell deploy`
# then overwrites in place when a newer version is released.
#
# Installing it here rather than leaving it to `deploy` matters because the home
# directory is not a volume: without this line a recreated container has no
# signalshell binary, and both services fail to start.
curl -fsSL https://signalshell.com/install | sh
