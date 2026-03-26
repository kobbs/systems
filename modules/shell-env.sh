# modules/shell-env.sh — Shell environment module.
# Source this file; do not execute it directly.
#
# Handles: ~/.config/shell/bootstrap-env.sh generation and .bashrc sourcing.
#
# Assumes lib/common.sh is sourced (ensure_bashrc_source available).

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

_generate_env_content() {
    cat <<'EOF'
# Managed by ./setup shell-env
# Do not edit manually; changes will be overwritten.

alias docker=podman
export KIND_EXPERIMENTAL_PROVIDER=podman
export QT_QPA_PLATFORMTHEME=kde
export QT_STYLE_OVERRIDE=Breeze

# kde-settings ships /etc/profile.d/kde-openssh-askpass.sh which sets
# SSH_ASKPASS=/usr/bin/ksshaskpass, but ksshaskpass is not installed.
# This breaks git HTTPS credential prompts. Unset unconditionally.
unset SSH_ASKPASS
EOF
}

# ---------------------------------------------------------------------------
# Module contract
# ---------------------------------------------------------------------------

shell-env::check() {
    local env_file="$HOME/.config/shell/bootstrap-env.sh"

    # Check if env file content matches
    if [[ -f "$env_file" ]]; then
        local target
        target="$(_generate_env_content)"
        local current
        current="$(cat "$env_file")"
        if [[ "$target" != "$current" ]]; then
            return 0
        fi
    else
        return 0
    fi

    # Check .bashrc source line
    if ! grep -qF "bootstrap-env.sh" "$HOME/.bashrc" 2>/dev/null; then
        return 0
    fi

    return 1
}

shell-env::preview() {
    info "[shell-env] Preview:"
    local env_file="$HOME/.config/shell/bootstrap-env.sh"

    if [[ -f "$env_file" ]]; then
        local tmp
        tmp=$(mktemp)
        _generate_env_content > "$tmp"
        if ! cmp -s "$tmp" "$env_file"; then
            echo "  Changes to bootstrap-env.sh:"
            diff "$env_file" "$tmp" | sed 's/^/    /' || true
        else
            echo "  bootstrap-env.sh: up to date  [OK]"
        fi
        rm -f "$tmp"
    else
        echo "  Will create: ~/.config/shell/bootstrap-env.sh"
        _generate_env_content | sed 's/^/    /'
    fi

    if ! grep -qF "bootstrap-env.sh" "$HOME/.bashrc" 2>/dev/null; then
        echo "  Will add source line to .bashrc  [CHANGE]"
    else
        echo "  .bashrc source line: present  [OK]"
    fi
}

shell-env::apply() {
    local env_file="$HOME/.config/shell/bootstrap-env.sh"

    # Write env file atomically via temp file
    local tmp
    tmp=$(mktemp)
    _generate_env_content > "$tmp"

    mkdir -p "$HOME/.config/shell"

    if ! cmp -s "$tmp" "$env_file" 2>/dev/null; then
        mv "$tmp" "$env_file"
        ok "Shell env configured"
    else
        rm -f "$tmp"
        ok "Shell env already up to date"
    fi

    # Ensure .bashrc sources it
    ensure_bashrc_source

    ok "Shell environment ready"
}

shell-env::status() {
    local env_file="$HOME/.config/shell/bootstrap-env.sh"
    if [[ -f "$env_file" ]]; then
        local count
        count=$(grep -c '^export\|^alias\|^unset' "$env_file" 2>/dev/null || echo 0)
        echo "shell-env: deployed, ${count} directives"
    else
        echo "shell-env: NOT deployed"
    fi
}
