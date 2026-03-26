#!/bin/bash

# Accent Color Theme
# ==================
# Applies the accent color preset to all config files in the repo.
# Installs the matching Tela icon theme. Updates shell prompts.
#
# Usage:  theme-accent-color.sh start [--list]
#         theme-accent-color.sh --list
#
# The accent preset is read from scripts/env (ACCENT=green|orange|blue).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="$REPO_DIR/config"

# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# Global cleanup — temp files register here; EXIT trap cleans them all.
_cleanup_files=()
_cleanup() { rm -rf "${_cleanup_files[@]}" 2>/dev/null || true; }
trap _cleanup EXIT

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $(basename "$0") start [--list]
       $(basename "$0") --list

Apply the accent color preset to all config files.

The accent preset is read from scripts/env (ACCENT=green|orange|blue).
Available presets: green, orange, blue.

Commands:
  start             Apply accent to all config files and install icon theme
  start --list      Apply accent and list all preset hex values

Options:
  --list            List all presets with hex values (no changes applied)
  -h, --help        Show this help message and exit
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# List presets
# ---------------------------------------------------------------------------
list_presets() {
    load_accent
    echo ""
    echo "Active accent: $ACCENT_NAME"
    echo ""
    for preset in green orange blue; do
        read -r p d dk br s ansi <<< "${COLOR_PRESETS[$preset]}"
        local label="$preset"
        [[ "$preset" == "$ACCENT_NAME" ]] && label="$preset (active)"
        echo "  $label:"
        echo "    PRIMARY    $p"
        echo "    DIM        $d"
        echo "    DARK       $dk"
        echo "    BRIGHT     $br"
        echo "    SECONDARY  $s"
        echo "    ANSI       $ansi"
        echo ""
    done
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
_DO_START=false
_DO_LIST=false

if [[ $# -eq 0 ]]; then
    usage
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        start)      _DO_START=true; shift ;;
        --list)     _DO_LIST=true; shift ;;
        -h|--help)  usage ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            echo "Run '$(basename "$0") --help' for usage." >&2
            exit 1
            ;;
    esac
done

# --list without start: just print and exit
if [[ "$_DO_LIST" == true ]] && [[ "$_DO_START" == false ]]; then
    list_presets
    exit 0
fi

# start required for applying changes
if [[ "$_DO_START" == false ]]; then
    usage
fi

init_logging "accent"
load_accent

info "Accent: $ACCENT_NAME (${ACCENT_PRIMARY})"

# ---------------------------------------------------------------------------
# 1. Tela icon theme (user-local)
# ---------------------------------------------------------------------------
require_cmd git "sudo dnf install -y git"

_tela_dir="$HOME/.local/share/icons/Tela-${ACCENT_NAME}"
_need_install=false

if [[ ! -d "$_tela_dir" ]]; then
    _need_install=true
elif [[ -f "$_tela_dir/scalable/places/default-folder.svg" ]]; then
    # Verify the installed theme actually has the right accent color.
    # The Tela installer replaces #5294e2 (default blue) with the accent color.
    if [[ "$ACCENT_NAME" != "standard" ]] \
        && grep -qi '#5294e2' "$_tela_dir/scalable/places/default-folder.svg"; then
        warn "Tela-${ACCENT_NAME} contains default blue icons — reinstalling..."
        rm -rf "$_tela_dir" "${_tela_dir}-dark" "${_tela_dir}-light"
        _need_install=true
    fi
else
    warn "Tela-${ACCENT_NAME} is incomplete — reinstalling..."
    rm -rf "$_tela_dir" "${_tela_dir}-dark" "${_tela_dir}-light"
    _need_install=true
fi

if [[ "$_need_install" == true ]]; then
    info "Installing Tela ${ACCENT_NAME} icon theme (user-local)..."
    _tela_tmp=$(mktemp -d)
    _cleanup_files+=("$_tela_tmp")
    git clone --depth 1 https://github.com/vinceliuice/Tela-icon-theme.git "$_tela_tmp"
    bash "$_tela_tmp/install.sh" -d "$HOME/.local/share/icons" "$ACCENT_NAME"
    rm -rf "$_tela_tmp"
    ok "Tela ${ACCENT_NAME} icon theme installed"
else
    ok "Tela ${ACCENT_NAME} icon theme already installed (skipped)"
fi

# ---------------------------------------------------------------------------
# 2. Apply accent to config files
# ---------------------------------------------------------------------------
info "Applying accent colors to config files..."

_accent_files=(
    "$CONFIG_DIR/kitty/kitty.conf"
    "$CONFIG_DIR/tmux/tmux.conf"
    "$CONFIG_DIR/dunst/dunstrc"
    "$CONFIG_DIR/sddm/theme.conf"
    "$CONFIG_DIR/gtk/settings.ini"
    "$CONFIG_DIR/kde/kdeglobals"
    "$CONFIG_DIR/fish/conf.d/02-colors.fish"
)

if command -v sway &>/dev/null; then
    _accent_files+=(
        "$CONFIG_DIR/sway/config"
        "$CONFIG_DIR/waybar/style.css"
        "$CONFIG_DIR/swaylock/config"
    )
fi

for _af in "${_accent_files[@]}"; do
    apply_accent "$_af"
done

ok "Config files updated"

# ---------------------------------------------------------------------------
# 3. Bash prompt — ANSI escape code for hostname color
# ---------------------------------------------------------------------------
_prompt_file="$CONFIG_DIR/bash/prompt.sh"
if [[ -f "$_prompt_file" ]]; then
    sed -i "s/^\(_GREEN=\"\$(_pc \)[0-9]*/\1${ACCENT_ANSI}/" "$_prompt_file"
    ok "Bash prompt hostname color updated (ANSI $ACCENT_ANSI)"
fi

# ---------------------------------------------------------------------------
# 4. Fish prompt — hostname color uses __accent_dim from 02-colors.fish
#    which was already updated above. No additional sed needed.
# ---------------------------------------------------------------------------
ok "Fish prompt accent updated (via 02-colors.fish)"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================"
echo "  Accent color applied: $ACCENT_NAME"
echo "  Log: $LOG"
echo "============================================"
echo ""
echo "Next steps:"
echo "  1. Reload sway config:    Super+Shift+C"
echo "  2. Reload shell:          source ~/.bashrc  /  exec fish"
echo "  3. Re-apply SDDM theme:  bash scripts/theme-sddm.sh start"
echo ""

# --list after start: also print preset table
if [[ "$_DO_LIST" == true ]]; then
    list_presets
fi
