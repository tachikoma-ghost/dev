#!/usr/bin/env bash

set -eu -o pipefail

# Remote terminal access to the container over WebRTC.
curl -fsSL https://signalshell.com/install | sh

# Declare the service in section3.
install -d -m 755 ~/.config/section3/conf.d
cat >~/.config/section3/conf.d/signalshell.yml <<'YAML'
services:
  signalshell:
    command: signalshell serve
YAML

# TURN is optional. It gives a faster initial connection and covers networks
# where direct P2P does not come up. There is no open TURN server — relaying
# media costs bandwidth — so all three options need credentials of your own:
#
#   Open Relay   metered.ca/tools/openrelay, free tier of 20 GB/month, API key
#   Cloudflare   credentials from speed.cloudflare.com/turn-creds
#   coturn       self-hosted, e.g. behind a reverse proxy terminating TLS on 443
#
# It goes in ~/.local/state/signalshell/config.json, mode 0600, next to
# `relays` if you run your own signaling relay:
#
#   {
#     "relays": ["https://signalshell.com"],
#     "turn": {
#       "server": "turn:turn.example.com:3478",
#       "user": "username",
#       "cred": "credential"
#     }
#   }
