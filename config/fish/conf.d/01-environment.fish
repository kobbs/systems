# Environment variables — fish equivalent of bootstrap-env.sh
# Managed by scripts/dotfiles.sh

status is-interactive; or return

# Qt/KDE dark theme integration
set -gx QT_QPA_PLATFORMTHEME kde
set -gx QT_STYLE_OVERRIDE Breeze

# Podman as Docker replacement
abbr -a docker podman
set -gx KIND_EXPERIMENTAL_PROVIDER podman

# Fix broken SSH askpass (kde-settings sets SSH_ASKPASS to missing ksshaskpass)
set -e SSH_ASKPASS

# XDG defaults
set -q XDG_CONFIG_HOME; or set -gx XDG_CONFIG_HOME $HOME/.config
set -q XDG_DATA_HOME; or set -gx XDG_DATA_HOME $HOME/.local/share
set -q XDG_CACHE_HOME; or set -gx XDG_CACHE_HOME $HOME/.cache

# Editor preference (override in config.local.fish)
set -q EDITOR; or set -gx EDITOR vim

# Clean PATH additions (fish_add_path is idempotent — no duplicates)
fish_add_path ~/.local/bin
