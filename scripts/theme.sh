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
Usage: $(basename "$0") start [OPTIONS]

Install system-wide visual theming (icon theme, SDDM greeter).

By default, applies a dark grey background to the stock Fedora SDDM theme.
Use --corners to install the sddm-theme-corners theme from GitHub instead.

Options:
  --corners   Install sddm-theme-corners from GitHub (accent-colored login screen)
  -h, --help  Show this help message and exit

Examples:
  $(basename "$0") start              Dark background on stock SDDM theme
  $(basename "$0") start --corners    Install corners theme with accent colors
EOF
    exit 0
}

SDDM_CORNERS=false

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

while [[ $# -gt 0 ]]; do
    case "$1" in
        --corners)  SDDM_CORNERS=true; shift ;;
        -h|--help)  usage ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            echo "Run '$(basename "$0") --help' for usage." >&2
            exit 1
            ;;
    esac
done

init_logging "theme"
preflight_checks
require_cmd git "sudo dnf install -y git"

# ---------------------------------------------------------------------------
# 1. Icon theme (Tela, system-wide — color follows ACCENT)
# ---------------------------------------------------------------------------
# Installed system-wide so the SDDM greeter (runs as "sddm" user) can
# also use it. No Fedora package available — installed from GitHub.

load_accent

_tela_dir="/usr/share/icons/Tela-${ACCENT_NAME}"
_need_install=false

if [[ ! -d "$_tela_dir" ]]; then
    _need_install=true
elif sudo test -f "$_tela_dir/scalable/places/default-folder.svg"; then
    # Verify the installed theme actually has the right accent color.
    # The Tela installer replaces #5294e2 (default blue) with the accent color.
    # If the folder SVG still contains the default blue, the install was wrong.
    if [[ "$ACCENT_NAME" != "standard" ]] \
        && sudo grep -qi '#5294e2' "$_tela_dir/scalable/places/default-folder.svg"; then
        warn "Tela-${ACCENT_NAME} contains default blue icons — reinstalling..."
        sudo rm -rf "$_tela_dir" "${_tela_dir}-dark" "${_tela_dir}-light"
        _need_install=true
    fi
else
    # Directory exists but is missing expected files — corrupt install
    warn "Tela-${ACCENT_NAME} is incomplete — reinstalling..."
    sudo rm -rf "$_tela_dir" "${_tela_dir}-dark" "${_tela_dir}-light"
    _need_install=true
fi

if [[ "$_need_install" == true ]]; then
    info "Installing Tela ${ACCENT_NAME} icon theme (system-wide)..."
    _tela_tmp=$(mktemp -d)
    _cleanup_files+=("$_tela_tmp")
    git clone --depth 1 https://github.com/vinceliuice/Tela-icon-theme.git "$_tela_tmp"
    sudo bash "$_tela_tmp/install.sh" -d /usr/share/icons "$ACCENT_NAME"
    rm -rf "$_tela_tmp"
    ok "Tela ${ACCENT_NAME} icon theme installed"
else
    ok "Tela ${ACCENT_NAME} icon theme already installed (skipped)"
fi

# Fix permissions — the Tela installer uses cp -r from a mktemp dir (mode 700),
# so subdirectories inherit restricted permissions. Same pattern as corners theme.
for _variant in "$_tela_dir" "${_tela_dir}-dark" "${_tela_dir}-light"; do
    [[ -d "$_variant" ]] && sudo chmod -R a+rX "$_variant"
done

# ---------------------------------------------------------------------------
# 2. SDDM greeter
# ---------------------------------------------------------------------------

info "Configuring SDDM theme..."

_SCRIPT_DIR="$(dirname "$0")"
_SDDM_THEME_NAME=""

