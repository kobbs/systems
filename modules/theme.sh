# modules/theme.sh — Theme module (accent colors + icon theme + SDDM).
# Source this file; do not execute it directly.
#
# Merges: scripts/theme-accent-color.sh + scripts/theme-sddm.sh
#
# Assumes all libs sourced, REPO_ROOT set.
# apply_accent(), load_accent(), load_all_presets(), pkg_install(),
# require_cmd() are available.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

_SDDM_THEME_BASE="/usr/share/sddm/themes"
_TELA_ICON_BASE="$HOME/.local/share/icons"

# ---------------------------------------------------------------------------
# File lists for accent color application
# ---------------------------------------------------------------------------

_ACCENT_HEX_FILES=(
    "kitty/kitty.conf"
    "tmux/tmux.conf"
    "dunst/dunstrc"
    "sddm/theme.conf"
    "gtk/settings.ini"
    "kde/kdeglobals"
    "fish/conf.d/02-colors.fish"
)

_ACCENT_SWAY_FILES=(
    "sway/config"
    "waybar/style.css"
)

_ACCENT_BARE_FILES=(
    "swaylock/config"
)

_ACCENT_TELA_FILES=(
    "gtk/settings.ini"
    "kde/kdeglobals"
)

_ACCENT_BASH_PROMPT="bash/prompt.sh"

# ---------------------------------------------------------------------------
# Detection helpers
# ---------------------------------------------------------------------------

# _detect_preset_in_file <file> <method>
# method: "hex"  — match PRIMARY color with '#' prefix (most config files)
#         "bare" — match PRIMARY color without '#' (swaylock)
#         "ansi" — match ANSI code number (bash prompt)
# Returns: preset name, "missing", "broken", "unknown", or "mixed(a+b)"
_detect_preset_in_file() {
    local file="$1"
    local method="$2"
    [[ -f "$file" ]] || { echo "missing"; return; }

    # Check for leftover placeholders (interrupted run)
    if grep -q '@@[A-Za-z_]*@@' "$file" 2>/dev/null; then
        echo "broken"
        return
    fi

    # ANSI method has completely different matching logic
    if [[ "$method" == "ansi" ]]; then
        local ansi_code
        ansi_code=$(sed -n 's/^_GREEN="\$(_pc \([0-9]*\))".*/\1/p' "$file")
        [[ -z "$ansi_code" ]] && { echo "unknown"; return; }
        local preset
        for preset in "${!COLOR_PRESETS[@]}"; do
            read -r _p _d _dk _br _s ansi <<< "${COLOR_PRESETS[$preset]}"
            [[ "$ansi_code" == "$ansi" ]] && { echo "$preset"; return; }
        done
        echo "unknown(ANSI=$ansi_code)"
        return
    fi

    # tela: match Tela-{preset} icon theme name
    if [[ "$method" == "tela" ]]; then
        local found="" count=0
        local preset
        for preset in "${!COLOR_PRESETS[@]}"; do
            if grep -q "Tela-${preset}" "$file" 2>/dev/null; then
                found="${found:+${found}+}${preset}"
                count=$(( count + 1 ))
            fi
        done
        if [[ "$count" -eq 0 ]]; then echo "unknown"
        elif [[ "$count" -eq 1 ]]; then echo "$found"
        else echo "mixed($found)"
        fi
        return
    fi

    # hex/bare: score each preset by how many of its color roles match
    # PRIMARY match gets 2 points (stronger signal), other roles get 1 point
    local best="" best_score=0
    local preset
    for preset in "${!COLOR_PRESETS[@]}"; do
        read -r p d dk br s _ansi <<< "${COLOR_PRESETS[$preset]}"
        local score=0
        local needle="$p"
        [[ "$method" == "bare" ]] && needle="${p#\#}"
        grep -qi "${needle}" "$file" 2>/dev/null && score=$(( score + 2 ))
        local src
        for src in "$d" "$dk" "$br" "$s"; do
            needle="$src"
            [[ "$method" == "bare" ]] && needle="${src#\#}"
            grep -qi "${needle}" "$file" 2>/dev/null && score=$(( score + 1 ))
        done
        if [[ "$score" -gt "$best_score" ]]; then
            best_score=$score
            best=$preset
        fi
    done

    if [[ "$best_score" -eq 0 ]]; then
        echo "unknown"
    else
        echo "$best"
    fi
}

