# Copyright (c) 2026, NVIDIA SAE India. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause
"""Thin wrapper around Isaac Lab's rsl_rl play.py that first registers the Trakr tasks.

Watch the trained policy in the Newton viewer (no RTX/kit renderer needed):
    ./isaaclab.sh -p scripts/play.py --task Isaac-Velocity-Flat-Trakr-Play-v0 \
        --num_envs 16 presets=newton --viz newton
"""
import os
import runpy

import trakr_locomotion  # noqa: F401  -- registers the Gym tasks (lazy string entry points)

_ISAACLAB = os.environ.get("ISAACLAB_PATH")
assert _ISAACLAB, "Set ISAACLAB_PATH to your IsaacLab checkout."
_TARGET = os.path.join(_ISAACLAB, "scripts", "reinforcement_learning", "rsl_rl", "play.py")
runpy.run_path(_TARGET, run_name="__main__")
