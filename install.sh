#!/usr/bin/env bash
# Install PipeWire + EasyEffects and set up the Auralis presets, the
# Auralis 360 stage and the auto-switching watcher for the current user.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$REPO/lib.sh"

SKIP_PACKAGES=0
FILES_ONLY=0
AUTOSTART_EE=1
MIC=1

usage() {
    cat <<EOF
Usage: ./install.sh [options]

  --skip-packages   don't install packages (PipeWire, EasyEffects, plugins)
  --no-autostart    don't start EasyEffects automatically at login
  --no-mic          don't turn on microphone noise suppression
  --files-only      only copy files; don't touch services or EasyEffects
  -h, --help        show this help

Run as your normal user, not root. sudo is used only to install packages.
EOF
}

for arg in "$@"; do
    case "$arg" in
        --skip-packages) SKIP_PACKAGES=1 ;;
        --no-autostart)  AUTOSTART_EE=0 ;;
        --no-mic)        MIC=0 ;;
        --files-only)    FILES_ONLY=1; SKIP_PACKAGES=1 ;;
        -h|--help)       usage; exit 0 ;;
        *)               usage >&2; exit 1 ;;
    esac
done

[ "$(id -u)" -ne 0 ] || die "run this as your normal user, not root (it configures your user session)"

install_packages() {
    if have apt-get; then
        info "Installing packages with apt"
        sudo apt-get update
        sudo apt-get install -y pipewire pipewire-pulse wireplumber pulseaudio-utils \
            easyeffects lsp-plugins-lv2 calf-plugins libmysofa1 python3
    elif have dnf; then
        info "Installing packages with dnf"
        sudo dnf install -y pipewire pipewire-pulseaudio wireplumber pulseaudio-utils \
            easyeffects lsp-plugins-lv2 calf libmysofa python3
    elif have pacman; then
        info "Installing packages with pacman"
        sudo pacman -S --needed --noconfirm pipewire pipewire-pulse wireplumber libpulse \
            easyeffects lsp-plugins-lv2 calf libmysofa python
    elif have zypper; then
        info "Installing packages with zypper"
        sudo zypper install -y pipewire pipewire-pulseaudio wireplumber pulseaudio-utils \
            easyeffects lsp-plugins-lv2 calf libmysofa1 python3
    else
        die "no supported package manager found (apt, dnf, pacman, zypper); install PipeWire, WirePlumber, EasyEffects, LSP + Calf plugins and libmysofa yourself, then re-run with --skip-packages"
    fi
}

