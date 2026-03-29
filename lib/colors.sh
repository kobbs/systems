# shellcheck shell=bash
# lib/colors.sh -- Color preset system
# Sourced by other scripts, not executed directly.
# Requires: REPO_ROOT set by caller.
# ---------------------------------------------------------------------------

declare -gA COLOR_PRESETS=()

# ---------------------------------------------------------------------------
# load_all_presets [colors_dir]
# Reads all colors/*.conf files into the COLOR_PRESETS associative array.
# Each entry format: "PRIMARY DIM DARK BRIGHT SECONDARY ANSI"
# Uses its own simple key=value parser -- does NOT touch _CONFIG.
# ---------------------------------------------------------------------------
load_all_presets() {
    local dir="${1:-${REPO_ROOT}/colors}"
    COLOR_PRESETS=()

    local conf
    for conf in "$dir"/*.conf; do
        [[ -f "$conf" ]] || continue

        local -A kv=()
        local line
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line#"${line%%[![:space:]]*}"}"
            line="${line%"${line##*[![:space:]]}"}"
            [[ -z "$line" || "$line" == \#* ]] && continue
            local key="${line%%=*}" val="${line#*=}"
            key="${key%"${key##*[![:space:]]}"}"
            val="${val#"${val%%[![:space:]]*}"}"
            kv["$key"]="$val"
        done < "$conf"

        local name="${kv[name]:-}"
        [[ -z "$name" ]] && continue

        COLOR_PRESETS["$name"]="${kv[primary]} ${kv[dim]} ${kv[dark]} ${kv[bright]} ${kv[secondary]} ${kv[ansi]}"
    done
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
        echo "Error: green preset not found -- load_all_presets must be called first" >&2
        return 1
    fi

    local p d dk br s ansi
    read -r p d dk br s ansi <<< "${COLOR_PRESETS[$name]}"

    ACCENT_NAME="$name"
    ACCENT_PRIMARY="$p"
    ACCENT_DIM="$d"
    ACCENT_DARK="$dk"
    ACCENT_BRIGHT="$br"
    ACCENT_SECONDARY="$s"
    export ACCENT_ANSI="$ansi"
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
    local -a sed_args=()
    local -i i=0
    for role in "${roles[@]}"; do
        local target="${targets[$i]}"
        local target_bare="${target#\#}"
        sed_args+=(-e "s/@@ACCENT_${role}@@/${target}/g")
        sed_args+=(-e "s/@@BARE_${role}@@/${target_bare}/g")
        for preset in "${!COLOR_PRESETS[@]}"; do
            sed_args+=(-e "s/@@${preset}_${role}@@/${target}/g")
            sed_args+=(-e "s/@@BARE_${preset}_${role}@@/${target_bare}/g")
        done
        i=$(( i + 1 ))
    done
    sed -i "${sed_args[@]}" "$file"

    # Pass 1: known preset colors → preset-specific placeholders
    sed_args=()
    for preset in "${!COLOR_PRESETS[@]}"; do
        [[ "$preset" == "$ACCENT_NAME" ]] && continue
        read -r p d dk br s _ansi <<< "${COLOR_PRESETS[$preset]}"

        local -i i=0
        for src in "$p" "$d" "$dk" "$br" "$s"; do
            local src_bare="${src#\#}" role="${roles[$i]}"
            sed_args+=(-e "s/${src}/@@${preset}_${role}@@/gI")
            sed_args+=(-e "s/=${src_bare}$/=@@BARE_${preset}_${role}@@/gI")
            i=$(( i + 1 ))
        done

        sed_args+=(-e "s/Tela-${preset}/Tela-${ACCENT_NAME}/g")
    done
    if [[ ${#sed_args[@]} -gt 0 ]]; then
        sed -i "${sed_args[@]}" "$file"
    fi

    # Pass 2: all placeholders → target colors
    sed_args=()
    for preset in "${!COLOR_PRESETS[@]}"; do
        [[ "$preset" == "$ACCENT_NAME" ]] && continue
        local -i i=0
        for role in "${roles[@]}"; do
            local target="${targets[$i]}" target_bare="${targets[$i]#\#}"
            sed_args+=(-e "s/@@${preset}_${role}@@/${target}/g")
            sed_args+=(-e "s/@@BARE_${preset}_${role}@@/${target_bare}/g")
            i=$(( i + 1 ))
        done
    done
    if [[ ${#sed_args[@]} -gt 0 ]]; then
        sed -i "${sed_args[@]}" "$file"
    fi
}
