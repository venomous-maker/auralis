#!/usr/bin/env bash
# Install PipeWire + EasyEffects and set up the Atmos-style presets, the
# Atmos 360 stage and the auto-switching watcher for the current user.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$REPO/lib.sh"

SKIP_PACKAGES=0
FILES_ONLY=0
AUTOSTART_EE=1

usage() {
    cat <<EOF
Usage: ./install.sh [options]

  --skip-packages   don't install packages (PipeWire, EasyEffects, plugins)
  --no-autostart    don't start EasyEffects automatically at login
  --files-only      only copy files; don't touch services or EasyEffects
  -h, --help        show this help

Run as your normal user, not root. sudo is used only to install packages.
EOF
}

for arg in "$@"; do
    case "$arg" in
        --skip-packages) SKIP_PACKAGES=1 ;;
        --no-autostart)  AUTOSTART_EE=0 ;;
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
    [ ${#missing[@]} -eq 0 ] || die "missing commands: ${missing[*]}"

    if ! { find /usr/lib /usr/lib64 /usr/local/lib -name 'libspa-filter-graph-plugin-sofa.so' 2>/dev/null || true; } | grep -q .; then
        warn "PipeWire's SOFA spatializer plugin was not found; headphone 360 mode needs PipeWire 1.4+ built with libmysofa"
    fi
    if flatpak list 2>/dev/null | grep -q com.github.wwmm.easyeffects && ! have easyeffects; then
        die "only the Flatpak EasyEffects was found; this setup needs the distribution package"
    fi
}

install_files() {
    local sofa preset_dir
    sofa="$(find_sofa)" || die "no .sofa HRTF file found (normally shipped by libmysofa in /usr/share/libmysofa)"
    preset_dir="$(ee_preset_dir)"

    info "Installing the atmos command to $BIN_DIR"
    install -Dm755 "$REPO/bin/atmos" "$BIN_DIR/atmos"

    info "Installing EasyEffects presets to $preset_dir"
    local p
    for p in "${PRESETS[@]}"; do
        install -Dm644 "$REPO/presets/$p.json" "$preset_dir/$p.json"
    done

    info "Installing the Atmos 360 stage (HRTF: $sofa)"
    mkdir -p "$PW_CONF_DIR"
    sed "s|@SOFA_FILE@|$sofa|g" "$REPO/config/pipewire/sink-atmos-360.conf" > "$PW_CONF"

    info "Installing the auto-switch service"
    install -Dm644 "$REPO/config/systemd/$UNIT" "$UNIT_DIR/$UNIT"
}

install_autostart() {
    info "Starting EasyEffects at login ($AUTOSTART)"
    mkdir -p "$(dirname "$AUTOSTART")"
    cat > "$AUTOSTART" <<EOF
[Desktop Entry]
Type=Application
Name=EasyEffects (Atmos)
Comment=Start EasyEffects in the background for the Atmos-style setup
Exec=easyeffects $(ee_service_args)
Icon=com.github.wwmm.easyeffects
X-GNOME-Autostart-enabled=true
EOF
}

activate() {
    systemctl --user daemon-reload
    systemctl --user enable --now pipewire.service pipewire-pulse.service wireplumber.service >/dev/null 2>&1 \
        || warn "could not enable the PipeWire user services; if you still run PulseAudio, switch to PipeWire and log in again"

    info "Starting the Atmos 360 stage"
    systemctl --user enable filter-chain.service >/dev/null 2>&1 || true
    systemctl --user restart filter-chain.service
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        stage_present && break
        sleep 1
    done
    stage_present || die "the Atmos 360 sink did not appear; check: journalctl --user -u filter-chain"

    info "Routing EasyEffects through the stage"
    ee_set_output "$STAGE_SINK"
    ee_start
    ee --bypass 2 >/dev/null || true

    info "Starting the auto-switch service"
    systemctl --user enable "$UNIT" >/dev/null 2>&1
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
"$BIN_DIR/atmos" status || true
case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) warn "$BIN_DIR is not in your PATH; add it to use the 'atmos' command directly" ;;
esac
