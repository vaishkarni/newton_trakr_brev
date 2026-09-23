#!/usr/bin/env bash
# =============================================================================
# Trakr quadruped locomotion (Isaac Lab 3.0 beta + Newton) node setup for
# NVIDIA Brev (VM mode). Lives inside the task repo itself
# (github.com/vaishkarni/newton_trakr_brev, fork of NMadhub/trakr-newton-locomotion).
#
# Paste brev/launchable-setup.sh as the Launchable "setup script", or run this
# once on an existing VM:   sudo -E bash brev/brev-setup.sh
#
# What it does
#   1. (DESKTOP=1) GPU-backed XFCE desktop on Xorg :0 -> x11vnc -> noVNC on port 6080,
#      systemd service gpu-desktop. Needed only for the Newton OpenGL viewer (--viz newton).
#   2. Isaac Lab ISAACLAB_TAG + Isaac Sim ISAACSIM_VER (pip, Python 3.12 uv venv) in ~/IsaacLab
#   3. This repo's setup.sh (pins newton 1.0.0 / mujoco 3.5.0 / mujoco-warp 3.5.0.2,
#      Isaac Sim 6.0 compat patches, pip install -e .)
#   4. viser (browser viewer for --viz viser, port 8080; no desktop needed) + tensorboard
#   5. Helper scripts in ~ :
#        trakr_train.sh        headless training (fastest)
#        trakr_train_live.sh   training with the Viser web viewer on 8080 (watch it learn)
#        trakr_train_gl.sh     training in the Newton GL viewer on the desktop (16 worlds drawn)
#        trakr_play_web.sh     trained policy in the Viser web viewer on 8080
#        trakr_play.sh         trained policy in the Newton OpenGL viewer on the noVNC desktop
#        trakr_tensorboard.sh  TensorBoard on 6006
#        trakr_record.sh       record the GL viewer to ~/outputs/{train,play}/*.mp4 (60 s, ffmpeg x11grab + NVENC)
#   6. Optional 3-min headless warm-up (warp kernel cache); ~/WORKSHOP.md sheet
#
# Launch parameters (Brev "Launch Parameters" -> env vars), all optional:
#   VNC_PASSWORD    noVNC password (generated if empty; only used when DESKTOP=1)
#   DESKTOP         1 = install the XFCE/noVNC desktop (default), 0 = web viewers only
#   NOVNC_TLS       0 = plain HTTP on 6080 behind a Brev Secure Link [default], 1 = self-signed HTTPS
#   ISAACLAB_TAG    Isaac Lab git tag/branch                     [v3.0.0-beta]
#   ISAACSIM_VER    isaacsim pip version (pypi.nvidia.com)       [6.0.0]
#   ISAACLAB_INSTALL selectors for ./isaaclab.sh --install       [rsl_rl]
#   TRAKR_REPO      this repo (HTTPS), used only if the kit must be re-cloned into the user's home
#   TRAKR_REF       branch/tag/commit to check out                [main]
#   WARMUP          1 = 3-min headless play to warm the warp kernel cache [1]
#   SCREEN          virtual desktop resolution                    [1920x1080]
#   TARGET_USER     login user that owns everything               [auto: sudo user / ubuntu / first /home]
# =============================================================================
set -euo pipefail

DESKTOP="${DESKTOP:-1}"
NOVNC_TLS="${NOVNC_TLS:-0}"
ISAACLAB_TAG="${ISAACLAB_TAG:-v3.0.0-beta}"
ISAACSIM_VER="${ISAACSIM_VER:-6.0.0}"
ISAACLAB_INSTALL="${ISAACLAB_INSTALL:-rsl_rl}"
TRAKR_REPO="${TRAKR_REPO:-https://github.com/vaishkarni/newton_trakr_brev.git}"
TRAKR_REF="${TRAKR_REF:-main}"
WARMUP="${WARMUP:-1}"
SCREEN="${SCREEN:-1920x1080}"
VISER_PORT=8080          # ViserVisualizerCfg default; not changeable from the CLI
LOG=/var/log/trakr-brev-setup.log

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

# ---------------------------------------------------------------- 0. context
if [ "$(id -u)" -ne 0 ]; then
  echo "Re-running with sudo..."; exec sudo -E bash "$0" "$@"
fi
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # repo root (this file is brev/brev-setup.sh)
if [ -z "${TARGET_USER:-}" ]; then
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    TARGET_USER="$SUDO_USER"
  elif id ubuntu >/dev/null 2>&1; then
    TARGET_USER=ubuntu
  else
    TARGET_USER="$(ls /home | head -1)"
  fi
