#!/bin/bash

# Fedora Theme Setup
# ==================
# Installs system-wide visual theming: icon theme and SDDM greeter.
# Run after bootstrap.sh (needs git, sudo). Run as a regular user.

set -euo pipefail

# Global cleanup — temp files register here; EXIT trap cleans them all.
_cleanup_files=()
_cleanup() { rm -rf "${_cleanup_files[@]}" 2>/dev/null || true; }
trap _cleanup EXIT

# shellcheck source=scripts/lib/common.sh
source "$(dirname "$0")/lib/common.sh"

# Source user env (gitignored), fall back to sample
if [[ -f "$(dirname "$0")/env" ]]; then
    # shellcheck source=scripts/env
    source "$(dirname "$0")/env"
else
    # shellcheck source=scripts/env-sample
    source "$(dirname "$0")/env-sample"
fi

# ---------------------------------------------------------------------------
# Usage / argument parsing
# ---------------------------------------------------------------------------

usage() {
    cat <<EOF
Usage: $(basename "$0") start

Install system-wide visual theming (icon theme, SDDM greeter).

Options:
  -h, --help    Show this help message and exit

Examples:
  $(basename "$0") start    Install icon theme + configure SDDM greeter
EOF
    exit 0
}

# Require "start" subcommand; no args or -h/--help prints usage
if [[ $# -eq 0 ]]; then
    usage
fi
case "$1" in
    start)      shift ;;
    -h|--help)  usage ;;
    *)
        echo "ERROR: Unknown command: $1" >&2
        echo "Run '$(basename "$0") --help' for usage." >&2
        exit 1
        ;;
esac

init_logging "theme"
preflight_checks
require_cmd git "sudo dnf install -y git"

# ---------------------------------------------------------------------------
# 1. Icon theme (Tela, system-wide — color follows ACCENT)
# ---------------------------------------------------------------------------
# Installed system-wide so the SDDM greeter (runs as "sddm" user) can
# also use it. No Fedora package available — installed from GitHub.

load_accent
if [[ -d "/usr/share/icons/Tela-${ACCENT_NAME}" ]]; then
    ok "Tela ${ACCENT_NAME} icon theme already installed (skipped)"
else
    info "Installing Tela ${ACCENT_NAME} icon theme (system-wide)..."
    _tela_tmp=$(mktemp -d)
    _cleanup_files+=("$_tela_tmp")
    git clone --depth 1 https://github.com/vinceliuice/Tela-icon-theme.git "$_tela_tmp"
    sudo bash "$_tela_tmp/install.sh" -d /usr/share/icons "$ACCENT_NAME"
    rm -rf "$_tela_tmp"
    ok "Tela ${ACCENT_NAME} icon theme installed"
fi

# ---------------------------------------------------------------------------
# 2. SDDM greeter — sddm-theme-corners
# ---------------------------------------------------------------------------
# Minimal Qt6 SDDM theme with corners layout. Dark grey + accent color.

info "Configuring SDDM theme..."

# Dependencies for sddm-theme-corners (Qt6 greeter)
sudo dnf install -y \
    qt6-qt5compat \
    qt6-qtsvg

# Install theme from GitHub if not present
_SDDM_THEME_DIR="/usr/share/sddm/themes/corners"
if [[ -d "$_SDDM_THEME_DIR" ]]; then
    ok "sddm-theme-corners already installed (skipped)"
else
    _corners_tmp=$(mktemp -d)
    _cleanup_files+=("$_corners_tmp")
    git clone --depth 1 https://github.com/aczw/sddm-theme-corners.git "$_corners_tmp"
    sudo cp -r "$_corners_tmp/corners" "$_SDDM_THEME_DIR"
    # Fix permissions before patching — mktemp creates mode 700 dirs and
    # cp -r preserves them, so the glob below would fail as unprivileged user.
    sudo chmod -R a+rX "$_SDDM_THEME_DIR"
    # Validate expected structure before patching (guards against upstream changes)
    if compgen -G "$_SDDM_THEME_DIR/components/*.qml" >/dev/null; then
        # Patch Qt5 → Qt6: QtGraphicalEffects was removed in Qt6
        sudo sed -i 's/import QtGraphicalEffects.*/import Qt5Compat.GraphicalEffects/' \
            "$_SDDM_THEME_DIR"/components/*.qml
    else
        warn "sddm-theme-corners: no components/*.qml found — skipping Qt6 patch"
        warn "The upstream repo may have changed: https://github.com/aczw/sddm-theme-corners"
    fi
    if [[ -f "$_SDDM_THEME_DIR/Main.qml" ]]; then
        # Set dark background color on root Rectangle (theme defaults to white)
        sudo sed -i '/id: root/a\    color: "#222222"' "$_SDDM_THEME_DIR/Main.qml"
    else
        warn "sddm-theme-corners: Main.qml not found — skipping background patch"
    fi
    rm -rf "$_corners_tmp"
    ok "sddm-theme-corners installed"
fi

# Deploy custom theme.conf from repo and apply accent colors
load_accent
_theme_tmp=$(mktemp)
_cleanup_files+=("$_theme_tmp")
cp "$(dirname "$0")/../config/sddm/theme.conf" "$_theme_tmp"
apply_accent "$_theme_tmp"
sudo cp "$_theme_tmp" "$_SDDM_THEME_DIR/theme.conf"
sudo chmod 644 "$_SDDM_THEME_DIR/theme.conf"
rm -f "$_theme_tmp"

# Set corners as active SDDM theme
_sddm_conf_tmp=$(mktemp)
_cleanup_files+=("$_sddm_conf_tmp")
cat <<'SDDMCONF' > "$_sddm_conf_tmp"
[Theme]
Current=corners
SDDMCONF

sudo mkdir -p /etc/sddm.conf.d
if ! sudo cmp -s "$_sddm_conf_tmp" /etc/sddm.conf.d/theme.conf 2>/dev/null; then
    sudo cp "$_sddm_conf_tmp" /etc/sddm.conf.d/theme.conf
    sudo chmod 644 /etc/sddm.conf.d/theme.conf
fi
rm -f "$_sddm_conf_tmp"

# Disable greetd if it was previously enabled
if systemctl is-enabled greetd &>/dev/null; then
    sudo systemctl disable greetd
fi
sudo systemctl enable sddm

ok "SDDM + corners theme configured"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "============================================"
echo "  Theme setup complete!"
echo "  Log: $LOG"
echo "============================================"
echo ""
