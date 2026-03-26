# lib/colors.sh — Color preset system
# Sourced by other scripts, not executed directly.
# Requires: lib/config.sh (for _parse_ini), REPO_ROOT set by caller.
# ---------------------------------------------------------------------------

declare -gA COLOR_PRESETS=()

# ---------------------------------------------------------------------------
# load_all_presets [colors_dir]
# Reads all colors/*.conf files into the COLOR_PRESETS associative array.
# Each entry format: "PRIMARY DIM DARK BRIGHT SECONDARY ANSI"
# ---------------------------------------------------------------------------
load_all_presets() {
    local dir="${1:-${REPO_ROOT}/colors}"
    COLOR_PRESETS=()

    # Save _CONFIG (may contain profile data) and work on a clean slate
    local -A _saved_config=()
    local k
    for k in "${!_CONFIG[@]}"; do _saved_config["$k"]="${_CONFIG[$k]}"; done

    local conf
    for conf in "$dir"/*.conf; do
        [[ -f "$conf" ]] || continue

        # Reset _CONFIG for each color file
        _CONFIG=()
        _parse_ini "$conf"

        local name="${_CONFIG[".name"]:-}"
        [[ -z "$name" ]] && continue

        COLOR_PRESETS["$name"]="${_CONFIG[".primary"]} ${_CONFIG[".dim"]} ${_CONFIG[".dark"]} ${_CONFIG[".bright"]} ${_CONFIG[".secondary"]} ${_CONFIG[".ansi"]}"
    done

    # Restore original _CONFIG
    _CONFIG=()
    for k in "${!_saved_config[@]}"; do _CONFIG["$k"]="${_saved_config[$k]}"; done
}

# ---------------------------------------------------------------------------
# load_accent
# Determines the target accent color and populates ACCENT_* variables.
# Priority: PROFILE_THEME_ACCENT > ACCENT env var > "green"
# ---------------------------------------------------------------------------
load_accent() {
    local name="${PROFILE_THEME_ACCENT:-${ACCENT:-green}}"

    if [[ -z "${COLOR_PRESETS[$name]+x}" ]]; then
        echo "Warning: accent preset '$name' not found, falling back to green" >&2
        name="green"
    fi

    if [[ -z "${COLOR_PRESETS[$name]+x}" ]]; then
        echo "Error: green preset not found — load_all_presets must be called first" >&2
        return 0
    fi

    local p d dk br s ansi
    read -r p d dk br s ansi <<< "${COLOR_PRESETS[$name]}"

    ACCENT_NAME="$name"
    ACCENT_PRIMARY="$p"
    ACCENT_DIM="$d"
    ACCENT_DARK="$dk"
    ACCENT_BRIGHT="$br"
    ACCENT_SECONDARY="$s"
    ACCENT_ANSI="$ansi"
}

# ---------------------------------------------------------------------------
# apply_accent <file>
# Two-pass placeholder substitution for accent colors in config files.
# Pass 0: clean up leftover placeholders from interrupted previous runs
# Pass 1: known preset colors -> preset-specific placeholders
# Pass 2: all placeholders -> target colors
# ---------------------------------------------------------------------------
apply_accent() {
    local file="$1"
    [[ -f "$file" ]] || return 0

    local -a roles=(PRIMARY DIM DARK BRIGHT SECONDARY)
    local -a targets=("$ACCENT_PRIMARY" "$ACCENT_DIM" "$ACCENT_DARK" "$ACCENT_BRIGHT" "$ACCENT_SECONDARY")

    # Pass 0: clean up leftover placeholders from interrupted previous runs
    local -i i=0
    for role in "${roles[@]}"; do
        local target="${targets[$i]}"
        local target_bare="${target#\#}"
        sed -i "s/@@ACCENT_${role}@@/${target}/g" "$file"
        sed -i "s/@@BARE_${role}@@/${target_bare}/g" "$file"
        for preset in "${!COLOR_PRESETS[@]}"; do
            sed -i "s/@@${preset}_${role}@@/${target}/g" "$file"
            sed -i "s/@@BARE_${preset}_${role}@@/${target_bare}/g" "$file"
        done
        i=$(( i + 1 ))
    done

    # Pass 1: known preset colors → preset-specific placeholders
    for preset in "${!COLOR_PRESETS[@]}"; do
        [[ "$preset" == "$ACCENT_NAME" ]] && continue
        read -r p d dk br s _ansi <<< "${COLOR_PRESETS[$preset]}"

        local -i i=0
        for src in "$p" "$d" "$dk" "$br" "$s"; do
            local src_bare="${src#\#}" role="${roles[$i]}"
            sed -i "s/${src}/@@${preset}_${role}@@/gI" "$file"
            sed -i "s/=${src_bare}$/=@@BARE_${preset}_${role}@@/gI" "$file"
            i=$(( i + 1 ))
        done

        sed -i "s/Tela-${preset}/Tela-${ACCENT_NAME}/g" "$file"
    done

    # Pass 2: all placeholders → target colors
    for preset in "${!COLOR_PRESETS[@]}"; do
        [[ "$preset" == "$ACCENT_NAME" ]] && continue
        local -i i=0
        for role in "${roles[@]}"; do
            local target="${targets[$i]}" target_bare="${targets[$i]#\#}"
            sed -i "s/@@${preset}_${role}@@/${target}/g" "$file"
            sed -i "s/@@BARE_${preset}_${role}@@/${target_bare}/g" "$file"
            i=$(( i + 1 ))
        done
    done
}