fi
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
as_user() { sudo -u "$TARGET_USER" -H bash -lc "$*"; }
touch "$LOG"; chmod 644 "$LOG"
log "=== Trakr/Newton Brev setup: user=$TARGET_USER home=$TARGET_HOME kit=$KIT_DIR desktop=$DESKTOP isaaclab=$ISAACLAB_TAG isaacsim=$ISAACSIM_VER warmup=$WARMUP"

# ------------------------------------------------------------ 1. preflight
command -v nvidia-smi >/dev/null || { log "ERROR: nvidia-smi missing (no driver?)"; exit 1; }
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader | tee -a "$LOG"
GLIBC=$(ldd --version | head -1 | grep -o "[0-9]*\.[0-9]*$")
awk -v g="$GLIBC" 'BEGIN{exit !(g+0 < 2.35)}' && { log "ERROR: glibc $GLIBC < 2.35; the isaacsim pip wheel needs Ubuntu 22.04+"; exit 1; }
log "glibc $GLIBC OK; RAM $(free -g | awk '/Mem/{print $2}') GiB; disk free $(df -h "$TARGET_HOME" | awk 'NR==2{print $4}')"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null
apt-get install -y -qq --no-install-recommends git curl ca-certificates build-essential cmake \
  libgl1 libglu1-mesa libxrandr2 libxinerama1 libxcursor1 libxi6 libegl1 ffmpeg >>"$LOG" 2>&1

# ------------------------------------------------- 2. the kit / task repo in the user's home
# The Launchable clones this repo before running us; if that clone is not in TARGET_HOME
# (e.g. Brev ran it as root), make a local clone the login user owns.
TRAKR="$TARGET_HOME/newton_trakr_brev"
if [ "$KIT_DIR" != "$TRAKR" ]; then
  if [ ! -d "$TRAKR/.git" ]; then
    log "Cloning kit into $TRAKR (from local $KIT_DIR)"
    as_user "git clone -q '$KIT_DIR' '$TRAKR' && git -C '$TRAKR' remote set-url origin '$TRAKR_REPO'" >>"$LOG" 2>&1
  fi
else
  chown -R "$TARGET_USER:$TARGET_USER" "$TRAKR"
fi
as_user "cd '$TRAKR' && git fetch -q origin 2>/dev/null; git checkout -q '$TRAKR_REF' 2>/dev/null; git pull -q --ff-only 2>/dev/null; true" >>"$LOG" 2>&1
log "Kit at $(as_user "git -C '$TRAKR' rev-parse --short HEAD") ($TRAKR_REF)"
USD_BYTES=$(stat -c %s "$TRAKR/assets/trakr_robot/configuration/robot_base.usd" 2>/dev/null || echo 0)
[ "$USD_BYTES" -gt 1000000 ] && log "Trakr USD assets OK ($USD_BYTES bytes)" || { log "ERROR: robot_base.usd is $USD_BYTES bytes (LFS pointer? shallow clone?)"; exit 1; }

# --------------------------------------------------------- 3. desktop stack (optional)
if [ "$DESKTOP" = "1" ]; then
log "Installing XFCE / x11vnc / noVNC ..."
apt-get install -y -qq --no-install-recommends \
  xfce4 xfce4-terminal x11vnc novnc websockify xterm dbus-x11 xauth \
  mesa-utils x11-xserver-utils openssl >>"$LOG" 2>&1
DRV_MAJOR=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | cut -d. -f1)
dpkg -s "xserver-xorg-video-nvidia-${DRV_MAJOR}" >/dev/null 2>&1 || \
  apt-get install -y -qq "xserver-xorg-video-nvidia-${DRV_MAJOR}" >>"$LOG" 2>&1 || \
  log "WARN: could not install xserver-xorg-video-nvidia-${DRV_MAJOR}; Xorg may fall back to software"

