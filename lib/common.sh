# lib/common.sh — Core utility library, sourced by all modules.
# Source this file; do not execute it directly.
#
# Color/accent functions live in lib/colors.sh.
# Symlink/deploy functions live in lib/links.sh.

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