# _detect_all_files
# Populates _DETECT_RESULTS associative array: file → detected preset name.
# Must call load_all_presets + load_accent before calling.
declare -gA _DETECT_RESULTS=()

_detect_all_files() {
    _DETECT_RESULTS=()
    local config_dir="$REPO_ROOT/config"
    local f

    for f in "${_ACCENT_HEX_FILES[@]}"; do
        _DETECT_RESULTS["$f"]=$(_detect_preset_in_file "$config_dir/$f" hex)
    done

    # Sway files: only detect if sway is present
    if command -v sway &>/dev/null; then
        for f in "${_ACCENT_SWAY_FILES[@]}"; do
            _DETECT_RESULTS["$f"]=$(_detect_preset_in_file "$config_dir/$f" hex)
        done
        for f in "${_ACCENT_BARE_FILES[@]}"; do
            _DETECT_RESULTS["$f"]=$(_detect_preset_in_file "$config_dir/$f" bare)
        done
    fi

    # Tela icon theme files (detect by Tela-{preset} name)
    for f in "${_ACCENT_TELA_FILES[@]}"; do
        _DETECT_RESULTS["$f"]=$(_detect_preset_in_file "$config_dir/$f" tela)
    done

    # Bash prompt
    _DETECT_RESULTS["$_ACCENT_BASH_PROMPT"]=$(
        _detect_preset_in_file "$config_dir/$_ACCENT_BASH_PROMPT" ansi
    )
}

# ---------------------------------------------------------------------------
# List presets
# ---------------------------------------------------------------------------

list_presets() {
    load_all_presets
    load_accent
    echo ""
    echo "Active accent: $ACCENT_NAME"
    echo ""
    local preset
    for preset in "${!COLOR_PRESETS[@]}"; do
        read -r p d dk br s ansi <<< "${COLOR_PRESETS[$preset]}"
        local label="$preset"
        [[ "$preset" == "$ACCENT_NAME" ]] && label="$preset (active)"
        echo "  $label:"
        echo "    PRIMARY    $p"
        echo "    DIM        $d"
        echo "    DARK       $dk"
        echo "    BRIGHT     $br"
        echo "    SECONDARY  $s"
        echo "    ANSI       $ansi"
        echo ""
    done
}

# ---------------------------------------------------------------------------
# Audit
# ---------------------------------------------------------------------------

audit_accents() {
    local config_dir="$REPO_ROOT/config"
    load_all_presets
    load_accent

    local expected="$ACCENT_NAME"
    read -r exp_p exp_d exp_dk exp_br exp_s exp_ansi <<< "${COLOR_PRESETS[$expected]}"

    echo ""
    echo "Accent Color Audit"
    echo "==================="
    echo ""
    echo "  Expected preset: $expected"
    echo "  Expected PRIMARY: $exp_p  DIM: $exp_d  DARK: $exp_dk  BRIGHT: $exp_br  SECONDARY: $exp_s"
    echo ""

    local -i anomalies=0

    local -a audit_items=(
        "sway|$config_dir/sway/config|hex"
        "waybar|$config_dir/waybar/style.css|hex"
        "sddm|$config_dir/sddm/theme.conf|hex"
        "fish|$config_dir/fish/conf.d/02-colors.fish|hex"
        "kitty|$config_dir/kitty/kitty.conf|hex"
        "tmux|$config_dir/tmux/tmux.conf|hex"
        "dunst|$config_dir/dunst/dunstrc|hex"
        "gtk|$config_dir/gtk/settings.ini|hex"
        "kde|$config_dir/kde/kdeglobals|hex"
        "swaylock|$config_dir/swaylock/config|bare"
        "bash prompt|$config_dir/bash/prompt.sh|ansi"
    )

    printf "  %-14s %-10s %s\n" "COMPONENT" "DETECTED" "STATUS"
    printf "  %-14s %-10s %s\n" "---------" "--------" "------"

    local item
    for item in "${audit_items[@]}"; do
        IFS='|' read -r label filepath method <<< "$item"

        local detected=""
        detected=$(_detect_preset_in_file "$filepath" "$method")

        local status="OK"
        if [[ "$detected" == "missing" ]]; then
            status="FILE NOT FOUND"
            anomalies=$((anomalies + 1))
        elif [[ "$detected" == "broken" ]]; then
            status="BROKEN — leftover placeholders from interrupted run"
            anomalies=$((anomalies + 1))
        elif [[ "$detected" == "unknown" ]]; then
            local _tela_found=""
            local _tp
            for _tp in "${!COLOR_PRESETS[@]}"; do
                if grep -qi "Tela-${_tp}" "$filepath" 2>/dev/null; then
                    _tela_found="$_tp"
                    break
                fi
            done
            if [[ -n "$_tela_found" ]]; then
                detected="$_tela_found"
                if [[ "$_tela_found" == "$expected" ]]; then
                    status="OK (icon theme)"
                else
                    status="MISMATCH — expected $expected (icon theme)"
                    anomalies=$((anomalies + 1))
                fi
            else
                status="NO ACCENT COLORS FOUND"
                anomalies=$((anomalies + 1))
            fi
        elif [[ "$detected" != "$expected" ]]; then
            status="MISMATCH — expected $expected"
            anomalies=$((anomalies + 1))
        fi

        printf "  %-14s %-10s %s\n" "$label" "$detected" "$status"
    done

    echo ""
    if [[ "$anomalies" -eq 0 ]]; then
        echo "  No anomalies detected."
    else
        echo "  $anomalies anomaly/anomalies detected."
        echo "  Run './setup theme --apply' to fix."
    fi
    echo ""
}

