# Create the Trakr / Newton Launchable on NVIDIA Brev

Participants get three browser links: a **Viser web viewer** (robots walking / training live),
**TensorBoard**, and an optional **noVNC desktop** for the Newton OpenGL viewer. Everything on the
VM is done by `brev/brev-setup.sh`; you only build the Launchable around it in the Brev console.

## GPU / compute

| Pick | Why |
|---|---|
| **NVIDIA L40S 48 GB, 1 GPU, AWS `g6e.2xlarge`** (8 vCPU, 64 GiB RAM, ~$2.69/h on Brev) | RTX-class Ada GPU (Isaac Sim is only supported on RTX GPUs), stoppable + rebootable + flex ports, 64 GiB RAM is comfortable for the `isaacsim` pip install and 2048 Newton envs. |
| Cheaper: A10G 24 GB, AWS `g5.4xlarge` (64 GiB RAM, ~$1.95/h) | Also RTX-class; fine for this task (2048 envs is small). `g5.2xlarge` (32 GiB) is the minimum. |
| Avoid | A100 / H100 (no RT cores; Isaac Sim unsupported), anything with < 32 GiB RAM, Ubuntu < 22.04 (the isaacsim wheel needs glibc 2.35). |

Disk: **150 GiB** (isaacsim + extscache ~25 GB, torch ~5 GB, Isaac Lab, logs). Image: Ubuntu 22.04.

## Console steps

1. **Launchables -> Create Launchable.**
2. Files: "I don't have any code files".
3. Runtime: **VM Mode** (not Container mode: the desktop needs the host driver and Xorg).
   Setup script -> **Paste Script** -> paste `brev/launchable-setup.sh` (the 10-line one).
4. Jupyter: No.
5. Secure Links (exposed ports):

   | Name | Port | What |
   |---|---|---|
   | viewer | 8080 | Viser web viewer (`~/trakr_play_web.sh`, `~/trakr_train_live.sh`) |
   | tensorboard | 6006 | training curves (`~/trakr_tensorboard.sh`) |
   | desktop | 6080 | noVNC desktop for the Newton OpenGL viewer (`~/trakr_play.sh`); skip if `DESKTOP=0` |

6. Launch parameters:

   | Name | Type | Default | Note |
   |---|---|---|---|
   | VNC_PASSWORD | text (secret) | generated | shared desktop password; printed in `~/WORKSHOP.md` |
   | DESKTOP | choice 1 / 0 | 1 | 0 = skip XFCE/noVNC, web viewers only (setup ~3 min faster) |
   | WARMUP | choice 1 / 0 | 1 | headless play for up to 8 min during setup so the first viewer launch is quick |
   | TRAKR_REF | text | main | pin to a commit once the dry run passes |
   | ISAACLAB_TAG | text | v3.0.0-beta | the pairing this repo was developed against |
   | ISAACSIM_VER | text | 6.0.0 | pypi.nvidia.com wheel (cp312) |
   | NOVNC_TLS | choice 0 / 1 | 0 | keep 0 behind the Secure Link |

7. Compute: as above. Name `newton-trakr-locomotion`, description "Isaac Lab 3.0 beta + Newton:
   Trakr quadruped locomotion, live in the browser". Access: anyone with the link. Create, copy the URL.

## Verified 2026-09-23 (Brev instance on Crusoe `l40s-48gb.1x`, driver 565.57.01)

| Step | Result |
|---|---|
| `brev-setup.sh` to `=== DONE` | ~10 min (isaacsim wheels 46 s on that network, Isaac Lab install 40 s, 3-min warm-up) |
| `~/trakr_play_web.sh` | Viser on 8080, 16 robots walking with the shipped policy |
| `~/trakr_play.sh` | Newton Viewer window on the noVNC desktop, 62 FPS, 16 envs |
| `~/trakr_train.sh 40` | 0.7 s/iteration at 2048 envs (300 iterations = ~3.5 min), checkpoints in `logs/rsl_rl/trakr_flat/<run>/` |
| `~/trakr_tensorboard.sh` | port 6006 |
| `~/trakr_train_live.sh 30` | Viser on 8080 during training, ~1.2 s/iteration (16 worlds drawn) |
| `RECORD=60 ~/trakr_train_gl.sh 150 2048 16` | 2048 envs trained at 0.46 s/iteration while the GL viewer draws 16 of them at ~50 FPS; 60 s NVENC clip (18 MB) in `~/outputs/train/` |

Isaac Lab runs the Newton backend in **kitless mode** (no Kit/RTX start), so launches take about a minute.
noVNC playback of the GL viewer looks choppy in the browser; the sim itself runs at 60+ FPS on the node.

## Dry run (expect 10-15 min to DONE on a fast network, up to 40 min elsewhere)

1. Deploy from the share URL. In the instance terminal: `tail -f /var/log/trakr-brev-setup.log`
   until `=== DONE`. Checkpoints: `Trakr USD assets OK`, `isaacsim: 6.0.0...`, `Python packages: ... newton 1.0.0; mujoco-warp 3.5.0.2 ... viser`,
   `Trakr Gym tasks registered`, warm-up line.
