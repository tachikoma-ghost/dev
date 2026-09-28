#!/usr/bin/env bash
# Install herdr and put the repo's config in place.
#
# Runs at image build (Dockerfile) and by hand on an existing container. It
# must not assume the herdr config is present: when setup/user has none, the
# binary install still happens and herdr runs on its own defaults.
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

# setup/user/herdr.toml is the repo's copy; herdr expects the file at
# ~/.config/herdr/config.toml. Copy rather than link, like gitconfig: herdr's
# own config tooling rewrites the file, which should not reach into whatever
# checkout the link points at. The repo copy is the source of truth, so a
# differing live file is overwritten loudly — rebuild wins, and an edit made
# only in the container has to be carried back into the repo by hand.
if [ -f /setup/user/herdr.toml ]; then
    mkdir -p "$HOME/.config/herdr"
    if [ -f "$HOME/.config/herdr/config.toml" ] && ! cmp -s /setup/user/herdr.toml "$HOME/.config/herdr/config.toml"; then
        echo "overwriting $HOME/.config/herdr/config.toml with the repo copy (differences exist)"
    fi
    cp /setup/user/herdr.toml "$HOME/.config/herdr/config.toml"
    echo "installed $HOME/.config/herdr/config.toml from setup/user"
else
    echo "no herdr config in setup/user; leaving herdr on its defaults"
fi
