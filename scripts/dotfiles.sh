#!/bin/bash

# Dotfiles Deploy Script
# ======================
# Symlinks configs from this repo into ~/.config/.
# Installs the Tela icon theme (user-local).
# Safe to re-run: already-correct symlinks are skipped, existing files are
# backed up with a .bak suffix.

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
Usage: $(basename "$0") start

Deploy dotfiles — symlink configs from this repo into ~/.config/.
Installs the Tela icon theme (user-local).
Safe to re-run: already-correct symlinks are skipped, existing files are
backed up with a .bak suffix.

Sway/Waybar/Kanshi/Swaylock configs are only deployed if sway is installed.

Options:
  -h, --help    Show this help message and exit
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
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
# Create a local override file if it doesn't already exist.
# These are per-machine customizations that are NOT tracked by git.
# Usage: ensure_local_override <target_path> <comment_char>
# ---------------------------------------------------------------------------
ensure_local_override() {
    local dst="$1"
    local comment="${2:-#}"

    if [[ -e "$dst" ]]; then
        ok "Local override exists (kept): $dst"
        return 0
    fi

    mkdir -p "$(dirname "$dst")"
    cat > "$dst" <<EOF
${comment} Local overrides for this machine (not tracked by git).
${comment} Settings here take precedence over the base config.
EOF
    ok "Created local override: $dst"
}

# Detect sway availability for conditional sections
_HAS_SWAY=false
if command -v sway &>/dev/null; then
    _HAS_SWAY=true
fi

# ---------------------------------------------------------------------------
# Sway / Waybar / Kanshi / Swaylock (only if sway is installed)
# ---------------------------------------------------------------------------