2. `~/trakr_play_web.sh` -> open the **viewer** link. 16 robots should walk within about 1 min (the shipped policy `exported/model_299.pt` is used unless you pass `--checkpoint`).
3. `~/trakr_train_live.sh 100` -> the viewer shows the first 16 envs while training (they fall,
   then start walking within ~50 iterations). Ctrl-C when done.
4. `~/trakr_train.sh 300` (headless, ~4-5 min) + `~/trakr_tensorboard.sh` -> **tensorboard** link.
   Then `~/trakr_play_web.sh 16 --checkpoint ~/IsaacLab/logs/rsl_rl/trakr_flat/<run>/model_299.pt`.
5. If `DESKTOP=1`: **desktop** link -> password -> Terminal -> `~/trakr_play.sh` (Newton OpenGL viewer).
6. Pin `TRAKR_REF` to the tested commit. Stop (keep) or delete the instance.

## Live training: what you can see, and how

- **Viser web viewer (no desktop needed):** `--viz viser` on `train.py` or `play.py` serves a WebGL
  page on port 8080. `~/trakr_train_live.sh` draws only the first 16 of 2048 envs
  (`--visualizer_max_worlds 16`) to keep the overhead small; still expect training to be slower
  than headless. Reload the page if you opened it before the sim loop started.
- **TensorBoard (no desktop needed):** reward / episode-length curves update every iteration.
- **Newton OpenGL viewer (`--viz newton`)** is a native window, so it needs the noVNC desktop
  (`DESKTOP=1`, port 6080). Fastest and prettiest, but heavier to set up.
- Headless training (`~/trakr_train.sh`) is the fastest way to get a policy; play it afterwards.
- **Drawing a subset of envs:** the Newton GL and Viser viewers draw every env by default, and with 2048 envs the GL
  viewer falls to ~2 FPS and training to 10 s/iteration. The helpers set `TRAKR_VIZ_WORLDS` (default 16) and
  `TRAKR_NUM_ENVS`; `trakr_locomotion/rough_env_cfg.py` turns that into visualizer configs with `max_worlds` and a
  camera aimed at the drawn envs (the first N of the env grid, i.e. one corner). Isaac Lab's own
  `--visualizer_max_worlds` flag is ignored in kitless mode on v3.0.0-beta (it goes to a Kit settings store).
- **Video clips:** `~/trakr_record.sh [seconds=60] [name]` records the VM desktop (the Newton GL viewer) with
  ffmpeg x11grab + NVENC at 30 fps. It detects what is running and files the clip under `~/outputs/train/` or
  `~/outputs/play/`. Or start the recording automatically with the helpers: `RECORD=60 ~/trakr_play.sh` and
  `RECORD=60 ~/trakr_train_gl.sh 150` (training in the GL viewer with 16 of the 2048 envs drawn; drawing all of
  them drops the viewer to ~2 FPS and stalls training).
  60 s is ~33 MB with NVENC. Fetch with `scp <instance>:outputs/train/*.mp4 .` or `brev copy`.

## Troubleshooting

Fixed during the dry run (all in this repo now): uv could not resolve isaacsim (`--index-strategy unsafe-best-match`
added), Xorg found no GPU when the PCI domain is not 0 (BusID now `PCI:bus@domain:dev:fn`), `import cli_args` failed
in the wrapper scripts (sys.path fix in `scripts/*.py`), and play.py needs `--checkpoint` (helpers default to `exported/model_299.pt`).

- `isaacsim install failed`: check RAM/disk in the log; rerun `sudo -E bash ~/newton_trakr_brev/brev/brev-setup.sh` (idempotent).
- Viser page blank: the sim has not started yet (wait for "Viser server running" in the terminal) or a
  previous run still holds port 8080 (`pkill -f play.py`).
- `Failed to get DOF velocities`: you ran without `presets=newton` (PhysX is broken on Sim 6.0-rc).
- `geom_dataid expects 1 dim`: solver stack drifted; rerun `cd ~/newton_trakr_brev && ISAACLAB_PATH=~/IsaacLab bash setup.sh`.
- Desktop blank: `sudo systemctl restart gpu-desktop`, check `/tmp/xorg.log`. "CUDA/OpenGL interop" warnings are harmless.
- `pip check` conflicts in the log are expected (Isaac Lab issue #6200).
- `RuntimeError: Explicitly requested visualizer(s) ['newton'] could not be configured`: only happens if you
  changed `ISAACLAB_TAG` to `release/3.0.0` or `develop`, where `newton` became an alias of `newton_gl`
  (Isaac Lab PR #7960, fixed 2026-09-23). On the default `v3.0.0-beta` tag `--viz newton` is the valid name.
  Workaround on newer branches: `~/trakr_play.sh 16 --viz newton_gl`.
- Viser binds 0.0.0.0:8080 without authentication. Behind Brev Secure Links only the link holder reaches it;
  do not add a raw TCP port rule for 8080 on a public node.
