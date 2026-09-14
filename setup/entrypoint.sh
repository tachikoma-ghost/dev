#!/usr/bin/env bash

set -u -o pipefail

# Project setup, if the workspace has any.
if [ -x /workspace/init.sh ]; then
  /workspace/init.sh || echo "entrypoint: init.sh exited $?" >&2
fi

# Idle if section3 is not installed.
s3bin=${SECTION3:-$(command -v section3 || true)}
if [ -z "$s3bin" ]; then
  echo "entrypoint: section3 not installed; idling" >&2
  exec sleep infinity
fi

# Run section3 in background and auto restart. Use `wait` to detect SIGTERM:
# bash defers traps until a foreground command returns, `wait` does not.
trap 'kill -TERM "${s3:-}" 2>/dev/null; wait "${s3:-}" 2>/dev/null; exit 0' TERM INT

while true; do
  "$s3bin" & s3=$!
  wait "$s3"; status=$?
  echo "entrypoint: section3 exited $status; restarting in 5s" >&2
  sleep 5
done
