# modules/system.sh — System configuration module.
# Source this file; do not execute it directly.
#
# Handles: hostname, keyboard layout, GPU group membership,
#          firewall, bluetooth + tuned services, Sway Spin mode detection.
#
# Assumes lib/common.sh and lib/config.sh are already sourced,
# and REPO_ROOT / PROFILE_* vars are set.

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# _detect_gpu
# Sets _HAS_DISCRETE_AMD_GPU=true if a discrete AMD Navi/RDNA GPU is found.
_detect_gpu() {
    _HAS_DISCRETE_AMD_GPU=false
    if lspci 2>/dev/null | grep -qi 'VGA.*AMD.*Navi\|VGA.*AMD.*RDNA'; then
        _HAS_DISCRETE_AMD_GPU=true
    fi
}

# _detect_mode [args...]
# Determines Sway Spin mode from flags, persisted state, or auto-detection.
# Sets SWAY_SPIN=true|false and persists the result to the mode file.
#
# Priority:
#   1. --sway-spin / --kde-spin flag
#   2. Persisted mode file (validated)
#   3. Auto-detect via rpm -q sway
_detect_mode() {
    local _force_mode=""
    local arg
    for arg in "$@"; do
        case "$arg" in
            --sway-spin) _force_mode="sway-spin" ;;
            --kde-spin)  _force_mode="kde-spin" ;;
        esac
    done

    _MODE_FILE="$HOME/.config/shell/.bootstrap-mode"
    SWAY_SPIN=false

    if [[ "$_force_mode" == "sway-spin" ]]; then
        SWAY_SPIN=true
    elif [[ "$_force_mode" == "kde-spin" ]]; then
        SWAY_SPIN=false
    elif [[ -f "$_MODE_FILE" ]] && grep -qxE 'true|false' "$_MODE_FILE"; then
        SWAY_SPIN=$(cat "$_MODE_FILE")
    elif rpm -q sway &>/dev/null; then
        SWAY_SPIN=true
    fi

    # Always persist
    mkdir -p "$(dirname "$_MODE_FILE")"
    echo "$SWAY_SPIN" > "$_MODE_FILE"
}

# ---------------------------------------------------------------------------
# Module contract
# ---------------------------------------------------------------------------

# system::check [args...]
# Returns 0 if changes are needed, 1 if everything is up-to-date.
system::check() {
    _detect_gpu
    _detect_mode "$@"

    local needs_change=false

    # Hostname
    local target_hostname
    target_hostname="$(profile_get system hostname)"
    if [[ -n "$target_hostname" && "$(hostname -s)" != "$target_hostname" ]]; then
        needs_change=true
    fi

    # Keyboard layout
    local target_layout
    target_layout="$(profile_get system keyboard_layout)"
    if [[ -n "$target_layout" ]]; then
        local current_layout
        current_layout="$(localectl status 2>/dev/null \
            | sed -n 's/.*X11 Layout: *//p')"
        if [[ "$current_layout" != "$target_layout" ]]; then
            needs_change=true
        fi
    fi

    # GPU groups
    if [[ "$_HAS_DISCRETE_AMD_GPU" == true ]]; then
        local current_groups
        current_groups="$(id -Gn)"
        if ! echo "$current_groups" | grep -qw video || \
           ! echo "$current_groups" | grep -qw render; then
            needs_change=true
        fi
    fi

    # Firewalld
    if ! systemctl is-active --quiet firewalld 2>/dev/null; then
        needs_change=true
    fi

    # Bluetooth
    if ! systemctl is-enabled --quiet bluetooth 2>/dev/null; then
        needs_change=true
    fi

    # Tuned
    if ! systemctl is-enabled --quiet tuned 2>/dev/null; then
        needs_change=true
    fi

    if [[ "$needs_change" == true ]]; then
        return 0
    fi
    return 1
}

