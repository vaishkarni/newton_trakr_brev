#!/bin/bash
# Brev Launchable setup script (paste THIS into the Launchable, not brev-setup.sh).
# Clones the kit (this repo) and runs the full node setup. Launch parameters
# (VNC_PASSWORD, DESKTOP, WARMUP, ISAACLAB_TAG, ISAACSIM_VER, TRAKR_REF, NOVNC_TLS, ...) pass straight through.
set -euo pipefail
REPO=https://github.com/vaishkarni/newton_trakr_brev.git
DIR="$HOME/newton_trakr_brev"
if [ -d "$DIR/.git" ]; then git -C "$DIR" pull -q --ff-only || true; else git clone -q "$REPO" "$DIR"; fi
[ -n "${TRAKR_REF:-}" ] && git -C "$DIR" checkout -q "$TRAKR_REF" || true
sudo -E bash "$DIR/brev/brev-setup.sh"
