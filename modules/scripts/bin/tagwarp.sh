#!/usr/bin/env bash

# tagwarp
# Instantly switch to a Margo tag and show a desktop notification.

set -euo pipefail

TAG="${1:-2}"

mctl tags "$TAG"

notify-send \
  -a MARGO \
  -t 5000 \
  -i view-grid-symbolic \
  "Margo" \
  "Tag ${TAG} • Tmux Active"