# system::preview [args...]
# Prints what would change without making modifications.
system::preview() {
    _detect_gpu
    _detect_mode "$@"

    # Hostname
    local target_hostname current_hostname
    target_hostname="$(profile_get system hostname)"
    current_hostname="$(hostname -s)"
    if [[ -n "$target_hostname" && "$current_hostname" != "$target_hostname" ]]; then
        echo "  Hostname: ${current_hostname} → ${target_hostname}  [CHANGE]"
    else
        echo "  Hostname: ${current_hostname}  [OK]"
    fi

    # Keyboard layout
    local target_layout current_layout
    target_layout="$(profile_get system keyboard_layout)"
    current_layout="$(localectl status 2>/dev/null \
        | sed -n 's/.*X11 Layout: *//p')"
    if [[ -n "$target_layout" && "$current_layout" != "$target_layout" ]]; then
        echo "  Keyboard: ${current_layout:-unset} → ${target_layout}  [CHANGE]"
    else
        echo "  Keyboard: ${current_layout:-unset}  [OK]"
    fi

    # GPU groups
    if [[ "$_HAS_DISCRETE_AMD_GPU" == true ]]; then
        local current_groups missing=()
        current_groups="$(id -Gn)"
        echo "$current_groups" | grep -qw video  || missing+=(video)
        echo "$current_groups" | grep -qw render || missing+=(render)
        if [[ ${#missing[@]} -gt 0 ]]; then
            echo "  GPU groups: add ${missing[*]}  [CHANGE]"
        else
            echo "  GPU groups: video,render  [OK]"
        fi
    else
        echo "  GPU groups: no discrete AMD GPU  [SKIP]"
    fi

    # Firewalld
    if ! systemctl is-active --quiet firewalld 2>/dev/null; then
        echo "  Firewall: inactive → enable firewalld  [CHANGE]"
    else
        local zone
        zone="$(sudo firewall-cmd --get-default-zone 2>/dev/null || echo "unknown")"
        echo "  Firewall: active (zone: ${zone})  [OK]"
    fi

    # Bluetooth
    if ! systemctl is-enabled --quiet bluetooth 2>/dev/null; then
        echo "  Bluetooth: disabled → enable  [CHANGE]"
    else
        echo "  Bluetooth: enabled  [OK]"
    fi

    # Tuned
    if ! systemctl is-enabled --quiet tuned 2>/dev/null; then
        echo "  Tuned: disabled → enable  [CHANGE]"
    else
        echo "  Tuned: enabled  [OK]"
    fi

    # Mode
    echo "  Sway Spin mode: ${SWAY_SPIN}"
}

# system::apply [args...]
# Applies system configuration changes.
system::apply() {
    _detect_gpu
    _detect_mode "$@"

    # Hostname
    local target_hostname
    target_hostname="$(profile_get system hostname)"
    if [[ -n "$target_hostname" ]]; then
        if [[ "$(hostname -s)" != "$target_hostname" ]]; then
            sudo hostnamectl set-hostname "$target_hostname"
            ok "Hostname set to ${target_hostname}"
        else
            ok "Hostname already set to ${target_hostname}"
        fi
    fi

    # Keyboard layout
    local target_layout
    target_layout="$(profile_get system keyboard_layout)"
    if [[ -n "$target_layout" ]]; then
        local current_layout
        current_layout="$(localectl status 2>/dev/null \
            | sed -n 's/.*X11 Layout: *//p')"
        if [[ "$current_layout" != "$target_layout" ]]; then
            sudo localectl set-x11-keymap "$target_layout"
            ok "Keyboard layout set to ${target_layout}"
        else
            ok "Keyboard layout already set to ${target_layout}"
        fi
    fi

    # GPU groups
    if [[ "$_HAS_DISCRETE_AMD_GPU" == true ]]; then
        info "Discrete AMD GPU found — adding user to render/video groups"
        sudo usermod -aG video,render "$(id -un)"
        ok "GPU groups configured"
    else
        info "No discrete AMD GPU detected — skipping GPU group setup"
    fi

    # Firewall
    if ! systemctl is-active --quiet firewalld 2>/dev/null; then
        info "Enabling firewall..."
        sudo systemctl enable --now firewalld
    fi
    ok "firewalld enabled (default zone: $(sudo firewall-cmd --get-default-zone 2>/dev/null || echo "unknown"))"

    # Bluetooth
    sudo systemctl enable --now bluetooth
    ok "Bluetooth enabled"

    # Tuned
    sudo systemctl enable --now tuned
    ok "Tuned enabled"

    # Mode summary
    if [[ "$SWAY_SPIN" == true ]]; then
        info "Mode: Sway Spin (core Sway packages assumed pre-installed)"
    else
        info "Mode: Base Fedora (full Sway stack will be installed)"
    fi
}

# system::status
# Prints a one-line summary of current system configuration.
system::status() {
    _detect_gpu

    local hostname_val keyboard_val zone_val gpu_val

    hostname_val="$(hostname -s)"

    keyboard_val="$(localectl status 2>/dev/null \
        | sed -n 's/.*X11 Layout: *//p')"
    keyboard_val="${keyboard_val:-unset}"

    if systemctl is-active --quiet firewalld 2>/dev/null; then
        zone_val="$(sudo firewall-cmd --get-default-zone 2>/dev/null || echo "unknown")"
    else
        zone_val="inactive"
    fi

    if [[ "$_HAS_DISCRETE_AMD_GPU" == true ]]; then
        local current_groups
        current_groups="$(id -Gn)"
        if echo "$current_groups" | grep -qw video && \
           echo "$current_groups" | grep -qw render; then
            gpu_val="video,render"
        else
            gpu_val="incomplete"
        fi
    else
        gpu_val="none"
    fi

    echo "system: host=${hostname_val} keyboard=${keyboard_val} firewall=${zone_val} gpu_groups=${gpu_val}"
}
