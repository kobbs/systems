# modules/theme.sh — Theme module (accent colors + icon theme + SDDM).
# Source this file; do not execute it directly.
#
# Merges: scripts/theme-accent-color.sh + scripts/theme-sddm.sh
#
# Assumes all libs sourced, REPO_ROOT set.
# apply_accent(), load_accent(), load_all_presets(), pkg_install(),
# require_cmd() are available.

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
    "swaylock/config"
)

_ACCENT_BASH_PROMPT="bash/prompt.sh"

# ---------------------------------------------------------------------------
# Detection helpers (from theme-accent-color.sh)
# ---------------------------------------------------------------------------

_detect_preset() {
    local file="$1"
    [[ -f "$file" ]] || { echo "missing"; return; }

    if grep -q '@@[A-Za-z_]*@@' "$file" 2>/dev/null; then
        echo "broken"
        return
    fi

    local found="" count=0
    local preset
    for preset in "${!COLOR_PRESETS[@]}"; do
        read -r p _rest <<< "${COLOR_PRESETS[$preset]}"
        if grep -qi "${p}" "$file" 2>/dev/null; then
            found="${found:+${found}+}${preset}"
            count=$(( count + 1 ))
        fi
    done

    if [[ "$count" -eq 0 ]]; then
        echo "unknown"
    elif [[ "$count" -eq 1 ]]; then
        echo "$found"
    else
        echo "mixed($found)"
    fi
}

_detect_preset_bare() {
    local file="$1"
    [[ -f "$file" ]] || { echo "missing"; return; }

    if grep -q '@@[A-Za-z_]*@@' "$file" 2>/dev/null; then
        echo "broken"
        return
    fi

    local found="" count=0
    local preset
    for preset in "${!COLOR_PRESETS[@]}"; do
        read -r p _rest <<< "${COLOR_PRESETS[$preset]}"
        local bare="${p#\#}"
        if grep -qi "${bare}" "$file" 2>/dev/null; then
            found="${found:+${found}+}${preset}"
            count=$(( count + 1 ))
        fi
    done

    if [[ "$count" -eq 0 ]]; then
        echo "unknown"
    elif [[ "$count" -eq 1 ]]; then
        echo "$found"
    else
        echo "mixed($found)"
    fi
}

_detect_bash_prompt() {
    local file="$1"
    [[ -f "$file" ]] || { echo "missing"; return; }

    local ansi_code
    ansi_code=$(sed -n 's/^_GREEN="\$(_pc \([0-9]*\))".*/\1/p' "$file")
    [[ -z "$ansi_code" ]] && { echo "unknown"; return; }

    local preset
    for preset in "${!COLOR_PRESETS[@]}"; do
        read -r _p _d _dk _br _s ansi <<< "${COLOR_PRESETS[$preset]}"
        if [[ "$ansi_code" == "$ansi" ]]; then
            echo "$preset"
            return
        fi
    done
    echo "unknown(ANSI=$ansi_code)"
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

        case "$method" in
            hex)  detected=$(_detect_preset "$filepath") ;;
            bare) detected=$(_detect_preset_bare "$filepath") ;;
            ansi) detected=$(_detect_bash_prompt "$filepath") ;;
        esac

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
# Tela icon theme
# ---------------------------------------------------------------------------

_install_tela_icon_theme() {
    require_cmd git "sudo dnf install -y git"

    local tela_dir="$HOME/.local/share/icons/Tela-${ACCENT_NAME}"
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
        local tela_tmp
        tela_tmp=$(mktemp -d)
        git clone --depth 1 https://github.com/vinceliuice/Tela-icon-theme.git "$tela_tmp"
        bash "$tela_tmp/install.sh" -d "$HOME/.local/share/icons" "$ACCENT_NAME"
        rm -rf "$tela_tmp"
        ok "Tela ${ACCENT_NAME} icon theme installed"
    else
        ok "Tela ${ACCENT_NAME} icon theme already installed (skipped)"
    fi
}

# ---------------------------------------------------------------------------
# SDDM theming (from theme-sddm.sh)
# ---------------------------------------------------------------------------

