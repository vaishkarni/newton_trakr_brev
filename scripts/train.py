# Copyright (c) 2026, NVIDIA SAE India. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause
"""Thin wrapper around Isaac Lab's rsl_rl train.py that first registers the Trakr tasks.

Run via the Isaac Lab python launcher, e.g.:
    ./isaaclab.sh -p scripts/train.py --task Isaac-Velocity-Flat-Trakr-v0 \
        --headless --num_envs 2048 --max_iterations 300 presets=newton
"""
import os
import runpy
import sys

import trakr_locomotion  # noqa: F401  -- registers the Gym tasks (lazy string entry points)

_ISAACLAB = os.environ.get("ISAACLAB_PATH")
assert _ISAACLAB, "Set ISAACLAB_PATH to your IsaacLab checkout."
_TARGET = os.path.join(_ISAACLAB, "scripts", "reinforcement_learning", "rsl_rl", "train.py")
# Isaac Lab's rsl_rl scripts do `import cli_args` (a sibling module); run_path() does not add
# the script's directory to sys.path, so do it here.
sys.path.insert(0, os.path.dirname(_TARGET))
runpy.run_path(_TARGET, run_name="__main__")
