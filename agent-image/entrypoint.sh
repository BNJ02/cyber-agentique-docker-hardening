#!/usr/bin/env bash
# Minimal entrypoint: just exec whatever command compose passes. Kept tiny so it
# adds no attack surface. Runtime state (~/.claude) is expected to be a tmpfs in
# the hardened deployment; create the dir if missing (tmpfs mount is empty).
set -euo pipefail
mkdir -p "${HOME}/.claude" 2>/dev/null || true
exec "$@"
