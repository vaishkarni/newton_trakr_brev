# Copyright (c) 2026, NVIDIA SAE India. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

import importlib
import os
import sys

from isaaclab.utils import configclass

from isaaclab_tasks.manager_based.locomotion.velocity.velocity_env_cfg import (
    EventsCfg,
    LocomotionVelocityRoughEnvCfg,
    StartupEventsCfg,
)
from isaaclab_tasks.utils import PresetCfg

from trakr_locomotion.trakr_cfg import TRAKR_CFG


def _cli_num_envs(default: int) -> int:
    """``--num_envs`` from the command line (train.py/play.py apply it after ``__post_init__``)."""
    argv = sys.argv
    for i, a in enumerate(argv):
        if a == "--num_envs" and i + 1 < len(argv):
            return int(argv[i + 1])
        if a.startswith("--num_envs="):
            return int(a.split("=", 1)[1])
    return default


def _capped_visualizer_cfgs(num_envs: int, env_spacing: float) -> list:
    """Visualizer configs that draw only the first ``TRAKR_VIZ_WORLDS`` environments, camera aimed at them.

    Drawing all 2048 training envs in the Newton GL viewer drops it to ~2 FPS and stalls training.
    On Isaac Lab v3.0.0-beta the ``--visualizer_max_worlds`` CLI override is written to a Kit
    settings store that the kitless (Newton) simulation context never reads, so the cap is put in
    the env config instead. The drawn envs are the first N of the env grid (a corner of it for
    large ``num_envs``), so the camera is pointed at their centroid. Only active when the env var
    is set; ``--viz`` still selects the viewer.
    """
    n = os.environ.get("TRAKR_VIZ_WORLDS")
    if not n:
        return []
    n = int(n)
    num_envs = _cli_num_envs(num_envs)
    cam_pos = cam_tgt = None
    try:
        from isaaclab.cloner import grid_transforms

        origins, _ = grid_transforms(num_envs, env_spacing, device="cpu")
        first = origins[: min(n, num_envs)]
        c = first.mean(0).tolist()
        span = (first.max(0).values - first.min(0).values).tolist()
        # view the drawn group from the side perpendicular to its longer extent
        off = (0.0, -18.0, 8.0) if span[0] >= span[1] else (-18.0, 0.0, 8.0)
        cam_tgt = (c[0], c[1], 0.3)
        cam_pos = (c[0] + off[0], c[1] + off[1], off[2])
    except Exception:  # noqa: BLE001 - camera placement is best-effort
        pass
    cfgs = []
    for mod, cls in (
        ("isaaclab_visualizers.newton", "NewtonVisualizerCfg"),
        ("isaaclab_visualizers.viser", "ViserVisualizerCfg"),
    ):
        try:
            cfg_cls = getattr(importlib.import_module(mod), cls)
        except (ImportError, AttributeError):
            continue
        kwargs = {"max_worlds": n}
        if cam_pos is not None and hasattr(cfg_cls, "camera_position"):
            kwargs.update(camera_position=cam_pos, camera_target=cam_tgt)
        cfgs.append(cfg_cls(**kwargs))
    return cfgs


def _apply_viz_cap(env_cfg) -> None:
    viz = _capped_visualizer_cfgs(env_cfg.scene.num_envs, env_cfg.scene.env_spacing)
    if viz:
        env_cfg.sim.visualizer_cfgs = viz


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
        _apply_viz_cap(self)
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
        _apply_viz_cap(self)  # num_envs changed above
