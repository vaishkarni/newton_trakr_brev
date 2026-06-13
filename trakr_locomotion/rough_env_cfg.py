# Copyright (c) 2026, NVIDIA SAE India. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

from isaaclab.utils import configclass

from isaaclab_tasks.manager_based.locomotion.velocity.velocity_env_cfg import (
    EventsCfg,
    LocomotionVelocityRoughEnvCfg,
    StartupEventsCfg,
)
from isaaclab_tasks.utils import PresetCfg

from trakr_locomotion.trakr_cfg import TRAKR_CFG


@configclass
class TrakrNewtonEventsCfg(EventsCfg):
    def __post_init__(self):
        super().__post_init__()
        self.push_robot = None
        self.base_external_force_torque.params["asset_cfg"].body_names = "base"
        self.reset_robot_joints.params["position_range"] = (1.0, 1.0)
        self.reset_base.params = {
            "pose_range": {"x": (-0.5, 0.5), "y": (-0.5, 0.5), "yaw": (-3.14, 3.14)},
            "velocity_range": {
                "x": (0.0, 0.0),
                "y": (0.0, 0.0),
                "z": (0.0, 0.0),
                "roll": (0.0, 0.0),
                "pitch": (0.0, 0.0),
                "yaw": (0.0, 0.0),
            },
        }


@configclass
class TrakrPhysxEventsCfg(TrakrNewtonEventsCfg, StartupEventsCfg):
    def __post_init__(self):
        super().__post_init__()
        self.add_base_mass.params["mass_distribution_params"] = (-1.0, 3.0)
        self.add_base_mass.params["asset_cfg"].body_names = "base"
        self.base_com = None


@configclass
class TrakrEventsCfg(PresetCfg):
    default = TrakrPhysxEventsCfg()
    newton = TrakrNewtonEventsCfg()
    physx = default


@configclass
class TrakrRoughEnvCfg(LocomotionVelocityRoughEnvCfg):
    events: TrakrEventsCfg = TrakrEventsCfg()

    def __post_init__(self):
        super().__post_init__()

        self.scene.robot = TRAKR_CFG.replace(prim_path="{ENV_REGEX_NS}/Robot")
        self.scene.height_scanner.prim_path = "{ENV_REGEX_NS}/Robot/base"
        # scale down the terrains because the robot is small
        self.scene.terrain.terrain_generator.sub_terrains["boxes"].grid_height_range = (0.025, 0.1)
        self.scene.terrain.terrain_generator.sub_terrains["random_rough"].noise_range = (0.01, 0.06)
        self.scene.terrain.terrain_generator.sub_terrains["random_rough"].noise_step = 0.01

        # reduce action scale (small robot)
        self.actions.joint_pos.scale = 0.25

        # rewards
        self.rewards.feet_air_time.params["sensor_cfg"].body_names = ".*_toe"
        self.rewards.feet_air_time.weight = 0.01
        self.rewards.undesired_contacts = None
        self.rewards.dof_torques_l2.weight = -0.0002
        self.rewards.track_lin_vel_xy_exp.weight = 1.5
        self.rewards.track_ang_vel_z_exp.weight = 0.75
        self.rewards.dof_acc_l2.weight = -2.5e-7

        # terminations
        self.terminations.base_contact.params["sensor_cfg"].body_names = "base"


@configclass
class TrakrRoughEnvCfg_PLAY(TrakrRoughEnvCfg):
    def __post_init__(self):
        super().__post_init__()

        self.scene.num_envs = 50
        self.scene.env_spacing = 2.5
        self.scene.terrain.max_init_terrain_level = None
        if self.scene.terrain.terrain_generator is not None:
            self.scene.terrain.terrain_generator.num_rows = 5
            self.scene.terrain.terrain_generator.num_cols = 5
            self.scene.terrain.terrain_generator.curriculum = False

        self.observations.policy.enable_corruption = False
        self.events.base_external_force_torque = None
        self.events.push_robot = None
