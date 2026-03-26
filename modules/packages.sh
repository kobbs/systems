# modules/packages.sh — System package management module.
# Source this file; do not execute it directly.
#
# Handles: system update, RPM Fusion repos, codec swaps, Flathub,
#          Sway/Wayland packages, CLI tools, security (Yubikey), ROCm.
#
# Assumes lib/common.sh and lib/config.sh are already sourced.
# pkg_install(), find_fedora_version(), REPO_ROOT, PROFILE_* vars available.

# ---------------------------------------------------------------------------
# Package lists (sorted alphabetically, one per line)
# ---------------------------------------------------------------------------

_SWAY_COMMON_PKGS=(
    bat
    bemenu
    bluez
    fish
    google-roboto-mono-fonts
    jq
    kitty
    libnotify
    mate-polkit
    mesa-demos
    network-manager-applet
    pavucontrol
    plasma-integration
    podman
    qt5ct
    qt6ct
    tuned
    tuned-ppd
    vim
    vulkan-tools
)

_SWAY_EXTRA_PKGS=(
    grim
    kanshi
    mako
    slurp
    sway
    swaybg
    swayidle
    swaylock
    waybar
    wl-clipboard
    xdg-desktop-portal-wlr
)

_CLI_PKGS=(
    btop
    curl
    fd-find
    fzf
    git
    htop
    p7zip
    ripgrep
    tmux
    unzip
    wget
)

_SECURITY_PKGS=(
    pam-u2f
    yubikey-manager
)

_ROCM_PKGS=(
    rocm-hip-runtime
    rocm-opencl-runtime
    rocm-smi-lib
    rocminfo
)

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

_read_mode() {
    local mode_file="$HOME/.config/shell/.bootstrap-mode"
    if [[ -f "$mode_file" ]] && grep -qxE 'true|false' "$mode_file"; then
        cat "$mode_file"
    else
        # Default: not sway spin
        echo "false"
    fi
}

_build_pkg_list() {
    local sway_spin="$1"
    local install_rocm="$2"
    local pkgs=()

    pkgs+=("dnf-plugins-core" "flatpak")

    if [[ "$sway_spin" == "true" ]]; then
        pkgs+=("${_SWAY_COMMON_PKGS[@]}")
    else
        pkgs+=("${_SWAY_COMMON_PKGS[@]}" "${_SWAY_EXTRA_PKGS[@]}")
    fi

    pkgs+=("${_CLI_PKGS[@]}" "${_SECURITY_PKGS[@]}")

    if [[ "$install_rocm" == "true" ]]; then
        pkgs+=("${_ROCM_PKGS[@]}")
    fi

    printf '%s\n' "${pkgs[@]}"
}

_check_missing_pkgs() {
    local missing=()
    while IFS= read -r pkg; do
        rpm -q "$pkg" &>/dev/null || missing+=("$pkg")
    done
    printf '%s\n' "${missing[@]}"
}

# ---------------------------------------------------------------------------
# Flag parsing helper
# ---------------------------------------------------------------------------

_packages_parse_flags() {
    _PKG_INSTALL_ROCM=false
    _PKG_SWAY_SPIN="$(_read_mode)"
    local arg
    for arg in "$@"; do
        case "$arg" in
            --rocm)      _PKG_INSTALL_ROCM=true ;;
            --sway-spin) _PKG_SWAY_SPIN=true ;;
            --kde-spin)  _PKG_SWAY_SPIN=false ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Module contract
# ---------------------------------------------------------------------------

packages::check() {
    _packages_parse_flags "$@"

    # Check RPM Fusion
    if ! rpm -q rpmfusion-free-release &>/dev/null; then
        return 0
    fi

    # Check codec swaps
    if rpm -q ffmpeg-free &>/dev/null && ! rpm -q ffmpeg &>/dev/null; then
        return 0
    fi
    if rpm -q mesa-va-drivers &>/dev/null && ! rpm -q mesa-va-drivers-freeworld &>/dev/null; then
        return 0
    fi

    # Check packages
    local missing
    missing=$(_build_pkg_list "$_PKG_SWAY_SPIN" "$_PKG_INSTALL_ROCM" | _check_missing_pkgs)
    if [[ -n "$missing" ]]; then
        return 0
    fi

    return 1
}

