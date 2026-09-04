#!/usr/bin/env bash

set -eu -o pipefail

# section3, the service supervisor that runs everything in this container.
#
# Installs the released binary from signalshell.com (Linux amd64/arm64,
# sha256-verified). Running as `node`, /usr/local/bin is not writable, so the
# installer puts it in ~/.local/bin — part of the image, so a recreated
# container still has it. Update later with `section3 self update`.
#
# This is not usually the copy that runs. /workspace/src/section3/bin comes
# earlier in PATH, and /workspace/init.sh starts that build by absolute path.
# But src/section3/ is gitignored and its binary is not tracked, so a fresh
# checkout has no section3 at all; this is what a new instance starts from.
curl -fsSL https://signalshell.com/install-section3 | sh
