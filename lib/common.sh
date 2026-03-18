#!/bin/bash
# lib/common.sh — Shared helpers for fedora-bootstrap.sh, apps-install.sh,
#                 and dotfiles-deploy.sh.
# Source this file; do not execute it directly.

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------

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
    umask 077
    LOG=$(mktemp "/tmp/${name}-XXXXXX.log")
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