packages::preview() {
    _packages_parse_flags "$@"
    info "[packages] Preview:"

    echo "  Mode: Sway Spin=$_PKG_SWAY_SPIN  ROCm=$_PKG_INSTALL_ROCM"
    echo ""

    # Repos
    if ! rpm -q rpmfusion-free-release &>/dev/null; then
        echo "  Repos to configure:"
        echo "    RPM Fusion (free + nonfree)"
    fi
    if ! flatpak remote-list --user 2>/dev/null | grep -q flathub; then
        echo "    Flathub"
    fi
    if [[ "$_PKG_INSTALL_ROCM" == "true" ]]; then
        if [[ ! -f /etc/yum.repos.d/amdgpu.repo ]]; then
            echo "    AMD GPU + ROCm repos"
        fi
    fi
    echo ""

    # Codec swaps
    local swaps=()
    if rpm -q ffmpeg-free &>/dev/null && ! rpm -q ffmpeg &>/dev/null; then
        swaps+=("ffmpeg-free → ffmpeg")
    fi
    if rpm -q mesa-va-drivers &>/dev/null && ! rpm -q mesa-va-drivers-freeworld &>/dev/null; then
        swaps+=("mesa-va-drivers → mesa-va-drivers-freeworld")
    fi
    if [[ ${#swaps[@]} -gt 0 ]]; then
        echo "  Codec swaps:"
        for s in "${swaps[@]}"; do echo "    $s"; done
        echo ""
    fi

    # Missing packages by category
    local missing
    missing=$(_build_pkg_list "$_PKG_SWAY_SPIN" "$_PKG_INSTALL_ROCM" | _check_missing_pkgs)
    if [[ -n "$missing" ]]; then
        echo "  Packages to install:"
        echo "$missing" | sed 's/^/    /'
    else
        echo "  All packages already installed."
    fi
}

packages::apply() {
    _packages_parse_flags "$@"
    preflight_checks

    # System update
    info "Updating system packages..."
    sudo dnf update -y
    pkg_install dnf-plugins-core
    ok "System updated"

    # RPM Fusion
    info "Configuring RPM Fusion repositories..."
    local fedora_version
    fedora_version=$(rpm -E %fedora)

    if ! rpm -q rpmfusion-free-release &>/dev/null; then
        sudo dnf install -y \
            "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_version}.noarch.rpm" \
            "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_version}.noarch.rpm"
    fi

    sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1

    # Codec swaps
    if rpm -q ffmpeg-free &>/dev/null && ! rpm -q ffmpeg &>/dev/null; then
        sudo dnf swap ffmpeg-free ffmpeg --allowerasing -y
    fi
    if rpm -q mesa-va-drivers &>/dev/null && ! rpm -q mesa-va-drivers-freeworld &>/dev/null; then
        sudo dnf swap mesa-va-drivers mesa-va-drivers-freeworld --allowerasing -y
    fi
    ok "RPM Fusion + multimedia configured"

    # Flathub
    info "Ensuring Flathub is configured..."
    pkg_install flatpak
    flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    ok "Flathub ready"

    # Sway + Wayland
    if [[ "$_PKG_SWAY_SPIN" == "true" ]]; then
        info "Installing Sway extras (beyond Sway Spin defaults)..."
        pkg_install "${_SWAY_COMMON_PKGS[@]}"
        ok "Sway extras installed"
    else
        info "Installing Sway and Wayland tools..."
        pkg_install "${_SWAY_COMMON_PKGS[@]}" "${_SWAY_EXTRA_PKGS[@]}"
        ok "Sway stack installed"
    fi

    # CLI tools
    info "Installing essential CLI utilities..."
    pkg_install "${_CLI_PKGS[@]}"
    ok "CLI tools installed"

    # Security
    info "Installing Yubikey tooling..."
    pkg_install "${_SECURITY_PKGS[@]}"
    mkdir -p "$HOME/.config/Yubico"
    ok "Yubikey tools installed"

    # ROCm
    if [[ "$_PKG_INSTALL_ROCM" == "true" ]]; then
        # Check GPU presence (reuse detection from system module)
        if ! lspci 2>/dev/null | grep -qi 'VGA.*AMD.*Navi\|VGA.*AMD.*RDNA'; then
            warn "--rocm requested but no discrete AMD GPU detected — skipping ROCm install"
        else
            info "Installing ROCm stack..."
            local rocm_rhel_ver="${ROCM_RHEL_VER:-9.5}"
            if [[ ! -f /etc/yum.repos.d/amdgpu.repo ]]; then
                sudo tee /etc/yum.repos.d/amdgpu.repo > /dev/null <<AMDGPU
[amdgpu]
name=amdgpu
baseurl=https://repo.radeon.com/amdgpu/latest/rhel/${rocm_rhel_ver}/main/x86_64/
enabled=1
gpgcheck=1
gpgkey=https://repo.radeon.com/rocm/rocm.gpg.key
AMDGPU
                sudo tee /etc/yum.repos.d/rocm.repo > /dev/null <<ROCM
[rocm]
name=ROCm
baseurl=https://repo.radeon.com/rocm/rhel9/${rocm_rhel_ver}/main
enabled=1
gpgcheck=1
gpgkey=https://repo.radeon.com/rocm/rocm.gpg.key
ROCM
                sudo chmod 644 /etc/yum.repos.d/amdgpu.repo /etc/yum.repos.d/rocm.repo
            fi

            pkg_install "${_ROCM_PKGS[@]}"
            ok "ROCm stack installed"
        fi
    fi
}

packages::status() {
    local rpm_count=0 total_leaves=0
    if [[ -f "$PKG_MANIFEST" ]]; then
        rpm_count=$(wc -l < "$PKG_MANIFEST")
    fi
    total_leaves=$(dnf5 leaves 2>/dev/null | grep -c '^\- ' || echo 0)
    echo "packages: ${rpm_count} managed, ${total_leaves} total leaves"
}
