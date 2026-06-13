#!/usr/bin/env python3
# Copyright (c) 2026, NVIDIA SAE India. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause
"""Apply Isaac Lab v3.0.0-beta <-> Isaac Sim 6.0.0-rc compatibility patches.

Two source-level fixes are required to run Isaac Lab v3.0.0-beta on Windows +
Isaac Sim 6.0.0-rc. Both are idempotent (safe to run repeatedly).

    1. ``isaaclab/sim/spawners/from_files/from_files.py`` does a top-level
       ``import fcntl`` (POSIX-only) which crashes ALL USD spawning on Windows.
       -> make it a guarded import and gate the two ``flock`` calls.

    2. Six runtime modules do ``import omni.physics.tensors.impl.api as physx``,
       but Isaac Sim 6.0 ships the API at ``omni.physics.tensors.api`` (no ``impl``
       subpackage). -> wrap each import in a try/except fallback.

Usage:
    python apply_isaacsim6_compat.py /path/to/IsaacLab
    # or set ISAACLAB_PATH and run with no args.
"""
import os
import re
import sys

TENSORS_FILES = [
    "source/isaaclab_physx/isaaclab_physx/sensors/contact_sensor/contact_sensor.py",
    "source/isaaclab/isaaclab/sensors/ray_caster/multi_mesh_ray_caster.py",
    "source/isaaclab/isaaclab/sensors/ray_caster/ray_cast_utils.py",
    "source/isaaclab_physx/isaaclab_physx/assets/deformable_object/deformable_object.py",
    "source/isaaclab_physx/isaaclab_physx/assets/deformable_object/deformable_object_data.py",
    "source/isaaclab_physx/isaaclab_physx/assets/rigid_object_collection/rigid_object_collection.py",
]
FROM_FILES = "source/isaaclab/isaaclab/sim/spawners/from_files/from_files.py"

TENSORS_FALLBACK = (
    "try:\n"
    "    import omni.physics.tensors.impl.api as physx  # Isaac Sim <= 5.x\n"
    "except ModuleNotFoundError:\n"
    "    import omni.physics.tensors.api as physx  # Isaac Sim 6.0+\n"
)


def patch_tensors_import(path: str) -> bool:
    with open(path, encoding="utf-8") as f:
        text = f.read()
    if "except ModuleNotFoundError:\n    import omni.physics.tensors.api as physx" in text:
        return False  # already patched
    new = re.sub(
        r"^import omni\.physics\.tensors\.impl\.api as physx[^\r\n]*$",
        TENSORS_FALLBACK.rstrip("\n"),
        text,
        flags=re.MULTILINE,
    )
    if new == text:
        return False
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(new)
    return True


def patch_from_files(path: str) -> bool:
    with open(path, encoding="utf-8") as f:
        text = f.read()
    changed = False
    if "except ModuleNotFoundError:  # not available on Windows" not in text:
        text = text.replace(
            "import fcntl\n",
            "try:\n    import fcntl  # POSIX-only; serializes USD spawning under distributed training\n"
            "except ModuleNotFoundError:  # not available on Windows\n    fcntl = None\n",
            1,
        )
        changed = True
    if "if _world_size > 1 and fcntl is not None:" not in text:
        text = text.replace("if _world_size > 1:", "if _world_size > 1 and fcntl is not None:")
        changed = True
    if changed:
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write(text)
    return changed


def main() -> int:
    root = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("ISAACLAB_PATH", "")
    if not root or not os.path.isdir(root):
        print("Usage: python apply_isaacsim6_compat.py /path/to/IsaacLab")
        return 2
    n = 0
    ff = os.path.join(root, FROM_FILES)
    if os.path.isfile(ff) and patch_from_files(ff):
        print(f"[patched] {FROM_FILES} (fcntl guard)")
        n += 1
    for rel in TENSORS_FILES:
        p = os.path.join(root, rel)
        if os.path.isfile(p) and patch_tensors_import(p):
            print(f"[patched] {rel} (tensors.impl.api fallback)")
            n += 1
    print(f"Done. {n} file(s) patched (others already up to date).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
