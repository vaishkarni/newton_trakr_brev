#!/usr/bin/env bash
# Copyright (c) 2026, NVIDIA SAE India. All rights reserved.
# One-shot setup: pin the Newton solver stack, apply Sim-6.0 compat patches,
# and install this package into an existing Isaac Lab (v3.0.0-beta) install.
#
# Usage:  ISAACLAB_PATH=/path/to/IsaacLab bash setup.sh
set -euo pipefail

: "${ISAACLAB_PATH:?Set ISAACLAB_PATH to your IsaacLab checkout (paired with Isaac Sim 6.0)}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Pick the Isaac Sim python launcher (Windows: isaaclab.bat -p ; Linux: ./isaaclab.sh -p).
if [[ -f "$ISAACLAB_PATH/isaaclab.sh" ]]; then PY=("$ISAACLAB_PATH/isaaclab.sh" -p); else PY=("$ISAACLAB_PATH/isaaclab.bat" -p); fi

echo "==> 1/3  Pin Newton solver stack (the --install resolver pulls newer, incompatible versions)"
"${PY[@]}" -m pip install "newton==1.0.0" "mujoco==3.5.0" "mujoco-warp==3.5.0.2"

echo "==> 2/3  Apply Isaac Sim 6.0 compatibility patches to the Isaac Lab source"
"${PY[@]}" "$REPO_DIR/patches/apply_isaacsim6_compat.py" "$ISAACLAB_PATH"

echo "==> 3/3  Install this task package (editable) so the Gym tasks register"
"${PY[@]}" -m pip install -e "$REPO_DIR"

echo
echo "Done. Train with:"
echo "  cd \"$ISAACLAB_PATH\""
echo "  ./isaaclab.sh -p $REPO_DIR/scripts/train.py --task Isaac-Velocity-Flat-Trakr-v0 --headless --num_envs 2048 --max_iterations 300 presets=newton"
