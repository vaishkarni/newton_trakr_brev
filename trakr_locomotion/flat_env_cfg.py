# Copyright (c) 2026, NVIDIA SAE India. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

from isaaclab_newton.physics import MJWarpSolverCfg, NewtonCfg
from isaaclab_physx.physics import PhysxCfg

from isaaclab.sim import SimulationCfg
from isaaclab.utils import configclass

from isaaclab_tasks.utils import PresetCfg

from trakr_locomotion.rough_env_cfg import TrakrRoughEnvCfg


@configclass
class PhysicsCfg(PresetCfg):
    """Multi-backend physics preset. ``newton`` is the intended backend for this project."""

    default = PhysxCfg(gpu_max_rigid_patch_count=10 * 2**15)
    newton = NewtonCfg(
        solver_cfg=MJWarpSolverCfg(
            # njmax/nconmax raised from the A1 template (60/30) to avoid `nefc overflow`
            # warnings observed at play time with trakr's contact count.
            njmax=128,
            nconmax=64,
            cone="pyramidal",
            impratio=1,
            integrator="implicitfast",
        ),
        num_substeps=1,
        debug_mode=False,
    )
    physx = default


@configclass
class TrakrFlatEnvCfg(TrakrRoughEnvCfg):
    sim: SimulationCfg = SimulationCfg(physics=PhysicsCfg())

    def __post_init__(self):
        super().__post_init__()

        # override rewards
        self.rewards.flat_orientation_l2.weight = -2.5
        self.rewards.feet_air_time.weight = 0.25

        # flat terrain
        self.scene.terrain.terrain_type = "plane"
        self.scene.terrain.terrain_generator = None
        # no height scan on flat ground
        self.scene.height_scanner = None
        self.observations.policy.height_scan = None
        self.curriculum.terrain_levels = None


class TrakrFlatEnvCfg_PLAY(TrakrFlatEnvCfg):
    def __post_init__(self) -> None:
        super().__post_init__()

        self.scene.num_envs = 50
        self.scene.env_spacing = 2.5
        self.observations.policy.enable_corruption = False
        self.events.base_external_force_torque = None
        self.events.push_robot = None