if [[ "$SDDM_CORNERS" == true ]]; then
    # -- sddm-theme-corners (GitHub) ------------------------------------------
    # Minimal Qt6 theme with corners layout. Dark grey + accent color.

    sudo dnf install -y \
        qt6-qt5compat \
        qt6-qtsvg

    _SDDM_THEME_DIR="/usr/share/sddm/themes/corners"
    if [[ -d "$_SDDM_THEME_DIR" ]]; then
        ok "sddm-theme-corners already installed (skipped)"
    else
        _corners_tmp=$(mktemp -d)
        _cleanup_files+=("$_corners_tmp")
        git clone --depth 1 https://github.com/aczw/sddm-theme-corners.git "$_corners_tmp"
        sudo cp -r "$_corners_tmp/corners" "$_SDDM_THEME_DIR"
        rm -rf "$_corners_tmp"
        ok "sddm-theme-corners installed"
    fi

    # Always fix permissions (recovers from partial installs where cp succeeded
    # but chmod never ran — mktemp creates mode 700 dirs, cp -r preserves them)
    sudo chmod -R a+rX "$_SDDM_THEME_DIR"

    # Patch Qt5 → Qt6: QtGraphicalEffects was removed in Qt6 (idempotent)
    if compgen -G "$_SDDM_THEME_DIR/components/*.qml" >/dev/null; then
        sudo sed -i 's/import QtGraphicalEffects.*/import Qt5Compat.GraphicalEffects/' \
            "$_SDDM_THEME_DIR"/components/*.qml
    else
        warn "sddm-theme-corners: no components/*.qml found — skipping Qt6 patch"
        warn "The upstream repo may have changed: https://github.com/aczw/sddm-theme-corners"
    fi

    # Set dark background color on root Rectangle (theme defaults to white)
    if [[ -f "$_SDDM_THEME_DIR/Main.qml" ]]; then
        if ! sudo grep -q 'color: "#222222"' "$_SDDM_THEME_DIR/Main.qml"; then
            sudo sed -i '/id: root/a\    color: "#222222"' "$_SDDM_THEME_DIR/Main.qml"
        fi
    else
        warn "sddm-theme-corners: Main.qml not found — skipping background patch"
    fi

    # Deploy custom theme.conf from repo and apply accent colors
    load_accent
    _theme_tmp=$(mktemp)
    _cleanup_files+=("$_theme_tmp")
    cp "$_SCRIPT_DIR/../config/sddm/theme.conf" "$_theme_tmp"
    apply_accent "$_theme_tmp"
    sudo cp "$_theme_tmp" "$_SDDM_THEME_DIR/theme.conf"
    sudo chmod 644 "$_SDDM_THEME_DIR/theme.conf"
    rm -f "$_theme_tmp"

    _SDDM_THEME_NAME="corners"
else
    # -- Stock Fedora Sway theme + dark grey background ------------------------
    _SDDM_THEME_DIR="/usr/share/sddm/themes/03-sway-fedora"
    _bg_src="$_SCRIPT_DIR/../config/sddm/background-dark-grey.png"
    _bg_dest="$_SDDM_THEME_DIR/background-dark-grey.png"

    if [[ ! -d "$_SDDM_THEME_DIR" ]]; then
        warn "Stock SDDM theme not found at $_SDDM_THEME_DIR — is sddm installed?"
    else
        sudo cp "$_bg_src" "$_bg_dest"
        sudo chmod 644 "$_bg_dest"
        # Override background via theme.conf.user (leaves stock theme.conf untouched)
        _user_conf_tmp=$(mktemp)
        _cleanup_files+=("$_user_conf_tmp")
        cat <<'USERCONF' > "$_user_conf_tmp"
[General]
background=background-dark-grey.png
USERCONF
        if ! sudo cmp -s "$_user_conf_tmp" "$_SDDM_THEME_DIR/theme.conf.user" 2>/dev/null; then
            sudo cp "$_user_conf_tmp" "$_SDDM_THEME_DIR/theme.conf.user"
            sudo chmod 644 "$_SDDM_THEME_DIR/theme.conf.user"
        fi
        rm -f "$_user_conf_tmp"
        ok "Dark grey background applied to stock SDDM theme"
    fi

    _SDDM_THEME_NAME="03-sway-fedora"
fi

# Set active SDDM theme
_sddm_conf_tmp=$(mktemp)
_cleanup_files+=("$_sddm_conf_tmp")
cat > "$_sddm_conf_tmp" <<EOF
[Theme]
Current=$_SDDM_THEME_NAME
EOF

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

ok "SDDM configured (theme: $_SDDM_THEME_NAME)"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "============================================"
echo "  Theme setup complete!"
echo "  Log: $LOG"
echo "============================================"
echo ""
