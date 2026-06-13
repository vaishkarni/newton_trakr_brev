# Copyright (c) 2026, NVIDIA SAE India. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

"""Trakr quadruped flat/rough velocity-locomotion tasks for Isaac Lab (Newton backend).

Importing this package registers the Gym tasks:

* ``Isaac-Velocity-Flat-Trakr-v0`` / ``Isaac-Velocity-Flat-Trakr-Play-v0``
* ``Isaac-Velocity-Rough-Trakr-v0`` / ``Isaac-Velocity-Rough-Trakr-Play-v0``

Always train/play with the Newton backend via the Hydra preset ``presets=newton``.
"""

import gymnasium as gym

from . import agents

gym.register(
    id="Isaac-Velocity-Flat-Trakr-v0",
    entry_point="isaaclab.envs:ManagerBasedRLEnv",
    disable_env_checker=True,
    kwargs={
        "env_cfg_entry_point": f"{__name__}.flat_env_cfg:TrakrFlatEnvCfg",
        "rsl_rl_cfg_entry_point": f"{agents.__name__}.rsl_rl_ppo_cfg:TrakrFlatPPORunnerCfg",
    },
)

gym.register(
    id="Isaac-Velocity-Flat-Trakr-Play-v0",
    entry_point="isaaclab.envs:ManagerBasedRLEnv",
    disable_env_checker=True,
    kwargs={
        "env_cfg_entry_point": f"{__name__}.flat_env_cfg:TrakrFlatEnvCfg_PLAY",
        "rsl_rl_cfg_entry_point": f"{agents.__name__}.rsl_rl_ppo_cfg:TrakrFlatPPORunnerCfg",
    },
)

gym.register(
    id="Isaac-Velocity-Rough-Trakr-v0",
    entry_point="isaaclab.envs:ManagerBasedRLEnv",
    disable_env_checker=True,
    kwargs={
        "env_cfg_entry_point": f"{__name__}.rough_env_cfg:TrakrRoughEnvCfg",
        "rsl_rl_cfg_entry_point": f"{agents.__name__}.rsl_rl_ppo_cfg:TrakrRoughPPORunnerCfg",
    },
)

gym.register(
    id="Isaac-Velocity-Rough-Trakr-Play-v0",
    entry_point="isaaclab.envs:ManagerBasedRLEnv",
    disable_env_checker=True,
    kwargs={
        "env_cfg_entry_point": f"{__name__}.rough_env_cfg:TrakrRoughEnvCfg_PLAY",
        "rsl_rl_cfg_entry_point": f"{agents.__name__}.rsl_rl_ppo_cfg:TrakrRoughPPORunnerCfg",
    },
)
