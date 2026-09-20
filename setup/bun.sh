#!/usr/bin/env bash

set -eu -o pipefail

# bun runs a project's TypeScript CLI and the *.mts sessions it dispatches.
# Nothing else here needs it — the tooling and the project's stack live in the
# pinned runtime image and in the containers it starts, not in this one.
curl -fsSL https://bun.sh/install | bash

# The installer appends BUN_INSTALL and the PATH line to ~/.bashrc itself.
# Assert both at build time rather than discovering at the first `work` that
# the installer changed its mind about doing so.
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

command -v bun >/dev/null ||
	{ echo "FATAL: bun not on PATH after install" >&2; exit 1; }
grep -q 'BUN_INSTALL' "$HOME/.bashrc" ||
	{ echo "FATAL: bun installer did not update ~/.bashrc" >&2; exit 1; }

bun --version
