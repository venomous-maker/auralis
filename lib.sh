#!/usr/bin/env bash
# Shared helpers for install.sh and uninstall.sh. Sourced, not executed.

STAGE_SINK="effect_input.atmos-360"
PRESETS=(Atmos-Speakers-360 Atmos-Headphones-360)

BIN_DIR="$HOME/.local/bin"
PW_CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/pipewire/filter-chain.conf.d"
PW_CONF="$PW_CONF_DIR/sink-atmos-360.conf"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT="atmos-auto.service"
AUTOSTART="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/easyeffects-atmos.desktop"
STATE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/atmos"
EE_RC="${XDG_CONFIG_HOME:-$HOME/.config}/easyeffects/db/easyeffectsrc"
EE_GSCHEMA="com.github.wwmm.easyeffects.streamoutputs"

info() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# EasyEffects prints Qt noise on stderr; keep its real output only.
ee() { easyeffects "$@" 2>/dev/null; }

ee_major() {
    ee --version | grep -oE '[0-9]+' | head -n1
}

# EasyEffects 8 (Qt) keeps presets in ~/.local/share, 7 (GTK) in ~/.config.
ee_preset_dir() {
    if [ "$(ee_major)" -ge 8 ] 2>/dev/null; then
        echo "${XDG_DATA_HOME:-$HOME/.local/share}/easyeffects/output"
    else
        echo "${XDG_CONFIG_HOME:-$HOME/.config}/easyeffects/output"
    fi
}

ee_running() { pgrep -x easyeffects >/dev/null 2>&1; }

ee_stop() {
    ee_running || return 0
    ee --quit
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        ee_running || return 0
        sleep 0.5
    done
    pkill -x easyeffects || true
}

ee_service_args() {
    if [ "$(ee_major)" -ge 8 ] 2>/dev/null; then
        echo "--service-mode --hide-window"
    else
        echo "--gapplication-service"
    fi
}

ee_start() {
    ee_running && return 0
    # shellcheck disable=SC2046
    setsid nohup easyeffects $(ee_service_args) >/dev/null 2>&1 &
    sleep 4
}

# Point EasyEffects' output at a fixed sink ($1), or back at the system
# default (no argument). EasyEffects 7 exposes this through GSettings and
# picks it up live; EasyEffects 8 only reads its config file at startup, so
# it has to be stopped while the file is edited.
ee_set_output() {
    local device="${1:-}"
    if have gsettings && gsettings list-schemas 2>/dev/null | grep -qx "$EE_GSCHEMA"; then
        if [ -n "$device" ]; then
            gsettings set "$EE_GSCHEMA" use-default-output-device false
            gsettings set "$EE_GSCHEMA" output-device "$device"
        else
            gsettings reset "$EE_GSCHEMA" use-default-output-device
            gsettings reset "$EE_GSCHEMA" output-device
        fi
        return
    fi

    local was_running=0
    ee_running && was_running=1
    ee_stop
    mkdir -p "$(dirname "$EE_RC")"
    python3 - "$EE_RC" "$device" <<'EOF'
import os, re, sys

path, device = sys.argv[1], sys.argv[2]
text = open(path).read() if os.path.exists(path) else ""
text = re.sub(r"^(outputDevice|useDefaultOutputDevice)=.*\n", "", text, flags=re.M)
if device:
    lines = f"outputDevice={device}\nuseDefaultOutputDevice=false\n"
    if "[StreamOutputs]\n" in text:
        text = text.replace("[StreamOutputs]\n", "[StreamOutputs]\n" + lines, 1)
    else:
        text += ("\n" if text and not text.endswith("\n\n") else "") + "[StreamOutputs]\n" + lines
with open(path, "w") as f:
    f.write(text)
EOF
    [ "$was_running" = 1 ] && ee_start
    return 0
}

find_sofa() {
    local f
    for f in /usr/share/libmysofa/default.sofa /usr/share/libmysofa/MIT_KEMAR_normal_pinna.sofa \
             /usr/local/share/libmysofa/default.sofa; do
        [ -e "$f" ] && { echo "$f"; return 0; }
    done
    { find /usr/share /usr/local/share -maxdepth 3 -name '*.sofa' 2>/dev/null || true; } | head -n1 | grep .
}

stage_present() {
    pactl list sinks short 2>/dev/null | grep -q "$STAGE_SINK"
}
