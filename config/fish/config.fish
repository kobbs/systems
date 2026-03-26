# Fish shell configuration
# Managed by scripts/dotfiles.sh — edit config files in this directory tree.
# Local overrides: ~/.config/fish/config.local.fish (not tracked by git)

# Guard: only run in interactive sessions
status is-interactive; or return

# Source local overrides (per-machine customizations, not tracked by git)
set -l _local_conf ~/.config/fish/config.local.fish
test -f $_local_conf; and source $_local_conf