BUSID=$(nvidia-smi --query-gpu=pci.bus_id --format=csv,noheader | head -1)   # 00000000:01:00.0 (domain:bus:dev.fn)
DOM=$((16#$(echo "$BUSID" | cut -d: -f1))); B=$((16#$(echo "$BUSID" | cut -d: -f2))); D=$((16#$(echo "$BUSID" | cut -d: -f3 | cut -d. -f1))); F=$(echo "$BUSID" | cut -d. -f2)
# Xorg BusID syntax is PCI:bus@domain:device:function; the domain is not 0 on some clouds (Crusoe: 0002:00:01.0)
if [ "$DOM" -ne 0 ]; then XBUSID="PCI:$B@$DOM:$D:$F"; else XBUSID="PCI:$B:$D:$F"; fi
W=${SCREEN%x*}; H=${SCREEN#*x}
cat > /etc/X11/xorg.conf <<EOF
Section "ServerLayout"
    Identifier "Layout0"
    Screen 0 "Screen0"
EndSection
Section "Device"
    Identifier "Device0"
    Driver "nvidia"
    BusID "$XBUSID"
    Option "AllowEmptyInitialConfiguration" "True"
EndSection
Section "Monitor"
    Identifier "Monitor0"
EndSection
Section "Screen"
    Identifier "Screen0"
    Device "Device0"
    Monitor "Monitor0"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Virtual $W $H
    EndSubSection
EndSection
EOF
log "xorg.conf written for GPU $BUSID (BusID $XBUSID), virtual screen ${W}x${H}"

install -d -m 700 -o "$TARGET_USER" -g "$TARGET_USER" "$TARGET_HOME/.vnc"
if [ -n "${VNC_PASSWORD:-}" ]; then
  as_user "x11vnc -storepasswd '$VNC_PASSWORD' ~/.vnc/passwd >/dev/null 2>&1 && chmod 600 ~/.vnc/passwd"
elif [ -s "$TARGET_HOME/.vnc/passwd" ]; then
  VNC_PASSWORD="(unchanged, set at first deploy)"
  log "No VNC_PASSWORD given; keeping the existing one (rerun)"
else
  VNC_PASSWORD=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 10)
  log "No VNC_PASSWORD given; generated one (see $TARGET_HOME/WORKSHOP.md)"
  as_user "x11vnc -storepasswd '$VNC_PASSWORD' ~/.vnc/passwd >/dev/null 2>&1 && chmod 600 ~/.vnc/passwd"
fi
WS_TLS_ARGS=""
if [ "$NOVNC_TLS" = "1" ]; then
  PUBIP=$(curl -s -m 5 ifconfig.me || hostname -I | awk '{print $1}')
  [ -f "$TARGET_HOME/.vnc/novnc.crt" ] || as_user "openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
      -keyout ~/.vnc/novnc.key -out ~/.vnc/novnc.crt -subj '/CN=$PUBIP' -addext 'subjectAltName=IP:$PUBIP' >/dev/null 2>&1 && chmod 600 ~/.vnc/novnc.key"
  WS_TLS_ARGS="--cert $TARGET_HOME/.vnc/novnc.crt --key $TARGET_HOME/.vnc/novnc.key --ssl-only"
fi

# noVNC web root overlay: bare Secure Link URL -> vnc.html with autoconnect + scale-to-window
NOVNC_WEB="$TARGET_HOME/.vnc/novnc-web"
as_user "mkdir -p '$NOVNC_WEB' && ln -sfn /usr/share/novnc/* '$NOVNC_WEB/' 2>/dev/null; rm -f '$NOVNC_WEB/index.html' '$NOVNC_WEB/defaults.json'"
cat > "$NOVNC_WEB/index.html" <<'NVEOF'
<!DOCTYPE html><html><head><meta charset="utf-8"><title>Trakr desktop</title>
<meta http-equiv="refresh" content="0; url=vnc.html?autoconnect=true&resize=scale&reconnect=true&reconnect_delay=2000">
<script>location.replace("vnc.html?autoconnect=true&resize=scale&reconnect=true&reconnect_delay=2000" + location.hash);</script>
</head><body>Opening the desktop...</body></html>
NVEOF
cat > "$NOVNC_WEB/defaults.json" <<'NVEOF'
{ "resize": "scale", "reconnect": true, "reconnect_delay": 2000, "show_dot": true }
NVEOF
chown -R "$TARGET_USER:$TARGET_USER" "$NOVNC_WEB"

cat > "$TARGET_HOME/start-desktop.sh" <<EOF
#!/bin/bash
# GPU-backed virtual desktop: Xorg :0 -> XFCE -> x11vnc:5900 (localhost) -> noVNC:6080
pkill -x websockify 2>/dev/null; pkill -x x11vnc 2>/dev/null; sudo pkill -x Xorg 2>/dev/null; sleep 1
sudo nohup Xorg :0 -ac -config /etc/X11/xorg.conf -noreset +extension GLX +extension RANDR +extension RENDER -logfile /tmp/xorg.log > /tmp/xorg.out 2>&1 &
for i in \$(seq 1 20); do [ -S /tmp/.X11-unix/X0 ] && break; sleep 0.5; done
sudo chmod 777 /tmp/.X11-unix 2>/dev/null; sudo chmod a+rw /tmp/.X11-unix/X0 2>/dev/null
export DISPLAY=:0
xset s off -dpms 2>/dev/null || true
OUT=\$(xrandr 2>/dev/null | awk '/ connected/{print \$1; exit}'); [ -n "\$OUT" ] && xrandr --output \$OUT --mode ${W}x${H} 2>/dev/null || true
nohup dbus-launch --exit-with-session startxfce4 > /tmp/xfce.log 2>&1 &
sleep 3
nohup x11vnc -display :0 -forever -shared -noxdamage -rfbport 5900 -localhost -rfbauth \$HOME/.vnc/passwd -o /tmp/x11vnc.log > /dev/null 2>&1 &
sleep 1
nohup websockify --web=$NOVNC_WEB $WS_TLS_ARGS 0.0.0.0:6080 127.0.0.1:5900 > /tmp/websockify.log 2>&1 &
sleep 1
echo "--- status ---"; ss -tlnp | grep -E ":5900|:6080"
DISPLAY=:0 glxinfo 2>/dev/null | grep "OpenGL renderer"
EOF
cat > "$TARGET_HOME/stop-desktop.sh" <<'EOF'
#!/bin/bash
pkill -x websockify 2>/dev/null; pkill -x x11vnc 2>/dev/null; pkill -x xfce4-session 2>/dev/null; sudo pkill -x Xorg 2>/dev/null; true
EOF
chmod +x "$TARGET_HOME"/start-desktop.sh "$TARGET_HOME"/stop-desktop.sh
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME"/start-desktop.sh "$TARGET_HOME"/stop-desktop.sh
echo "$TARGET_USER ALL=(ALL) NOPASSWD: /usr/bin/Xorg, /usr/bin/pkill, /usr/bin/chmod, /usr/bin/xhost" > /etc/sudoers.d/90-gpu-desktop
chmod 440 /etc/sudoers.d/90-gpu-desktop

cat > /etc/systemd/system/gpu-desktop.service <<EOF
[Unit]
Description=GPU-backed XFCE desktop with x11vnc + noVNC on :6080
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
User=$TARGET_USER
WorkingDirectory=$TARGET_HOME
ExecStart=$TARGET_HOME/start-desktop.sh
ExecStop=$TARGET_HOME/stop-desktop.sh

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable gpu-desktop.service >/dev/null 2>&1
# do not kill a running desktop session (and the viewer windows on it) on a rerun
if systemctl is-active --quiet gpu-desktop.service && ss -tln | grep -q ":6080 "; then
  log "gpu-desktop already running; not restarting it (run ~/start-desktop.sh to force)"
else
  systemctl restart gpu-desktop.service || true
  sleep 2
fi
ss -tlnp | grep -q ":6080" && log "noVNC listening on 6080" || log "WARN: noVNC not listening; check /tmp/xorg.log and journalctl -u gpu-desktop"
else
  log "DESKTOP=0: skipping XFCE/noVNC (web viewers only)"
  VNC_PASSWORD="(no desktop installed)"
fi

# --------------------------------------------------------- 4. firewall
if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow 6080/tcp >/dev/null && ufw allow 6006/tcp >/dev/null && ufw allow ${VISER_PORT}/tcp >/dev/null && log "ufw: allowed 6080,6006,${VISER_PORT}/tcp"
  for f in /home/*/init.sh /root/init.sh; do
    [ -f "$f" ] && ! grep -q "ufw allow 6080/tcp" "$f" && sed -i "/^ufw allow 22\/tcp/a ufw allow 6080/tcp\nufw allow 6006/tcp\nufw allow ${VISER_PORT}/tcp" "$f" && log "added ports to $f"
  done
fi

# ------------------------------------------------- 5. uv + Isaac Lab + Isaac Sim (pip)
# Documented route for Isaac Lab v3.0.0-beta: Python 3.12 uv venv, isaacsim[all,extscache]==6.0.0
# from pypi.nvidia.com, torch 2.10.0+cu128, then ./isaaclab.sh --install. The venv is created at
# <repo>/env_isaaclab, which isaaclab.sh picks up automatically (no activation needed).
LAB="$TARGET_HOME/IsaacLab"
if ! as_user "test -x ~/.local/bin/uv || command -v uv" >/dev/null 2>&1; then
  as_user "curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh" >>"$LOG" 2>&1 || true
  as_user "test -x ~/.local/bin/uv" && log "uv installed to ~/.local/bin/uv" || { log "ERROR: uv install failed"; exit 1; }
fi
as_user "grep -q '.local/bin' ~/.bashrc || echo 'export PATH=\$HOME/.local/bin:\$PATH' >> ~/.bashrc"
UV="$TARGET_HOME/.local/bin/uv"; as_user "command -v uv" >/dev/null 2>&1 && UV=uv

as_user "git config --global url.'https://github.com/'.insteadOf 'git@github.com:'" >>"$LOG" 2>&1 || true
if [ ! -d "$LAB/.git" ]; then
  log "Cloning Isaac Lab $ISAACLAB_TAG ..."
  as_user "git clone -q --branch '$ISAACLAB_TAG' --depth 1 https://github.com/isaac-sim/IsaacLab.git '$LAB'" >>"$LOG" 2>&1
fi
log "Isaac Lab at $(as_user "git -C '$LAB' describe --tags --always")"

if [ ! -x "$LAB/env_isaaclab/bin/python" ]; then
  log "Creating Python 3.12 venv $LAB/env_isaaclab ..."
  as_user "cd '$LAB' && '$UV' venv --python 3.12 --seed env_isaaclab" >>"$LOG" 2>&1
fi
in_venv() { as_user "cd '$LAB' && source env_isaaclab/bin/activate && export PATH='$TARGET_HOME/.local/bin':\$PATH OMNI_KIT_ACCEPT_EULA=YES ISAACLAB_PATH='$LAB' && $*"; }

if ! in_venv "python -c 'import isaacsim' 2>/dev/null"; then
  log "Installing isaacsim[all,extscache]==$ISAACSIM_VER (several GB, 5-15 min) ..."
  # --index-strategy unsafe-best-match: isaacsim-core pins mujoco-usd-converter==0.1.0, which only PyPI has,
  # while the package also exists (other versions) on pypi.nvidia.com; uv's default first-index rule then fails.
  # This merges the indexes exactly like plain pip does.
  in_venv "'$UV' pip install --upgrade pip && '$UV' pip install 'isaacsim[all,extscache]==$ISAACSIM_VER' --extra-index-url https://pypi.nvidia.com --index-strategy unsafe-best-match" >>"$LOG" 2>&1 \
    || { log "ERROR: isaacsim install failed (see $LOG)"; exit 1; }
fi
log "isaacsim: $(in_venv "'$UV' pip show isaacsim 2>/dev/null | awk '/^Version/{print \$2}'")"

in_venv "'$UV' pip show torch 2>/dev/null | grep -q 'Version: 2.10.0+cu128'" || {
  log "Installing torch 2.10.0+cu128 ..."
  in_venv "'$UV' pip install -U torch==2.10.0 torchvision==0.25.0 --index-url https://download.pytorch.org/whl/cu128" >>"$LOG" 2>&1
}

if ! in_venv "python -c 'import isaaclab_newton, isaaclab_rl, isaaclab_tasks, isaaclab_visualizers' 2>/dev/null"; then
  log "./isaaclab.sh --install $ISAACLAB_INSTALL (10-20 min) ..."
  in_venv "./isaaclab.sh --install '$ISAACLAB_INSTALL'" >>"$LOG" 2>&1 \
    || { log "ERROR: isaaclab --install failed (see $LOG)"; exit 1; }
fi

# ------------------------------------------------- 6. this repo's setup.sh (pins + patches + pip -e)
log "Running $TRAKR/setup.sh (solver pins + Sim 6.0 patches + pip install -e) ..."
in_venv "cd '$TRAKR' && ISAACLAB_PATH='$LAB' bash setup.sh" >>"$LOG" 2>&1 \
  || { log "ERROR: setup.sh failed (see $LOG)"; exit 1; }

# viser = browser viewer for --viz viser (isaaclab_visualizers[viser] extra); tensorboard for curves
in_venv "python -c 'import viser' 2>/dev/null" || in_venv "'$UV' pip install 'viser>=1.0.16'" >>"$LOG" 2>&1 || log "WARN: viser install failed; --viz viser will not work"
in_venv "python -c 'import tensorboard' 2>/dev/null" || in_venv "'$UV' pip install tensorboard" >>"$LOG" 2>&1 || true

log "Python packages: $(in_venv "'$UV' pip list 2>/dev/null | grep -E '^(isaaclab|isaacsim |newton|mujoco|warp-lang|rsl-rl|viser|torch ) ' | tr -s ' ' | tr '\n' ';'")"
in_venv "'$UV' pip check" >>"$LOG" 2>&1 && log "pip check: clean" || log "NOTE: pip check reports conflicts (known for Isaac Lab 3.0 beta + isaacsim 6.0, github.com/isaac-sim/IsaacLab/issues/6200); details in $LOG"
in_venv "python -c 'import gymnasium as gym, trakr_locomotion; assert \"Isaac-Velocity-Flat-Trakr-Play-v0\" in gym.registry; print(\"tasks registered\")'" >>"$LOG" 2>&1 \
  && log "Trakr Gym tasks registered" || { log "ERROR: trakr_locomotion import/registration check failed"; exit 1; }

# ------------------------------------------------- 7. shell env + helpers
as_user "grep -q 'newton_trakr_brev' ~/.bashrc || cat >> ~/.bashrc <<'EOS'

# newton_trakr_brev: GUI apps go to the browser desktop; Isaac Sim EULA; Isaac Lab paths
export DISPLAY=:0
export OMNI_KIT_ACCEPT_EULA=YES
export ISAACLAB_PATH=\$HOME/IsaacLab
export TRAKR_PATH=\$HOME/newton_trakr_brev
alias lab='\$ISAACLAB_PATH/isaaclab.sh'
EOS"

cat > "$TARGET_HOME/trakr_common.sh" <<'EOF'
# sourced by the trakr_*.sh helpers
export DISPLAY=:0 OMNI_KIT_ACCEPT_EULA=YES ISAACLAB_PATH=$HOME/IsaacLab TRAKR_PATH=$HOME/newton_trakr_brev
cd "$ISAACLAB_PATH"
# RECORD=1 (or yes/true, or a number of seconds): once the Newton Viewer window is up, record it with
# ~/trakr_record.sh. Default clip length is 60 s. Training must run in the GL viewer (trakr_train_gl.sh).
case "${RECORD:-}" in
  ''|0|no|false) ;;
  *)
    case "$RECORD" in *[!0-9]*|1) REC_SEC=60 ;; *) REC_SEC=$RECORD ;; esac
    ( for i in $(seq 1 180); do xwininfo -root -tree 2>/dev/null | grep -q "Newton Viewer" && break; sleep 1; done
      sleep 5; ~/trakr_record.sh "$REC_SEC" ) > "$HOME/outputs/last_record.log" 2>&1 &
    ;;
esac
EOF
cat > "$TARGET_HOME/trakr_train.sh" <<'EOF'
#!/bin/bash
# Headless training (fastest). Usage: ~/trakr_train.sh [max_iterations=300] [num_envs=2048] [extra args]
set -e; source ~/trakr_common.sh
IT=${1:-300}; NE=${2:-2048}; shift 2 2>/dev/null || shift $# 2>/dev/null || true
exec ./isaaclab.sh -p "$TRAKR_PATH/scripts/train.py" \
  --task Isaac-Velocity-Flat-Trakr-v0 --num_envs "$NE" --max_iterations "$IT" presets=newton "$@"
EOF
cat > "$TARGET_HOME/trakr_train_live.sh" <<'EOF'
#!/bin/bash
# Training with the Viser web viewer (Brev Secure Link "viewer", port 8080): watch the policy learn.
# Only the first WORLDS envs are drawn; training is slower than headless. Usage: ~/trakr_train_live.sh [iters=300] [num_envs=2048] [worlds=16]
set -e; source ~/trakr_common.sh
IT=${1:-300}; NE=${2:-2048}; WORLDS=${3:-16}; shift 3 2>/dev/null || shift $# 2>/dev/null || true
export TRAKR_VIZ_WORLDS=$WORLDS TRAKR_NUM_ENVS=$NE   # cap + camera aim via the env config (trakr_locomotion/rough_env_cfg.py)
exec ./isaaclab.sh -p "$TRAKR_PATH/scripts/train.py" \
  --task Isaac-Velocity-Flat-Trakr-v0 --num_envs "$NE" --max_iterations "$IT" presets=newton \
  --viz viser --visualizer_max_worlds "$WORLDS" "$@"
EOF
cat > "$TARGET_HOME/trakr_train_gl.sh" <<'EOF'
#!/bin/bash
# Training in the Newton OpenGL viewer on the noVNC desktop (recordable with RECORD=<sec> or ~/trakr_record.sh).
# Only the first WORLDS envs are drawn (TRAKR_VIZ_WORLDS): drawing all 2048 drops the viewer to ~2 FPS and stalls training.
# Usage: RECORD=1 ~/trakr_train_gl.sh [iters=300] [num_envs=2048] [worlds=16]   (RECORD=1 -> 60 s clip)
set -e; source ~/trakr_common.sh
IT=${1:-300}; NE=${2:-2048}; WORLDS=${3:-16}; shift 3 2>/dev/null || shift $# 2>/dev/null || true
export TRAKR_VIZ_WORLDS=$WORLDS TRAKR_NUM_ENVS=$NE   # cap + camera aim via the env config (trakr_locomotion/rough_env_cfg.py)
exec ./isaaclab.sh -p "$TRAKR_PATH/scripts/train.py" \
  --task Isaac-Velocity-Flat-Trakr-v0 --num_envs "$NE" --max_iterations "$IT" presets=newton \
  --viz newton --visualizer_max_worlds "$WORLDS" "$@"
EOF
cat > "$TARGET_HOME/trakr_play_web.sh" <<'EOF'
#!/bin/bash
# Trained policy in the Viser web viewer (Brev Secure Link "viewer", port 8080). No desktop needed.
# Usage: ~/trakr_play_web.sh [num_envs=16] [extra args, e.g. --checkpoint path]
set -e; source ~/trakr_common.sh
NUM=${1:-16}; shift || true
export TRAKR_NUM_ENVS=$NUM
# Isaac Lab's play.py otherwise looks for a run under logs/rsl_rl/trakr_flat; default to the shipped policy
CKPT=(); case " $* " in *" --checkpoint "*) ;; *) CKPT=(--checkpoint "$TRAKR_PATH/exported/model_299.pt");; esac
exec ./isaaclab.sh -p "$TRAKR_PATH/scripts/play.py" \
  --task Isaac-Velocity-Flat-Trakr-Play-v0 --num_envs "$NUM" presets=newton --viz viser "${CKPT[@]}" "$@"
EOF
cat > "$TARGET_HOME/trakr_play.sh" <<'EOF'
#!/bin/bash
# Trained policy in the Newton OpenGL viewer, on the noVNC browser desktop (Secure Link "desktop").
# Usage: ~/trakr_play.sh [num_envs=16] [extra args, e.g. --checkpoint path]
set -e; source ~/trakr_common.sh
NUM=${1:-16}; shift || true
export TRAKR_NUM_ENVS=$NUM
# Isaac Lab's play.py otherwise looks for a run under logs/rsl_rl/trakr_flat; default to the shipped policy
CKPT=(); case " $* " in *" --checkpoint "*) ;; *) CKPT=(--checkpoint "$TRAKR_PATH/exported/model_299.pt");; esac
exec ./isaaclab.sh -p "$TRAKR_PATH/scripts/play.py" \
  --task Isaac-Velocity-Flat-Trakr-Play-v0 --num_envs "$NUM" presets=newton --viz newton "${CKPT[@]}" "$@"
EOF
cat > "$TARGET_HOME/trakr_tensorboard.sh" <<'EOF'
#!/bin/bash
# TensorBoard for the training logs on port 6006 (Brev Secure Link "tensorboard").
source ~/trakr_common.sh
exec ./isaaclab.sh -p -m tensorboard.main --logdir logs/rsl_rl --host 0.0.0.0 --port 6006
EOF
cat > "$TARGET_HOME/trakr_record.sh" <<'EOF'
#!/bin/bash
# Record the VM desktop (the Newton GL viewer) to ~/outputs/<mode>/<name>_<stamp>.mp4, where <mode> is
# detected from what is running: train (train.py), play (play.py) or desktop (nothing). 30 fps, captured on
# the node, so the clip is smooth even when noVNC looks choppy. NVENC when available, else libx264.
# Usage: ~/trakr_record.sh [seconds=60] [name=trakr_<mode>]   (run in a 2nd terminal while the viewer is open,
#        or let the helpers start it: RECORD=1 ~/trakr_play.sh / RECORD=1 ~/trakr_train_gl.sh 150  (RECORD=<sec> for other lengths))
set -e
SEC=${1:-60}; NAME=${2:-}
export DISPLAY=:0
if pgrep -x ffmpeg >/dev/null; then echo "a recording is already running (pgrep ffmpeg); not starting another"; exit 1; fi
if pgrep -f "[t]rain.py --task" >/dev/null; then MODE=train
elif pgrep -f "[p]lay.py --task" >/dev/null; then MODE=play
else MODE=desktop; fi
NAME=${NAME:-trakr_$MODE}
OUT=$HOME/outputs/$MODE; mkdir -p "$OUT"
F="$OUT/${NAME}_$(date +%Y%m%d_%H%M%S)_$$.mp4"   # pid suffix: two recorders started in the same second must not share a file
RES=$(xrandr 2>/dev/null | awk '/\*/{print $1; exit}'); RES=${RES:-1920x1080}
# probe NVENC with a frame size above its minimum (64x64 is rejected)
if ffmpeg -hide_banner -loglevel error -f lavfi -i nullsrc=s=320x240 -t 0.2 -c:v h264_nvenc -f null - 2>/dev/null; then
  ENC=(-c:v h264_nvenc -preset p4 -b:v 8M)          # GPU encoder
else
  ENC=(-c:v libx264 -preset veryfast -crf 20)       # CPU fallback
fi
echo "recording [$MODE] $RES for ${SEC}s -> $F (${ENC[1]})"
ffmpeg -hide_banner -loglevel error -y -f x11grab -framerate 30 -video_size "$RES" -i :0 -t "$SEC" "${ENC[@]}" -pix_fmt yuv420p -movflags +faststart "$F"
echo "saved $F ($(du -h "$F" | cut -f1))"
EOF
chmod +x "$TARGET_HOME"/trakr_*.sh
install -d -o "$TARGET_USER" -g "$TARGET_USER" "$TARGET_HOME/outputs" "$TARGET_HOME/outputs/train" "$TARGET_HOME/outputs/play"
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME"/trakr_*.sh

# ------------------------------------------------- 8. warm-up (headless; caches Kit extensions + warp kernels)
if [ "$WARMUP" = "1" ]; then
  log "Warm-up: headless play for up to 3 min (compiles warp kernels, caches the policy export) ..."
  set +e
  in_venv "cd '$LAB' && timeout 180 ./isaaclab.sh -p '$TRAKR/scripts/play.py' --task Isaac-Velocity-Flat-Trakr-Play-v0 --num_envs 16 presets=newton --checkpoint '$TRAKR/exported/model_299.pt'" >>"$LOG" 2>&1
  RC=$?; set -e
  if [ $RC -eq 124 ]; then log "Warm-up ran until the timeout (good: the sim loop was running)";
  elif [ $RC -eq 0 ]; then log "Warm-up finished";
  else log "WARN: warm-up exited with code $RC; grep -n 'Error\|Traceback' $LOG"; fi
fi

# ------------------------------------------------- 9. attendee sheet
PUBIP=$(curl -s -m 5 ifconfig.me || hostname -I | awk '{print $1}')
cat > "$TARGET_HOME/WORKSHOP.md" <<EOF
# Trakr quadruped locomotion on Isaac Lab 3.0 + Newton (Brev)

Secure Links: viewer (8080, Viser web viewer) | tensorboard (6006) | desktop (6080, noVNC; password: $VNC_PASSWORD)
Direct access if no Secure Links: http://$PUBIP:8080 / :6006 / :6080

Full attendee guide: ~/newton_trakr_brev/WORKSHOP.md (PDF in brev/docs/). Quick version:
Open a terminal (Brev "Terminal" button, or ssh, or the noVNC desktop) and run:

    ~/trakr_play_web.sh          # trained policy, 16 robots -> open the 'viewer' link (Viser, WebGL)
    ~/trakr_train_live.sh 300    # train and watch it learn in the 'viewer' link (slower than headless)
    ~/trakr_train.sh 300 2048    # headless training, ~4-5 min for 300 iterations
    ~/trakr_tensorboard.sh       # curves on the 'tensorboard' link
    ~/trakr_play_web.sh 16 --checkpoint ~/IsaacLab/logs/rsl_rl/trakr_flat/<run>/model_299.pt
    ~/trakr_play.sh              # same policy in the Newton OpenGL viewer, on the 'desktop' link
    ~/trakr_record.sh            # 2nd terminal: 60 s clip of the viewer -> ~/outputs/play/ or ~/outputs/train/ (auto-detected)
    RECORD=1 ~/trakr_play.sh     # or let the helper record 60 s automatically once the viewer window is up (RECORD=<sec> for other lengths)
    RECORD=1 ~/trakr_train_gl.sh 150    # training in the GL viewer (16 of 2048 envs drawn), 60 s clip in ~/outputs/train/

The play helpers load the shipped policy exported/model_299.pt unless you pass --checkpoint.
Isaac Lab runs Newton in kitless mode here: a play/train launch takes about 1 min to the first frame.
The Viser page is empty until the sim loop starts; reload it if it was opened too early.
Newton GL viewer keys: W/A/S/D move, Q/E down/up, left-drag rotate, scroll zoom, H sidebar, ESC quit.
Rough terrain (Isaac-Velocity-Rough-Trakr-v0) does NOT work on the Newton backend of this Isaac Lab beta
(contact sensor init fails on generated terrain); the workshop uses the flat task only.

Clips in ~/outputs/{train,play} are smooth 30 fps captures made on the node (noVNC playback may look choppy).
Download: brev copy or scp from your laptop, e.g.  scp <instance>:outputs/trakr_*.mp4 .
Paths: Isaac Lab ~/IsaacLab (venv env_isaaclab, launcher ./isaaclab.sh -p), repo ~/newton_trakr_brev.
presets=newton is required on Sim 6.0. Setup log: $LOG. Desktop service: gpu-desktop.
EOF
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/WORKSHOP.md"; chmod 600 "$TARGET_HOME/WORKSHOP.md"
log "=== DONE. Instructions in $TARGET_HOME/WORKSHOP.md"
