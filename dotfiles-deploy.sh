#!/bin/bash

# Dotfiles Deploy Script — Phase 2
# =================================
# Symlinks configs from this repo into ~/.config/.
# Safe to re-run: existing symlinks are updated, existing files are backed up.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

info() { echo -e "\n\033[1;34m→ $*\033[0m"; }
ok()   { echo -e "\033[1;32m✓ $*\033[0m"; }
warn() { echo -e "\033[1;33m⚠ $*\033[0m"; }

# ---------------------------------------------------------------------------
# Link a single file. Backs up existing non-symlink files, replaces symlinks.
# Usage: link_file <repo_path> <target_path>
# ---------------------------------------------------------------------------
link_file() {
    local src="$1"
    local dst="$2"

    mkdir -p "$(dirname "$dst")"

    if [[ -L "$dst" ]]; then
        rm "$dst"
    elif [[ -e "$dst" ]]; then
        warn "Backing up existing file: $dst → $dst.bak"
        mv "$dst" "$dst.bak"
    fi

    ln -s "$src" "$dst"
    ok "$dst → $src"
}

# ---------------------------------------------------------------------------
# Sway
# ---------------------------------------------------------------------------
info "Deploying sway config..."
link_file "$REPO_DIR/sway/config" "$HOME/.config/sway/config"

# ---------------------------------------------------------------------------
# Waybar
# ---------------------------------------------------------------------------
info "Deploying waybar config..."
link_file "$REPO_DIR/waybar/config"    "$HOME/.config/waybar/config"
link_file "$REPO_DIR/waybar/style.css" "$HOME/.config/waybar/style.css"
link_file "$REPO_DIR/waybar/scripts"   "$HOME/.config/waybar/scripts"
chmod +x "$REPO_DIR"/waybar/scripts/*.sh
ok "waybar scripts marked executable"

# ---------------------------------------------------------------------------
# Kanshi
# ---------------------------------------------------------------------------
info "Deploying kanshi config..."
link_file "$REPO_DIR/kanshi/config" "$HOME/.config/kanshi/config"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================"
echo "  Dotfiles deployed!"
echo "============================================"
echo ""
echo "Next steps:"
echo "  1. Reload sway config:   Super+Shift+C"
echo "  2. Or restart sway:      Super+Shift+E → restart"
echo "  3. Add kanshi profile for this machine if needed:"
echo "       swaymsg -t get_outputs"
echo "       # then edit: $REPO_DIR/kanshi/config"
echo ""
