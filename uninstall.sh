#!/usr/bin/env bash
# Disable or remove the Atmos-style setup. Packages (PipeWire, EasyEffects)
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
  --disable     switch it off but keep the files; ./install.sh --skip-packages
                turns it back on
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
            ee --bypass 1 >/dev/null || true
        fi
    fi
    rm -f "$AUTOSTART"
}

remove_files() {
    info "Removing installed files"
    local p preset_dir
    rm -f "$BIN_DIR/atmos" "$UNIT_DIR/$UNIT" "$PW_CONF"
    rm -rf "$STATE_DIR"
    if have easyeffects; then
        preset_dir="$(ee_preset_dir)"
        for p in "${PRESETS[@]}"; do
            rm -f "$preset_dir/$p.json"
        done
    fi
    systemctl --user daemon-reload
    # drops the Atmos 360 sink; the service itself belongs to PipeWire
    systemctl --user try-restart filter-chain.service >/dev/null 2>&1 || true
}

disable
if [ "$DISABLE_ONLY" = 1 ]; then
    info "Disabled. Re-enable with: ./install.sh --skip-packages"
    exit 0
fi
remove_files
info "Removed. PipeWire and EasyEffects are still installed; effects are bypassed (toggle in EasyEffects or run: easyeffects -b 2)."
