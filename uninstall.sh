#!/usr/bin/env bash
# Disable or remove Auralis. Packages (PipeWire, EasyEffects)
# are never removed.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$REPO/lib.sh"

DISABLE_ONLY=0

usage() {
    cat <<EOF
Usage: ./uninstall.sh [options]

  (no option)   remove everything this project installed
  --disable     switch it off but keep the presets and the auralis command;
                ./install.sh --skip-packages turns it back on
  -h, --help    show this help
EOF
}

for arg in "$@"; do
    case "$arg" in
        --disable) DISABLE_ONLY=1 ;;
        -h|--help) usage; exit 0 ;;
        *)         usage >&2; exit 1 ;;
    esac
done

disable() {
    info "Stopping the auto-switch service"
    systemctl --user disable --now "$UNIT" >/dev/null 2>&1 || true

    if have easyeffects; then
        info "Pointing EasyEffects back at the default output device"
        ee_set_output
        if ee_running; then
            info "Bypassing EasyEffects effects"
            ee --load-preset Auralis-Mic-Off >/dev/null || true
            ee --bypass 1 >/dev/null || true
        fi
    fi
    rm -f "$AUTOSTART"

    # Take the stage down too: left behind, it could be picked as an output
    # device with nothing keeping it pointed at real hardware.
    info "Removing the Auralis 360 stage"
    rm -f "$PW_CONF"
    systemctl --user try-restart filter-chain.service >/dev/null 2>&1 || true
}

remove_files() {
    info "Removing installed files"
    local p
    rm -f "$BIN_DIR/auralis" "$UNIT_DIR/$UNIT"
    rm -rf "$STATE_DIR"
    if have easyeffects; then
        for p in "${OUTPUT_PRESETS[@]}"; do
            rm -f "$(ee_preset_dir output)/$p.json"
        done
        for p in "${INPUT_PRESETS[@]}"; do
            rm -f "$(ee_preset_dir input)/$p.json"
        done
    fi
    systemctl --user daemon-reload
}

disable
if [ "$DISABLE_ONLY" = 1 ]; then
    info "Disabled. Re-enable with: ./install.sh --skip-packages"
    exit 0
fi
remove_files
info "Removed. PipeWire and EasyEffects are still installed; effects are bypassed (toggle in EasyEffects or run: easyeffects -b 2)."
