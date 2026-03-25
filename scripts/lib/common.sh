#!/bin/bash
# lib/common.sh — Shared helpers for bootstrap.sh, theme.sh, dotfiles.sh, and apps.sh.
# Source this file; do not execute it directly.

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------

# shellcheck disable=SC2034  # variables used by sourcing scripts

info()  { echo -e "\n\033[1;34m→ $*\033[0m"; }
ok()    { echo -e "\033[1;32m✓ $*\033[0m"; }
warn()  { echo -e "\033[1;33m⚠ $*\033[0m"; }

# ---------------------------------------------------------------------------
# init_logging <script-name>
# Creates a restricted-permission log file and redirects stdout+stderr into it.
# Sets the global LOG variable for use in summary messages.
# ---------------------------------------------------------------------------
init_logging() {
    local name="${1:-script}"
    local log_dir="${XDG_RUNTIME_DIR:-/tmp}"
    umask 077
    LOG=$(mktemp "${log_dir}/${name}-XXXXXX.log")
    exec > >(tee -a "$LOG") 2>&1
}

# ---------------------------------------------------------------------------
# preflight_checks
# Ensures the script runs as a regular user on Fedora.
# ---------------------------------------------------------------------------
preflight_checks() {
    if [[ $EUID -eq 0 ]]; then
        echo "ERROR: Run as a regular user, not root. The script uses sudo internally." >&2
        exit 1
    fi
    if ! grep -q '^ID=fedora$' /etc/os-release 2>/dev/null; then
        echo "ERROR: This script targets Fedora. Detected OS is not Fedora." >&2
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# require_cmd <cmd> [<install-hint>]
# Exits with a clear message if <cmd> is not on PATH.
# ---------------------------------------------------------------------------
require_cmd() {
    local cmd="$1"
    local hint="${2:-}"
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: Required command '${cmd}' not found.${hint:+ Install with: ${hint}}" >&2
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Package manifest paths — used by pkg_install and audit.sh
# ---------------------------------------------------------------------------
PKG_MANIFEST="$HOME/.config/shell/.pkg-manifest"
FLATPAK_MANIFEST="$HOME/.config/shell/.flatpak-manifest"

# ---------------------------------------------------------------------------
# pkg_install <pkg>...
# Installs RPM packages via dnf and records them in the package manifest.
# ---------------------------------------------------------------------------
pkg_install() {
    sudo dnf install -y "$@"
    mkdir -p "$(dirname "$PKG_MANIFEST")"
    local pkg
    for pkg in "$@"; do
        [[ "$pkg" == -* || "$pkg" == */* ]] && continue
        grep -qFx "$pkg" "$PKG_MANIFEST" 2>/dev/null || echo "$pkg" >> "$PKG_MANIFEST"
    done
}

# ---------------------------------------------------------------------------
# ensure_bashrc_source
# Sources a dedicated env file from .bashrc, idempotently.
# ---------------------------------------------------------------------------
ensure_bashrc_source() {
    mkdir -p "$HOME/.config/shell"
    # Use single-quoted heredoc-style string so $HOME is evaluated at shell
    # startup time, not baked in at install time (matches prompt.sh pattern).
    local source_line='[[ -f "$HOME/.config/shell/bootstrap-env.sh" ]] && source "$HOME/.config/shell/bootstrap-env.sh"'
    grep -qF "bootstrap-env.sh" "$HOME/.bashrc" 2>/dev/null || \
        echo "$source_line" >> "$HOME/.bashrc"
}

# ---------------------------------------------------------------------------
# find_fedora_version <url_template> [max_fallback]
# Probes a URL pattern to find the newest Fedora version that exists.
# Template uses {ver} as the version placeholder.
# Echoes the first working version; returns 1 if none found.
# ---------------------------------------------------------------------------
find_fedora_version() {
    local template="$1"
    local max="${2:-3}"
    local cur
    cur=$(rpm -E %fedora)
    for (( v=cur; v > cur - max; v-- )); do
        if curl -sf --head --connect-timeout 5 "${template//\{ver\}/$v}" -o /dev/null; then
            echo "$v"
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------------------
# Accent color presets
# ---------------------------------------------------------------------------
# Each preset: PRIMARY DIM DARK BRIGHT SECONDARY ANSI_CODE
# PRIMARY  — focused borders, login button, clock, cursor
# DIM      — sway focused_inactive borders
# DARK     — sway unfocused borders
# BRIGHT   — sway placeholder borders
# SECONDARY — bemenu text, power icons
# ANSI_CODE — terminal escape for bash prompt hostname color

declare -A COLOR_PRESETS
COLOR_PRESETS[green]="#88DD00 #557700 #2A3B00 #8BE235 #ffaa00 92"
COLOR_PRESETS[orange]="#ff8800 #995200 #4d2900 #ffcc44 #88DD00 33"
COLOR_PRESETS[blue]="#4488ff #2a5599 #152a4d #88bbff #ffaa00 34"

# ---------------------------------------------------------------------------
# load_accent
# Reads ACCENT from scripts/env (if present) or falls back to env-sample.
# Populates ACCENT_PRIMARY, ACCENT_DIM, ACCENT_DARK, ACCENT_BRIGHT,
# ACCENT_SECONDARY, ACCENT_ANSI.
# ---------------------------------------------------------------------------
load_accent() {
    # Only source env files if ACCENT is not already set (avoids redundant I/O
    # when the calling script already sourced env at startup).
    if [[ -z "${ACCENT:-}" ]]; then
        local _scripts_dir
        _scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
        if [[ -f "$_scripts_dir/env" ]]; then
            # shellcheck source=scripts/env
            source "$_scripts_dir/env"
        elif [[ -f "$_scripts_dir/env-sample" ]]; then
            # shellcheck source=scripts/env-sample
            source "$_scripts_dir/env-sample"
        fi
    fi
    local accent="${ACCENT:-green}"

    if [[ -z "${COLOR_PRESETS[$accent]+x}" ]]; then
        warn "Unknown accent '$accent', falling back to green"
        accent="green"
    fi

    read -r ACCENT_PRIMARY ACCENT_DIM ACCENT_DARK ACCENT_BRIGHT ACCENT_SECONDARY ACCENT_ANSI \
        <<< "${COLOR_PRESETS[$accent]}"
    ACCENT_NAME="$accent"
}

# ---------------------------------------------------------------------------
# apply_accent <file>
# Replaces any known preset's colors with the currently loaded accent.
# Handles both #RRGGBB (most configs) and bare RRGGBB (swaylock) formats.
# ---------------------------------------------------------------------------
apply_accent() {
    local file="$1"
    [[ -f "$file" ]] || return 0

    for preset in "${!COLOR_PRESETS[@]}"; do
        read -r p d dk br s _ansi <<< "${COLOR_PRESETS[$preset]}"
        # Skip if this IS the target preset (no-op replacement)
        [[ "$preset" == "$ACCENT_NAME" ]] && continue

        # Replace with hash prefix (#RRGGBB)
        sed -i "s/${p}/${ACCENT_PRIMARY}/gi"     "$file"
        sed -i "s/${d}/${ACCENT_DIM}/gi"         "$file"
        sed -i "s/${dk}/${ACCENT_DARK}/gi"       "$file"
        sed -i "s/${br}/${ACCENT_BRIGHT}/gi"     "$file"
        sed -i "s/${s}/${ACCENT_SECONDARY}/gi"   "$file"

        # Replace bare hex (no hash) for swaylock-style configs
        local p_bare="${p#\#}" d_bare="${d#\#}" dk_bare="${dk#\#}" br_bare="${br#\#}"
        local tp_bare="${ACCENT_PRIMARY#\#}" td_bare="${ACCENT_DIM#\#}" tdk_bare="${ACCENT_DARK#\#}" tbr_bare="${ACCENT_BRIGHT#\#}"
        # Only replace bare hex at line start (swaylock format: key=RRGGBB)
        sed -i "s/=${p_bare}$/=${tp_bare}/gi"    "$file"
        sed -i "s/=${d_bare}$/=${td_bare}/gi"    "$file"
        sed -i "s/=${dk_bare}$/=${tdk_bare}/gi"  "$file"
        sed -i "s/=${br_bare}$/=${tbr_bare}/gi"  "$file"

        # Replace icon theme name (Tela-green → Tela-orange, etc.)
        sed -i "s/Tela-${preset}/Tela-${ACCENT_NAME}/g" "$file"
    done
}