check_requirements() {
    local cmd missing=()
    for cmd in pipewire pactl pw-cli easyeffects python3 systemctl; do
        have "$cmd" || missing+=("$cmd")
    done
    if [ ${#missing[@]} -ne 0 ]; then
        [[ " ${missing[*]} " != *" easyeffects "* ]] || ! have flatpak \
            || warn "a Flatpak EasyEffects does not count; this setup needs the distribution package"
        die "missing commands: ${missing[*]}"
    fi

    if ! { find /usr/lib /usr/lib64 /usr/local/lib -name 'libspa-filter-graph-plugin-sofa.so' 2>/dev/null || true; } | grep -q .; then
        warn "PipeWire's SOFA spatializer plugin was not found; headphone 360 mode needs PipeWire 1.4+ built with libmysofa"
    fi

    local pw_version
    pw_version="$(pipewire --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | tail -n1 || true)"
    case "$pw_version" in
        0.*|1.0|1.1|1.2|1.3) warn "PipeWire $pw_version is older than 1.4; the Auralis 360 stage may not load" ;;
    esac
    if [ "$(ee_major)" -lt 8 ] 2>/dev/null; then
        warn "EasyEffects $(ee_major) found; the speaker preset's Crosstalk Canceller needs EasyEffects 8 and will be skipped"
    fi
    pactl -f json info >/dev/null 2>&1 \
        || die "pactl does not support JSON output (needs pulseaudio-utils 16 or newer)"
    systemctl --user cat filter-chain.service >/dev/null 2>&1 \
        || die "PipeWire's filter-chain.service was not found; your PipeWire package does not ship it"
}

install_files() {
    local sofa p
    sofa="$(find_sofa)" || die "no .sofa HRTF file found (normally shipped by libmysofa in /usr/share/libmysofa)"

    info "Installing the auralis command to $BIN_DIR"
    install -Dm755 "$REPO/bin/auralis" "$BIN_DIR/auralis"

    info "Installing EasyEffects presets to $(dirname "$(ee_preset_dir output)")"
    for p in "${OUTPUT_PRESETS[@]}"; do
        install -Dm644 "$REPO/presets/$p.json" "$(ee_preset_dir output)/$p.json"
    done
    for p in "${INPUT_PRESETS[@]}"; do
        install -Dm644 "$REPO/presets/$p.json" "$(ee_preset_dir input)/$p.json"
    done

    info "Installing the Auralis 360 stage (HRTF: $sofa)"
    mkdir -p "$PW_CONF_DIR"
    sed "s|@SOFA_FILE@|$sofa|g" "$REPO/config/pipewire/sink-auralis-360.conf" > "$PW_CONF"

    info "Installing the auto-switch service"
    install -Dm644 "$REPO/config/systemd/$UNIT" "$UNIT_DIR/$UNIT"
}

install_autostart() {
    info "Starting EasyEffects at login ($AUTOSTART)"
    mkdir -p "$(dirname "$AUTOSTART")"
    cat > "$AUTOSTART" <<EOF
[Desktop Entry]
Type=Application
Name=EasyEffects (Auralis)
Comment=Start EasyEffects in the background for Auralis
Exec=easyeffects $(ee_service_args)
Icon=com.github.wwmm.easyeffects
X-GNOME-Autostart-enabled=true
EOF
}

activate() {
    systemctl --user daemon-reload
    systemctl --user enable --now pipewire.service pipewire-pulse.service wireplumber.service >/dev/null 2>&1 \
        || warn "could not enable the PipeWire user services; if you still run PulseAudio, switch to PipeWire and log in again"

    info "Starting the Auralis 360 stage"
    systemctl --user enable filter-chain.service >/dev/null 2>&1 || true
    systemctl --user restart filter-chain.service
    for _ in $(seq 10); do
        sink_present "$STAGE_SINK" && break
        sleep 1
    done
    sink_present "$STAGE_SINK" || die "the Auralis 360 sink did not appear; check: journalctl --user -u filter-chain"

    info "Routing EasyEffects through the stage"
    ee_set_output "$STAGE_SINK"
    ee_start
    ee --bypass 2 >/dev/null || true

    if [ "$MIC" = 1 ]; then
        info "Enabling microphone noise suppression"
        ee --load-preset Auralis-Mic >/dev/null || warn "could not load the microphone preset"
    fi

    info "Starting the auto-switch service"
    # reenable: an older install may have hooked it to a different target
    systemctl --user reenable "$UNIT" >/dev/null 2>&1
    if ! systemctl --user is-active --quiet graphical-session.target; then
        # Window managers that never reach graphical-session.target would
        # otherwise not start the service at all.
        warn "graphical-session.target is not active on this desktop; starting the service at login instead"
        systemctl --user add-wants default.target "$UNIT" >/dev/null 2>&1 || true
    fi
    systemctl --user restart "$UNIT"
    sleep 3
}

[ "$SKIP_PACKAGES" = 1 ] || install_packages
check_requirements
install_files

if [ "$FILES_ONLY" = 1 ]; then
    info "Files installed. Services and EasyEffects were left untouched."
    exit 0
fi

[ "$AUTOSTART_EE" = 0 ] || install_autostart
activate

info "Done. Current state:"
"$BIN_DIR/auralis" status || true
case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) warn "$BIN_DIR is not in your PATH; add it to use the 'auralis' command directly" ;;
esac
