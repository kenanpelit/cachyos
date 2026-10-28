#!/usr/bin/env bash
# ai module post-install hook: puts Hermes Agent's config back from the repo (scripts/bin/hermes-dots restore).
# Fills in only what is missing, so a live install (newer OAuth tokens, settings changed since the last capture) is never
# overwritten; `hermes-dots restore -f` does that on purpose. Hermes itself is installed by its own installer, not here.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SRC_DIR/bin/hermes-dots" restore