if [[ "$_HAS_SWAY" == true ]]; then
    info "Deploying sway config..."
    link_file "$CONFIG_DIR/sway/config" "$HOME/.config/sway/config"
    ensure_local_override "$HOME/.config/sway/config.local" "#"

    info "Deploying waybar config..."
    link_file "$CONFIG_DIR/waybar/config"    "$HOME/.config/waybar/config"
    link_file "$CONFIG_DIR/waybar/style.css" "$HOME/.config/waybar/style.css"
    link_file "$CONFIG_DIR/waybar/scripts"   "$HOME/.config/waybar/scripts"
    if compgen -G "$CONFIG_DIR/waybar/scripts/*.sh" >/dev/null 2>&1; then
        chmod +x "$CONFIG_DIR"/waybar/scripts/*.sh
        ok "waybar scripts marked executable"
    fi

    info "Deploying kanshi config..."
    link_file "$CONFIG_DIR/kanshi/config" "$HOME/.config/kanshi/config"

    info "Deploying swaylock config..."
    mkdir -p "$HOME/.config/swaylock"
    link_file "$CONFIG_DIR/swaylock/config" "$HOME/.config/swaylock/config"
else
    info "Sway not installed — skipping Sway/Waybar/Kanshi/Swaylock configs"
fi

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
# Bash completions
# ---------------------------------------------------------------------------
info "Deploying bash completions..."
link_file "$CONFIG_DIR/bash/completions.sh" "$HOME/.config/shell/completions.sh"

COMPLETIONS_SOURCE_LINE="[[ -f \"\$HOME/.config/shell/completions.sh\" ]] && source \"\$HOME/.config/shell/completions.sh\""
grep -qF "completions.sh" "$HOME/.bashrc" 2>/dev/null \
    || echo "$COMPLETIONS_SOURCE_LINE" >> "$HOME/.bashrc"
ok "Bash completions configured (takes effect in new shells)"

# ---------------------------------------------------------------------------
# Fish shell (optional interactive shell)
# ---------------------------------------------------------------------------
if command -v fish &>/dev/null; then
    info "Deploying fish config..."
    mkdir -p "$HOME/.config/fish/conf.d" "$HOME/.config/fish/functions"
    link_file "$CONFIG_DIR/fish/config.fish"                      "$HOME/.config/fish/config.fish"
    link_file "$CONFIG_DIR/fish/conf.d/01-environment.fish"       "$HOME/.config/fish/conf.d/01-environment.fish"
    link_file "$CONFIG_DIR/fish/conf.d/02-colors.fish"            "$HOME/.config/fish/conf.d/02-colors.fish"
    link_file "$CONFIG_DIR/fish/conf.d/03-abbreviations.fish"     "$HOME/.config/fish/conf.d/03-abbreviations.fish"
    link_file "$CONFIG_DIR/fish/conf.d/04-keybinds.fish"          "$HOME/.config/fish/conf.d/04-keybinds.fish"
    link_file "$CONFIG_DIR/fish/functions/fish_prompt.fish"        "$HOME/.config/fish/functions/fish_prompt.fish"
    link_file "$CONFIG_DIR/fish/functions/fish_right_prompt.fish"  "$HOME/.config/fish/functions/fish_right_prompt.fish"
    link_file "$CONFIG_DIR/fish/functions/fish_greeting.fish"      "$HOME/.config/fish/functions/fish_greeting.fish"
    link_file "$CONFIG_DIR/fish/functions/fish_mode_prompt.fish"   "$HOME/.config/fish/functions/fish_mode_prompt.fish"
    link_file "$CONFIG_DIR/fish/functions/md.fish"                "$HOME/.config/fish/functions/md.fish"
    ensure_local_override "$HOME/.config/fish/config.local.fish" "#"
    ok "Fish config deployed"
else
    info "Fish not installed — skipping fish config"
fi

# ---------------------------------------------------------------------------
# Dunst
# ---------------------------------------------------------------------------
info "Deploying dunst config..."
mkdir -p "$HOME/.config/dunst"
link_file "$CONFIG_DIR/dunst/dunstrc" "$HOME/.config/dunst/dunstrc"
ensure_local_override "$HOME/.config/dunst/dunstrc.local" "#"

# ---------------------------------------------------------------------------
# Kitty
# ---------------------------------------------------------------------------
info "Deploying kitty config..."
link_file "$CONFIG_DIR/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf"
ensure_local_override "$HOME/.config/kitty/config.local" "#"

# ---------------------------------------------------------------------------
# Tmux
# ---------------------------------------------------------------------------
info "Deploying tmux config..."
link_file "$CONFIG_DIR/tmux/tmux.conf" "$HOME/.config/tmux/tmux.conf"
ensure_local_override "$HOME/.config/tmux/local.conf" "#"

# ---------------------------------------------------------------------------
# Icon theme (Tela, user-local — color follows ACCENT)
# ---------------------------------------------------------------------------
# Installed to ~/.local/share/icons so no sudo is needed.
# GTK and KDE apps find it via the standard XDG icon search path.

load_accent
require_cmd git "sudo dnf install -y git"

_tela_dir="$HOME/.local/share/icons/Tela-${ACCENT_NAME}"
_need_install=false

if [[ ! -d "$_tela_dir" ]]; then
    _need_install=true
elif [[ -f "$_tela_dir/scalable/places/default-folder.svg" ]]; then
    # Verify the installed theme actually has the right accent color.
    # The Tela installer replaces #5294e2 (default blue) with the accent color.
    # If the folder SVG still contains the default blue, the install was wrong.
    if [[ "$ACCENT_NAME" != "standard" ]] \
        && grep -qi '#5294e2' "$_tela_dir/scalable/places/default-folder.svg"; then
        warn "Tela-${ACCENT_NAME} contains default blue icons — reinstalling..."
        rm -rf "$_tela_dir" "${_tela_dir}-dark" "${_tela_dir}-light"
        _need_install=true
    fi
else
    # Directory exists but is missing expected files — corrupt install
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
# Apply accent color
# ---------------------------------------------------------------------------
info "Applying accent color: $ACCENT_NAME (${ACCENT_PRIMARY})..."

_accent_files=(
    "$CONFIG_DIR/kitty/kitty.conf"
    "$CONFIG_DIR/tmux/tmux.conf"
    "$CONFIG_DIR/dunst/dunstrc"
    "$CONFIG_DIR/sddm/theme.conf"
    "$CONFIG_DIR/gtk/settings.ini"
    "$CONFIG_DIR/kde/kdeglobals"   # hex colors won't match (RGB triplets), but Tela-<preset> will
    "$CONFIG_DIR/fish/conf.d/02-colors.fish"
)

if [[ "$_HAS_SWAY" == true ]]; then
    _accent_files+=(
        "$CONFIG_DIR/sway/config"
        "$CONFIG_DIR/waybar/style.css"
        "$CONFIG_DIR/swaylock/config"
    )
fi

for _af in "${_accent_files[@]}"; do
    apply_accent "$_af"
done

# bash/prompt.sh uses ANSI escape codes — replace hostname color
# Targets the _GREEN variable line: _GREEN="$(_pc NN)"  → swap the ANSI code
_prompt_file="$CONFIG_DIR/bash/prompt.sh"
if [[ -f "$_prompt_file" ]]; then
    sed -i "s/^\(_GREEN=\"\$(_pc \)[0-9]*/\1${ACCENT_ANSI}/" "$_prompt_file"
fi

ok "Accent color applied"

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
if [[ "$_HAS_SWAY" == true ]]; then
    echo "  1. Reload sway config:   Super+Shift+C"
    echo "  2. Or restart sway:      Super+Shift+E → restart"
    echo "  3. Add kanshi profile for this machine if needed:"
    echo "       swaymsg -t get_outputs"
    echo "       # then edit: $CONFIG_DIR/kanshi/config"
fi
echo "  4. Reload shell prompt:  source ~/.bashrc"
echo "  5. Launch fish:          fish   (optional — not the default shell)"
echo "  6. Re-apply SDDM theme: bash scripts/theme-sddm.sh start"
echo ""