# ---------------------------------------------------------------------------
# Error handling
# ---------------------------------------------------------------------------

_THEME_TMPDIR=""

_theme_cleanup() {
    [[ -n "$_THEME_TMPDIR" ]] && rm -rf "$_THEME_TMPDIR"
}

# ---------------------------------------------------------------------------
# Tela icon theme
# ---------------------------------------------------------------------------

_install_tela_icon_theme() {
    require_cmd git "sudo dnf install -y git"

    local tela_dir="${_TELA_ICON_BASE}/Tela-${ACCENT_NAME}"
    local need_install=false

    if [[ ! -d "$tela_dir" ]]; then
        need_install=true
    elif [[ -f "$tela_dir/scalable/places/default-folder.svg" ]]; then
        if [[ "$ACCENT_NAME" != "standard" ]] \
            && grep -qi '#5294e2' "$tela_dir/scalable/places/default-folder.svg"; then
            warn "Tela-${ACCENT_NAME} contains default blue icons — reinstalling..."
            rm -rf "$tela_dir" "${tela_dir}-dark" "${tela_dir}-light"
            need_install=true
        fi
    else
        warn "Tela-${ACCENT_NAME} is incomplete — reinstalling..."
        rm -rf "$tela_dir" "${tela_dir}-dark" "${tela_dir}-light"
        need_install=true
    fi

    if [[ "$need_install" == true ]]; then
        info "Installing Tela ${ACCENT_NAME} icon theme (user-local)..."
        local tela_tmp="${_THEME_TMPDIR}/tela-icon-theme"
        if ! git clone --depth 1 https://github.com/vinceliuice/Tela-icon-theme.git "$tela_tmp" 2>&1; then
            warn "Failed to clone Tela-icon-theme — skipping icon theme"
            return 0
        fi
        bash "$tela_tmp/install.sh" -d "${_TELA_ICON_BASE}" "$ACCENT_NAME"
        ok "Tela ${ACCENT_NAME} icon theme installed"
    else
        ok "Tela ${ACCENT_NAME} icon theme already installed (skipped)"
    fi
}

# ---------------------------------------------------------------------------
# SDDM theming (split into focused helpers)
# ---------------------------------------------------------------------------

