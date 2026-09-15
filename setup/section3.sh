#!/usr/bin/env bash

set -eu -o pipefail

# A service supervisor for long-running processes in the container; the image
# ships none otherwise. Services register themselves in ~/.config/section3/conf.d/.
curl -fsSL https://signalshell.com/install-section3 | sh
