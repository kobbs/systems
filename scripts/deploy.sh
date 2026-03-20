#!/bin/bash

# Dotfiles Deploy Script — Phase 2
# =================================
# Symlinks configs from this repo into ~/.config/.
# Safe to re-run: already-correct symlinks are skipped, existing files are
# backed up with a .bak suffix.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="$REPO_DIR/config"

# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

init_logging "deploy"

# ---------------------------------------------------------------------------
# Link a single file. Skips if already linked correctly. Backs up existing
# non-symlink files. Replaces incorrect symlinks.
# Usage: link_file <repo_path> <target_path>
# ---------------------------------------------------------------------------
link_file() {
    local src="$1"
    local dst="$2"

    if [[ ! -e "$src" ]]; then
        warn "Source does not exist, skipping: $src"
        return 0
    fi

    mkdir -p "$(dirname "$dst")"

    # Already points to the correct target — nothing to do.
    if [[ "$(readlink "$dst" 2>/dev/null)" == "$src" ]]; then
        ok "$dst already linked (skipped)"
        return 0
    fi

    if [[ -L "$dst" ]]; then
        rm "$dst"
    elif [[ -e "$dst" ]]; then
        local bak="$dst.bak.$(date +%Y%m%d%H%M%S)"
        warn "Backing up existing file: $dst → $bak"
        mv "$dst" "$bak"
    fi

    ln -s "$src" "$dst"
    ok "$dst → $src"
}

# ---------------------------------------------------------------------------
# Sway
# ---------------------------------------------------------------------------
info "Deploying sway config..."
link_file "$CONFIG_DIR/sway/config" "$HOME/.config/sway/config"

# ---------------------------------------------------------------------------
# Waybar
# ---------------------------------------------------------------------------
info "Deploying waybar config..."
link_file "$CONFIG_DIR/waybar/config"    "$HOME/.config/waybar/config"
link_file "$CONFIG_DIR/waybar/style.css" "$HOME/.config/waybar/style.css"
link_file "$CONFIG_DIR/waybar/scripts"   "$HOME/.config/waybar/scripts"
chmod +x "$CONFIG_DIR"/waybar/scripts/*.sh
ok "waybar scripts marked executable"

# ---------------------------------------------------------------------------
# Kanshi
# ---------------------------------------------------------------------------
info "Deploying kanshi config..."
link_file "$CONFIG_DIR/kanshi/config" "$HOME/.config/kanshi/config"

# ---------------------------------------------------------------------------
# GTK theming (single source file for both GTK 3 and GTK 4)
# ---------------------------------------------------------------------------
info "Deploying GTK dark theme settings..."
link_file "$CONFIG_DIR/gtk/settings.ini" "$HOME/.config/gtk-3.0/settings.ini"
link_file "$CONFIG_DIR/gtk/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"

# ---------------------------------------------------------------------------
# Qt theming (qt5ct/qt6ct → Breeze style + dark palette for Dolphin, etc.)
# ---------------------------------------------------------------------------
info "Deploying qt5ct/qt6ct configs..."
link_file "$CONFIG_DIR/qt5ct/qt5ct.conf" "$HOME/.config/qt5ct/qt5ct.conf"
link_file "$CONFIG_DIR/qt6ct/qt6ct.conf" "$HOME/.config/qt6ct/qt6ct.conf"

# ---------------------------------------------------------------------------
# KDE Frameworks theming (kdeglobals — needed by KF5/KF6 apps like Dolphin)
# ---------------------------------------------------------------------------
info "Deploying KDE color scheme..."
link_file "$CONFIG_DIR/kde/kdeglobals" "$HOME/.config/kdeglobals"

# ---------------------------------------------------------------------------
# Bash prompt
# ---------------------------------------------------------------------------
info "Deploying bash prompt..."
link_file "$CONFIG_DIR/bash/prompt.sh" "$HOME/.config/shell/prompt.sh"

# Source from .bashrc if not already present
PROMPT_SOURCE_LINE="[[ -f \"\$HOME/.config/shell/prompt.sh\" ]] && source \"\$HOME/.config/shell/prompt.sh\""
grep -qF "prompt.sh" "$HOME/.bashrc" 2>/dev/null \
    || echo "$PROMPT_SOURCE_LINE" >> "$HOME/.bashrc"
ok "Bash prompt configured (takes effect in new shells)"

# ---------------------------------------------------------------------------
# Swaylock
# ---------------------------------------------------------------------------
info "Deploying swaylock config..."
mkdir -p "$HOME/.config/swaylock"
link_file "$CONFIG_DIR/swaylock/config" "$HOME/.config/swaylock/config"

# ---------------------------------------------------------------------------
# Dunst
# ---------------------------------------------------------------------------
info "Deploying dunst config..."
mkdir -p "$HOME/.config/dunst"
link_file "$CONFIG_DIR/dunst/dunstrc" "$HOME/.config/dunst/dunstrc"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================"
echo "  Dotfiles deployed!"
echo "  Log: $LOG"
echo "============================================"
echo ""
echo "Next steps:"
echo "  1. Reload sway config:   Super+Shift+C"
echo "  2. Or restart sway:      Super+Shift+E → restart"
echo "  3. Add kanshi profile for this machine if needed:"
echo "       swaymsg -t get_outputs"
echo "       # then edit: $CONFIG_DIR/kanshi/config"
echo "  4. Reload shell prompt:  source ~/.bashrc"
echo ""