# _install_sddm_corners <theme_dir>
# Git clones sddm-theme-corners, applies Qt6 patch, adds dark background.
_install_sddm_corners() {
    local sddm_theme_dir="$1"

    pkg_install qt6-qt5compat qt6-qtsvg

    if [[ -d "$sddm_theme_dir" ]]; then
        ok "sddm-theme-corners already installed (skipped)"
    else
        local corners_tmp="${_THEME_TMPDIR}/corners"
        if ! git clone --depth 1 https://github.com/aczw/sddm-theme-corners.git "$corners_tmp" 2>&1; then
            warn "Failed to clone sddm-theme-corners — skipping"
            return 0
        fi
        sudo cp -r "$corners_tmp/corners" "$sddm_theme_dir" \
            || { warn "Failed to install sddm-theme-corners"; return 0; }
        ok "sddm-theme-corners installed"
    fi

    sudo chmod -R a+rX "$sddm_theme_dir"

    # Qt5 → Qt6 patch
    if compgen -G "$sddm_theme_dir/components/*.qml" >/dev/null; then
        sudo sed -i 's/import QtGraphicalEffects.*/import Qt5Compat.GraphicalEffects/' \
            "$sddm_theme_dir"/components/*.qml
    fi

    # Dark background color
    if [[ -f "$sddm_theme_dir/Main.qml" ]]; then
        if ! sudo grep -q 'color: "#222222"' "$sddm_theme_dir/Main.qml"; then
            sudo sed -i '/id: root/a\    color: "#222222"' "$sddm_theme_dir/Main.qml"
        fi
    fi

    # Deploy theme.conf with accent colors
    local theme_tmp="${_THEME_TMPDIR}/sddm-theme.conf"
    cp "$REPO_ROOT/config/sddm/theme.conf" "$theme_tmp"
    apply_accent "$theme_tmp"
    sudo cp "$theme_tmp" "$sddm_theme_dir/theme.conf"
    sudo chmod 644 "$sddm_theme_dir/theme.conf"
}

# _apply_sddm_stock <theme_dir>
# Configures stock Fedora SDDM theme with dark grey background.
_apply_sddm_stock() {
    local sddm_theme_dir="$1"
    local bg_src="$REPO_ROOT/config/sddm/background-dark-grey.png"

    if [[ ! -d "$sddm_theme_dir" ]]; then
        warn "Stock SDDM theme not found at $sddm_theme_dir — is sddm installed?"
        return 0
    fi

    sudo cp "$bg_src" "$sddm_theme_dir/background-dark-grey.png" \
        || { warn "Failed to copy SDDM background"; return 0; }
    sudo chmod 644 "$sddm_theme_dir/background-dark-grey.png"

    local user_conf_tmp="${_THEME_TMPDIR}/sddm-user.conf"
    printf '[General]\nbackground=background-dark-grey.png\n' > "$user_conf_tmp"
    if ! sudo cmp -s "$user_conf_tmp" "$sddm_theme_dir/theme.conf.user" 2>/dev/null; then
        sudo cp "$user_conf_tmp" "$sddm_theme_dir/theme.conf.user"
        sudo chmod 644 "$sddm_theme_dir/theme.conf.user"
    fi
    ok "Dark grey background applied to stock SDDM theme"
}

# _set_sddm_active_theme <theme_name>
# Writes /etc/sddm.conf.d/theme.conf, disables greetd if active, enables sddm.
_set_sddm_active_theme() {
    local theme_name="$1"
    local sddm_conf_tmp="${_THEME_TMPDIR}/sddm-active.conf"
    printf '[Theme]\nCurrent=%s\n' "$theme_name" > "$sddm_conf_tmp"
    sudo mkdir -p /etc/sddm.conf.d
    if ! sudo cmp -s "$sddm_conf_tmp" /etc/sddm.conf.d/theme.conf 2>/dev/null; then
        sudo cp "$sddm_conf_tmp" /etc/sddm.conf.d/theme.conf
        sudo chmod 644 /etc/sddm.conf.d/theme.conf
    fi

    if systemctl is-enabled greetd &>/dev/null; then
        sudo systemctl disable greetd
    fi
    sudo systemctl enable sddm
    ok "SDDM configured (theme: $theme_name)"
}

# _apply_sddm — Orchestrator
# Calls the appropriate variant based on --corners flag, then sets active theme.
_apply_sddm() {
    if ! rpm -q sddm &>/dev/null; then
        info "SDDM not installed — skipping SDDM theming"
        return 0
    fi

    info "Configuring SDDM theme..."

    if [[ "$_THEME_CORNERS" == true ]]; then
        _install_sddm_corners "${_SDDM_THEME_BASE}/corners"
        _set_sddm_active_theme "corners"
    else
        _apply_sddm_stock "${_SDDM_THEME_BASE}/03-sway-fedora"
        _set_sddm_active_theme "03-sway-fedora"
    fi
}

# ---------------------------------------------------------------------------
# Flag parsing
# ---------------------------------------------------------------------------

_theme_parse_flags() {
    _THEME_ACCENT_OVERRIDE=""
    _THEME_DO_LIST=false
    _THEME_DO_AUDIT=false
    _THEME_CORNERS=false
    local arg
    for arg in "$@"; do
        case "$arg" in
            --list)    _THEME_DO_LIST=true ;;
            --audit)   _THEME_DO_AUDIT=true ;;
            --corners) _THEME_CORNERS=true ;;
            --accent)  ;; # value follows
            *)
                # Check if previous arg was --accent
                if [[ "${_prev_arg:-}" == "--accent" ]]; then
                    _THEME_ACCENT_OVERRIDE="$arg"
                fi
                ;;
        esac
        _prev_arg="$arg"
    done
    unset _prev_arg
}

# ---------------------------------------------------------------------------
# Module contract
# ---------------------------------------------------------------------------

theme::check() {
    _theme_parse_flags "$@"

    # Special modes bypass check
    [[ "$_THEME_DO_LIST" == true ]] && return 0
    [[ "$_THEME_DO_AUDIT" == true ]] && return 0

    load_all_presets
    if [[ -n "$_THEME_ACCENT_OVERRIDE" ]]; then
        PROFILE_THEME_ACCENT="${_THEME_ACCENT_OVERRIDE}"
    fi
    load_accent

    _detect_all_files
    local f
    for f in "${!_DETECT_RESULTS[@]}"; do
        [[ "${_DETECT_RESULTS[$f]}" != "$ACCENT_NAME" ]] && return 0
    done

    # Check icon theme
    [[ ! -d "${_TELA_ICON_BASE}/Tela-${ACCENT_NAME}" ]] && return 0

    # Check SDDM state (if installed)
    if rpm -q sddm &>/dev/null; then
        local expected_theme="03-sway-fedora"
        [[ "$_THEME_CORNERS" == true ]] && expected_theme="corners"

        # Theme directory must exist
        [[ ! -d "${_SDDM_THEME_BASE}/${expected_theme}" ]] && return 0

        # Active theme must match
        local current_theme
        current_theme=$(grep -oP 'Current=\K.*' /etc/sddm.conf.d/theme.conf 2>/dev/null || echo "")
        [[ "$current_theme" != "$expected_theme" ]] && return 0

        # Deployed theme.conf must have correct accent colors
        local deployed_conf="${_SDDM_THEME_BASE}/${expected_theme}/theme.conf"
        if [[ -f "$deployed_conf" ]]; then
            local sddm_accent
            sddm_accent=$(_detect_preset_in_file "$deployed_conf" hex)
            [[ "$sddm_accent" != "$ACCENT_NAME" ]] && return 0
        fi
    fi

    return 1
}

theme::preview() {
    _theme_parse_flags "$@"

    # Special modes
    if [[ "$_THEME_DO_LIST" == true ]]; then
        list_presets
        return 0
    fi
    if [[ "$_THEME_DO_AUDIT" == true ]]; then
        audit_accents
        return 0
    fi

    load_all_presets
    if [[ -n "$_THEME_ACCENT_OVERRIDE" ]]; then
        PROFILE_THEME_ACCENT="${_THEME_ACCENT_OVERRIDE}"
    fi
    load_accent

    info "[theme] Preview:"
    echo "  Target accent: $ACCENT_NAME"
    echo "  PRIMARY=$ACCENT_PRIMARY DIM=$ACCENT_DIM DARK=$ACCENT_DARK BRIGHT=$ACCENT_BRIGHT SECONDARY=$ACCENT_SECONDARY"
    echo ""

    _detect_all_files
    echo "  Config file status:"
    local f
    for f in "${!_DETECT_RESULTS[@]}"; do
        local detected="${_DETECT_RESULTS[$f]}"
        local status="OK"
        [[ "$detected" != "$ACCENT_NAME" ]] && status="WILL UPDATE ($detected → $ACCENT_NAME)"
        printf "    %-40s %s\n" "config/$f" "$status"
    done

    # Icon theme
    local tela_dir="${_TELA_ICON_BASE}/Tela-${ACCENT_NAME}"
    if [[ -d "$tela_dir" ]]; then
        echo "  Icon theme: Tela-${ACCENT_NAME}  [installed]"
    else
        echo "  Icon theme: Tela-${ACCENT_NAME}  [WILL INSTALL]"
    fi

    # SDDM
    if rpm -q sddm &>/dev/null; then
        local expected_theme="03-sway-fedora"
        [[ "$_THEME_CORNERS" == true ]] && expected_theme="corners"
        local current_theme
        current_theme=$(grep -oP 'Current=\K.*' /etc/sddm.conf.d/theme.conf 2>/dev/null || echo "none")
        if [[ "$current_theme" != "$expected_theme" ]]; then
            echo "  SDDM: $current_theme → $expected_theme  [WILL UPDATE]"
        else
            # Check deployed accent colors
            local deployed_conf="${_SDDM_THEME_BASE}/${expected_theme}/theme.conf"
            if [[ -f "$deployed_conf" ]]; then
                local sddm_accent
                sddm_accent=$(_detect_preset_in_file "$deployed_conf" hex)
                if [[ "$sddm_accent" != "$ACCENT_NAME" ]]; then
                    echo "  SDDM: $expected_theme accent $sddm_accent → $ACCENT_NAME  [WILL UPDATE]"
                else
                    echo "  SDDM: $expected_theme  [OK]"
                fi
            else
                echo "  SDDM: $expected_theme  [OK]"
            fi
        fi
    else
        echo "  SDDM: not installed (skip)"
    fi
}

theme::apply() {
    _theme_parse_flags "$@"

    # Special modes
    if [[ "$_THEME_DO_LIST" == true ]]; then
        list_presets
        return 0
    fi
    if [[ "$_THEME_DO_AUDIT" == true ]]; then
        audit_accents
        return 0
    fi

    load_all_presets
    if [[ -n "$_THEME_ACCENT_OVERRIDE" ]]; then
        PROFILE_THEME_ACCENT="${_THEME_ACCENT_OVERRIDE}"
    fi
    load_accent

    # Validate preset exists
    if [[ -z "${COLOR_PRESETS[$ACCENT_NAME]+x}" ]]; then
        warn "Unknown accent preset: $ACCENT_NAME (available: ${!COLOR_PRESETS[*]})"
        return 1
    fi

    # Set up temp directory with cleanup trap
    _THEME_TMPDIR=$(mktemp -d)
    trap _theme_cleanup EXIT

    info "Accent: $ACCENT_NAME ($ACCENT_PRIMARY)"

    # 1. Tela icon theme
    _install_tela_icon_theme

    # 2. Apply accent to config files
    local config_dir="$REPO_ROOT/config"
    info "Applying accent colors to config files..."
    local f
    for f in "${_ACCENT_HEX_FILES[@]}"; do
        apply_accent "$config_dir/$f"
    done
    if command -v sway &>/dev/null; then
        for f in "${_ACCENT_SWAY_FILES[@]}"; do
            apply_accent "$config_dir/$f"
        done
        for f in "${_ACCENT_BARE_FILES[@]}"; do
            apply_accent "$config_dir/$f"
        done
    fi
    ok "Config files updated"

    # 3. Bash prompt ANSI code
    local prompt_file="$config_dir/$_ACCENT_BASH_PROMPT"
    if [[ -f "$prompt_file" ]]; then
        sed -i "s/^\(_GREEN=\"\$(_pc \)[0-9]*/\1${ACCENT_ANSI}/" "$prompt_file"
        ok "Bash prompt hostname color updated (ANSI $ACCENT_ANSI)"
    fi

    # 4. SDDM (if installed)
    _apply_sddm

    ok "Theme applied: $ACCENT_NAME"
}

theme::status() {
    load_all_presets
    load_accent

    local tela="not installed"
    [[ -d "${_TELA_ICON_BASE}/Tela-${ACCENT_NAME}" ]] && tela="installed"

    local sddm="not installed"
    if rpm -q sddm &>/dev/null; then
        sddm=$(grep -oP 'Current=\K.*' /etc/sddm.conf.d/theme.conf 2>/dev/null || echo "unknown")
    fi

    echo "theme: accent=$ACCENT_NAME icon=Tela-${ACCENT_NAME}($tela) sddm=$sddm"
}