_apply_sddm() {
    if ! rpm -q sddm &>/dev/null; then
        info "SDDM not installed — skipping SDDM theming"
        return 0
    fi

    local use_corners=false
    local arg
    for arg in "$@"; do
        [[ "$arg" == "--corners" ]] && use_corners=true
    done

    info "Configuring SDDM theme..."
    local config_dir="$REPO_ROOT/config"
    local sddm_theme_name=""

    if [[ "$use_corners" == true ]]; then
        # sddm-theme-corners
        pkg_install qt6-qt5compat qt6-qtsvg

        local sddm_theme_dir="/usr/share/sddm/themes/corners"
        if [[ -d "$sddm_theme_dir" ]]; then
            ok "sddm-theme-corners already installed (skipped)"
        else
            local corners_tmp
            corners_tmp=$(mktemp -d)
            git clone --depth 1 https://github.com/aczw/sddm-theme-corners.git "$corners_tmp"
            sudo cp -r "$corners_tmp/corners" "$sddm_theme_dir"
            rm -rf "$corners_tmp"
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
        local theme_tmp
        theme_tmp=$(mktemp)
        cp "$config_dir/sddm/theme.conf" "$theme_tmp"
        apply_accent "$theme_tmp"
        sudo cp "$theme_tmp" "$sddm_theme_dir/theme.conf"
        sudo chmod 644 "$sddm_theme_dir/theme.conf"
        rm -f "$theme_tmp"

        sddm_theme_name="corners"
    else
        # Stock Fedora + dark grey background
        local sddm_theme_dir="/usr/share/sddm/themes/03-sway-fedora"
        local bg_src="$config_dir/sddm/background-dark-grey.png"
        local bg_dest="$sddm_theme_dir/background-dark-grey.png"

        if [[ ! -d "$sddm_theme_dir" ]]; then
            warn "Stock SDDM theme not found at $sddm_theme_dir — is sddm installed?"
        else
            sudo cp "$bg_src" "$bg_dest"
            sudo chmod 644 "$bg_dest"
            local user_conf_tmp
            user_conf_tmp=$(mktemp)
            cat <<'USERCONF' > "$user_conf_tmp"
[General]
background=background-dark-grey.png
USERCONF
            if ! sudo cmp -s "$user_conf_tmp" "$sddm_theme_dir/theme.conf.user" 2>/dev/null; then
                sudo cp "$user_conf_tmp" "$sddm_theme_dir/theme.conf.user"
                sudo chmod 644 "$sddm_theme_dir/theme.conf.user"
            fi
            rm -f "$user_conf_tmp"
            ok "Dark grey background applied to stock SDDM theme"
        fi

        sddm_theme_name="03-sway-fedora"
    fi

    # Set active SDDM theme
    local sddm_conf_tmp
    sddm_conf_tmp=$(mktemp)
    cat > "$sddm_conf_tmp" <<EOF
[Theme]
Current=$sddm_theme_name
EOF
    sudo mkdir -p /etc/sddm.conf.d
    if ! sudo cmp -s "$sddm_conf_tmp" /etc/sddm.conf.d/theme.conf 2>/dev/null; then
        sudo cp "$sddm_conf_tmp" /etc/sddm.conf.d/theme.conf
        sudo chmod 644 /etc/sddm.conf.d/theme.conf
    fi
    rm -f "$sddm_conf_tmp"

    # Disable greetd if previously enabled, enable sddm
    if systemctl is-enabled greetd &>/dev/null; then
        sudo systemctl disable greetd
    fi
    sudo systemctl enable sddm

    ok "SDDM configured (theme: $sddm_theme_name)"
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
        ACCENT="${_THEME_ACCENT_OVERRIDE}"
    fi
    load_accent

    local config_dir="$REPO_ROOT/config"

    # Check a representative file
    local f
    for f in "${_ACCENT_HEX_FILES[@]}"; do
        local detected
        detected=$(_detect_preset "$config_dir/$f")
        [[ "$detected" != "$ACCENT_NAME" ]] && return 0
    done

    # Check icon theme
    local tela_dir="$HOME/.local/share/icons/Tela-${ACCENT_NAME}"
    [[ ! -d "$tela_dir" ]] && return 0

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
        ACCENT="${_THEME_ACCENT_OVERRIDE}"
    fi
    load_accent

    info "[theme] Preview:"
    echo "  Target accent: $ACCENT_NAME"
    echo "  PRIMARY=$ACCENT_PRIMARY DIM=$ACCENT_DIM DARK=$ACCENT_DARK BRIGHT=$ACCENT_BRIGHT SECONDARY=$ACCENT_SECONDARY"
    echo ""

    local config_dir="$REPO_ROOT/config"
    echo "  Config file status:"
    local f
    for f in "${_ACCENT_HEX_FILES[@]}"; do
        local detected
        detected=$(_detect_preset "$config_dir/$f")
        local status="OK"
        [[ "$detected" != "$ACCENT_NAME" ]] && status="WILL UPDATE ($detected → $ACCENT_NAME)"
        printf "    %-40s %s\n" "config/$f" "$status"
    done
    if command -v sway &>/dev/null; then
        for f in "${_ACCENT_SWAY_FILES[@]}"; do
            local detected
            detected=$(_detect_preset "$config_dir/$f")
            local status="OK"
            [[ "$detected" != "$ACCENT_NAME" ]] && status="WILL UPDATE ($detected → $ACCENT_NAME)"
            printf "    %-40s %s\n" "config/$f" "$status"
        done
    fi

    # Icon theme
    local tela_dir="$HOME/.local/share/icons/Tela-${ACCENT_NAME}"
    if [[ -d "$tela_dir" ]]; then
        echo "  Icon theme: Tela-${ACCENT_NAME}  [installed]"
    else
        echo "  Icon theme: Tela-${ACCENT_NAME}  [WILL INSTALL]"
    fi

    # SDDM
    if rpm -q sddm &>/dev/null; then
        echo "  SDDM: will configure"
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
        ACCENT="${_THEME_ACCENT_OVERRIDE}"
    fi
    load_accent

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
    fi
    ok "Config files updated"

    # 3. Bash prompt ANSI code
    local prompt_file="$config_dir/$_ACCENT_BASH_PROMPT"
    if [[ -f "$prompt_file" ]]; then
        sed -i "s/^\(_GREEN=\"\$(_pc \)[0-9]*/\1${ACCENT_ANSI}/" "$prompt_file"
        ok "Bash prompt hostname color updated (ANSI $ACCENT_ANSI)"
    fi

    # 4. SDDM (if installed)
    _apply_sddm "$@"

    ok "Theme applied: $ACCENT_NAME"
}

theme::status() {
    load_all_presets
    load_accent

    local tela="not installed"
    [[ -d "$HOME/.local/share/icons/Tela-${ACCENT_NAME}" ]] && tela="installed"

    local sddm="not installed"
    if rpm -q sddm &>/dev/null; then
        sddm=$(grep -oP 'Current=\K.*' /etc/sddm.conf.d/theme.conf 2>/dev/null || echo "unknown")
    fi

    echo "theme: accent=$ACCENT_NAME icon=Tela-${ACCENT_NAME}($tela) sddm=$sddm"
}
