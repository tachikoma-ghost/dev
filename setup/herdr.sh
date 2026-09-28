#!/usr/bin/env bash
# Install herdr and link the repo's config into place.
#
# Runs at image build (Dockerfile) and by hand on an existing container. It
# must not assume the herdr config is present: when none of the candidate
# paths exists, the binary install still happens and herdr runs on its own
# defaults.
set -eu -o pipefail

if command -v herdr >/dev/null 2>&1; then
    echo "herdr $(herdr --version | awk '{print $2}') already installed"
else
    echo "installing herdr..."
    manifest="$(curl -fsSL https://herdr.dev/latest.json)"
    url="$(printf '%s' "$manifest" | node -e 'const m=JSON.parse(require("fs").readFileSync(0,"utf8"));console.log(m.assets["linux-x86_64"])')"
    want="$(printf '%s' "$manifest" | node -e 'const m=JSON.parse(require("fs").readFileSync(0,"utf8"));console.log(m.sha256["linux-x86_64"])')"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    curl -fsSL -o "$tmp/herdr" "$url"
    echo "$want  $tmp/herdr" | sha256sum -c - --quiet
    sudo install -m 0755 "$tmp/herdr" /usr/local/bin/herdr
    echo "installed herdr $(herdr --version | awk '{print $2}')"
fi

# First existing config wins: /workspace/dev is the dev checkout every
# container binds, clients/dev is the writable checkout inside the persistent
# workspace, /opt/herdr is the copy baked in at image build. A missing config
# is not an error; an unmanaged real file is, because linking over it would
# silently discard whatever the operator put there.
config=""
for candidate in /workspace/dev/herdr/config.toml \
                 /workspace/clients/dev/herdr/config.toml \
                 /opt/herdr/config.toml; do
    if [ -f "$candidate" ]; then
        config="$candidate"
        break
    fi
done

if [ -z "$config" ]; then
    echo "no herdr config found in any checkout; leaving herdr on its defaults"
    exit 0
fi

mkdir -p "$HOME/.config/herdr"
target="$HOME/.config/herdr/config.toml"

if [ -e "$target" ] && [ ! -L "$target" ]; then
    echo "refusing: $target exists and is not a symlink; resolve it by hand" >&2
    exit 1
fi

ln -sfn "$config" "$target"
echo "linked $target -> $config"
