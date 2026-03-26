# modules/dotfiles.sh — Dotfile symlink deployment module.
# Source this file; do not execute it directly.
#
# Handles: symlink creation from config/ → ~/.config/, local override files,
#          .bashrc source lines, waybar script permissions.
#
# Assumes lib/common.sh, lib/config.sh, lib/links.sh are sourced.
# REPO_ROOT is set. link_file(), ensure_local_override(), check_link() available.

# ---------------------------------------------------------------------------
# Declarative symlink map
# Format: "source_relative|target_absolute|condition"
# Conditions: "always", "sway", "fish"
# ---------------------------------------------------------------------------

_SYMLINK_MAP=(
    # Sway/Wayland (conditional)
    "sway/config|$HOME/.config/sway/config|sway"
    "waybar/config|$HOME/.config/waybar/config|sway"
    "waybar/style.css|$HOME/.config/waybar/style.css|sway"
    "waybar/scripts|$HOME/.config/waybar/scripts|sway"
    "kanshi/config|$HOME/.config/kanshi/config|sway"
    "swaylock/config|$HOME/.config/swaylock/config|sway"

    # GTK (single source → dual targets)
    "gtk/settings.ini|$HOME/.config/gtk-3.0/settings.ini|always"
    "gtk/settings.ini|$HOME/.config/gtk-4.0/settings.ini|always"

    # Qt
    "qt5ct/qt5ct.conf|$HOME/.config/qt5ct/qt5ct.conf|always"
    "qt6ct/qt6ct.conf|$HOME/.config/qt6ct/qt6ct.conf|always"

    # KDE
    "kde/kdeglobals|$HOME/.config/kdeglobals|always"

    # Shell
    "bash/prompt.sh|$HOME/.config/shell/prompt.sh|always"
    "bash/completions.sh|$HOME/.config/shell/completions.sh|always"

    # Fish (conditional)
    "fish/config.fish|$HOME/.config/fish/config.fish|fish"
    "fish/conf.d/01-environment.fish|$HOME/.config/fish/conf.d/01-environment.fish|fish"
    "fish/conf.d/02-colors.fish|$HOME/.config/fish/conf.d/02-colors.fish|fish"
    "fish/conf.d/03-abbreviations.fish|$HOME/.config/fish/conf.d/03-abbreviations.fish|fish"
    "fish/conf.d/04-keybinds.fish|$HOME/.config/fish/conf.d/04-keybinds.fish|fish"
    "fish/functions/fish_prompt.fish|$HOME/.config/fish/functions/fish_prompt.fish|fish"
    "fish/functions/fish_right_prompt.fish|$HOME/.config/fish/functions/fish_right_prompt.fish|fish"
    "fish/functions/fish_greeting.fish|$HOME/.config/fish/functions/fish_greeting.fish|fish"
    "fish/functions/fish_mode_prompt.fish|$HOME/.config/fish/functions/fish_mode_prompt.fish|fish"
    "fish/functions/md.fish|$HOME/.config/fish/functions/md.fish|fish"

    # Apps
    "dunst/dunstrc|$HOME/.config/dunst/dunstrc|always"
    "kitty/kitty.conf|$HOME/.config/kitty/kitty.conf|always"
    "tmux/tmux.conf|$HOME/.config/tmux/tmux.conf|always"
)

# Local override files (created once, never overwritten)
# Format: "target|comment_char|condition"
_LOCAL_OVERRIDES=(
    "$HOME/.config/sway/config.local|#|sway"
    "$HOME/.config/fish/config.local.fish|#|fish"
    "$HOME/.config/dunst/dunstrc.local|#|always"
    "$HOME/.config/kitty/config.local|#|always"
    "$HOME/.config/tmux/local.conf|#|always"
)

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

_condition_met() {
    case "$1" in
        always) return 0 ;;
        sway)   command -v sway &>/dev/null ;;
        fish)   command -v fish &>/dev/null ;;
        *)      return 1 ;;
    esac
}

_ensure_bashrc_line() {
    local marker="$1" line="$2"
    grep -qF "$marker" "$HOME/.bashrc" 2>/dev/null || echo "$line" >> "$HOME/.bashrc"
}

# ---------------------------------------------------------------------------
# Module contract
# ---------------------------------------------------------------------------

dotfiles::check() {
    local config_dir="$REPO_ROOT/config"
    local entry
    for entry in "${_SYMLINK_MAP[@]}"; do
        IFS='|' read -r rel dst cond <<< "$entry"
        _condition_met "$cond" || continue
        local src="$config_dir/$rel"
        local status
        status=$(check_link "$src" "$dst")
        [[ "$status" != "ok" ]] && return 0
    done
    return 1
}

dotfiles::preview() {
    info "[dotfiles] Preview:"
    local config_dir="$REPO_ROOT/config"
    local entry
    for entry in "${_SYMLINK_MAP[@]}"; do
        IFS='|' read -r rel dst cond <<< "$entry"
        _condition_met "$cond" || continue
        local src="$config_dir/$rel"
        local status
        status=$(check_link "$src" "$dst")
        local tag
        case "$status" in
            ok)          tag="[OK]" ;;
            missing)     tag="[WILL CREATE]" ;;
            wrong)       tag="[WILL RELINK]" ;;
            blocked)     tag="[WILL BACKUP + LINK]" ;;
            src_missing) tag="[SOURCE MISSING]" ;;
        esac
        printf "  %-45s → %-45s %s\n" "config/$rel" "$dst" "$tag"
    done
}

dotfiles::apply() {
    local config_dir="$REPO_ROOT/config"

    # Deploy symlinks
    local entry
    for entry in "${_SYMLINK_MAP[@]}"; do
        IFS='|' read -r rel dst cond <<< "$entry"
        _condition_met "$cond" || continue
        link_file "$config_dir/$rel" "$dst"
    done

    # Create local overrides
    for entry in "${_LOCAL_OVERRIDES[@]}"; do
        IFS='|' read -r dst comment cond <<< "$entry"
        _condition_met "$cond" || continue
        ensure_local_override "$dst" "$comment"
    done

    # .bashrc source lines (idempotent)
    _ensure_bashrc_line "prompt.sh" \
        '[[ -f "$HOME/.config/shell/prompt.sh" ]] && source "$HOME/.config/shell/prompt.sh"'
    _ensure_bashrc_line "completions.sh" \
        '[[ -f "$HOME/.config/shell/completions.sh" ]] && source "$HOME/.config/shell/completions.sh"'

    # Make waybar scripts executable
    if _condition_met "sway" && compgen -G "$config_dir/waybar/scripts/*.sh" >/dev/null 2>&1; then
        chmod +x "$config_dir"/waybar/scripts/*.sh
        ok "waybar scripts marked executable"
    fi

    ok "Dotfiles deployed"
}

dotfiles::status() {
    local config_dir="$REPO_ROOT/config"
    local total=0 linked=0
    local entry
    for entry in "${_SYMLINK_MAP[@]}"; do
        IFS='|' read -r rel dst cond <<< "$entry"
        _condition_met "$cond" || continue
        total=$((total + 1))
        [[ "$(check_link "$config_dir/$rel" "$dst")" == "ok" ]] && linked=$((linked + 1))
    done
    echo "dotfiles: ${linked}/${total} symlinks active"
}
