#!/bin/bash

# Dotfiles Deploy Script — Phase 2
# =================================
# Symlinks configs from this repo into ~/.config/.
# Safe to re-run: already-correct symlinks are skipped, existing files are
# backed up with a .bak suffix.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=lib/common.sh
source "${REPO_DIR}/lib/common.sh"

init_logging "dotfiles-deploy"

# ---------------------------------------------------------------------------
# Link a single file. Skips if already linked correctly. Backs up existing
# non-symlink files. Replaces incorrect symlinks.
# Usage: link_file <repo_path> <target_path>
# ---------------------------------------------------------------------------
link_file() {
    local src="$1"
    local dst="$2"

    mkdir -p "$(dirname "$dst")"

    # Already points to the correct target — nothing to do.
    if [[ "$(readlink "$dst" 2>/dev/null)" == "$src" ]]; then
        ok "$dst already linked (skipped)"
        return 0
    fi

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
# Bash prompt
# ---------------------------------------------------------------------------
info "Deploying bash prompt..."
link_file "$REPO_DIR/bash/prompt.sh" "$HOME/.config/shell/prompt.sh"

# Source from .bashrc if not already present
PROMPT_SOURCE_LINE="[[ -f \"\$HOME/.config/shell/prompt.sh\" ]] && source \"\$HOME/.config/shell/prompt.sh\""
grep -qF "prompt.sh" "$HOME/.bashrc" 2>/dev/null \
    || echo "$PROMPT_SOURCE_LINE" >> "$HOME/.bashrc"
ok "Bash prompt configured (takes effect in new shells)"

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
echo "       # then edit: $REPO_DIR/kanshi/config"
echo "  4. Reload shell prompt:  source ~/.bashrc"
echo ""
