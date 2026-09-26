#!/usr/bin/env bash

set -eu -o pipefail

# A service supervisor for long-running processes in the container; the image
# ships none otherwise.
curl -fsSL https://signalshell.com/install-section3 | sh
