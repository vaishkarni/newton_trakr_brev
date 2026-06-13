# Copyright (c) 2026, NVIDIA SAE India. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

"""Articulation configuration for the Trakr quadruped robot.

Topology (from ``assets/trakr_robot/configuration/robot_physics.usd``):

* Articulation root: ``/trakr``
* Bodies: ``base`` + per-leg ``{FL,FR,RL,RR}_{hip,thigh,shank,toe}`` (17 rigid bodies)
* Joints (revolute, 12 DoF): ``{FL,FR,RL,RR}_{adduction,hip,knee}``
* 17 convex-hull colliders, Z-up, meters.

Notes:
    * ``robot_physics.usd`` is used (not the top-level ``robot.usd``, which composes a
      payload/variant resolving to a collision-less skeleton).
    * The drive gains baked into the source USD are unsuitable for RL, so PD gains are
      set explicitly below and override the USD values at load time.
"""

import os

import isaaclab.sim as sim_utils
from isaaclab.actuators import DCMotorCfg
from isaaclab.assets.articulation import ArticulationCfg

# USD path resolved relative to this package so the repo is portable.
_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
TRAKR_USD_PATH = os.path.normpath(
    os.path.join(_THIS_DIR, "..", "assets", "trakr_robot", "configuration", "robot_physics.usd")
)

TRAKR_CFG = ArticulationCfg(
    spawn=sim_utils.UsdFileCfg(
        usd_path=TRAKR_USD_PATH,
        activate_contact_sensors=True,
        rigid_props=sim_utils.RigidBodyPropertiesCfg(
            disable_gravity=False,
            retain_accelerations=False,
            linear_damping=0.0,
            angular_damping=0.0,
            max_linear_velocity=1000.0,
            max_angular_velocity=1000.0,
            max_depenetration_velocity=1.0,
        ),
        articulation_props=sim_utils.ArticulationRootPropertiesCfg(
            enabled_self_collisions=False,
            solver_position_iteration_count=4,
            solver_velocity_iteration_count=0,
        ),
    ),
    init_state=ArticulationCfg.InitialStateCfg(
        # Nominal standing pose (validated: episode length saturates at the cap by ~iter 50).
        pos=(0.0, 0.0, 0.32),
        joint_pos={
            ".*_adduction": 0.0,
            ".*_hip": 0.4,
            ".*_knee": -0.4,
        },
        joint_vel={".*": 0.0},
    ),
    soft_joint_pos_limit_factor=0.9,
    actuators={
        "legs": DCMotorCfg(
            joint_names_expr=[".*_adduction", ".*_hip", ".*_knee"],
            effort_limit=30.0,
            saturation_effort=30.0,
            velocity_limit=20.0,
            stiffness=25.0,
            damping=0.5,
            friction=0.0,
        ),
    },
)
"""Configuration for the Trakr quadruped robot (12 DoF, DC-motor legs)."""
