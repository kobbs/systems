# shellcheck shell=bash
# modules/packages.sh -- System package management module.
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

_packages_build_pkg_list() {
    local pkgs=()

    pkgs+=("dnf-plugins-core")

    if [[ "${PROFILE_PACKAGES_FLATPAK:-true}" == "true" ]]; then
        pkgs+=("flatpak")
    fi

    if [[ "$_PKG_SWAY_SPIN" == "true" ]]; then
        pkgs+=("${_SWAY_COMMON_PKGS[@]}")
    else
        pkgs+=("${_SWAY_COMMON_PKGS[@]}" "${_SWAY_EXTRA_PKGS[@]}")
    fi

    if [[ "${PROFILE_PACKAGES_CLI_TOOLS:-true}" == "true" ]]; then
        pkgs+=("${_CLI_PKGS[@]}")
    fi

    if [[ "${PROFILE_PACKAGES_SECURITY:-true}" == "true" ]]; then
        pkgs+=("${_SECURITY_PKGS[@]}")
    fi

    if [[ "$_PKG_INSTALL_ROCM" == "true" ]]; then
        pkgs+=("${_ROCM_PKGS[@]}")
    fi

    printf '%s\n' "${pkgs[@]}"
}

_packages_check_missing_pkgs() {
    local missing=()
    while IFS= read -r pkg; do
        rpm -q "$pkg" &>/dev/null || missing+=("$pkg")
    done
    printf '%s\n' "${missing[@]}"
}

# ---------------------------------------------------------------------------
# Module contract
# ---------------------------------------------------------------------------

packages::init() {
    detect_mode
    _PKG_SWAY_SPIN="$SWAY_SPIN"
    _PKG_INSTALL_ROCM="${PROFILE_PACKAGES_ROCM:-false}"

    # Validate ROCm against GPU presence
    if [[ "$_PKG_INSTALL_ROCM" == "true" ]]; then
        detect_gpu
        if [[ "$_HAS_DISCRETE_AMD_GPU" != "true" ]]; then
            warn "packages.rocm = true but no discrete AMD GPU detected -- ROCm will be skipped"
            _PKG_INSTALL_ROCM=false
        fi
    fi
}

packages::check() {
    # RPM Fusion
    if [[ "${PROFILE_PACKAGES_RPM_FUSION:-true}" == "true" ]]; then
        if ! rpm -q rpmfusion-free-release &>/dev/null; then
            return 0
        fi
    fi

    # Codec swaps
    if [[ "${PROFILE_PACKAGES_CODEC_SWAPS:-true}" == "true" ]]; then
        if rpm -q ffmpeg-free &>/dev/null && ! rpm -q ffmpeg &>/dev/null; then
            return 0
        fi
        if rpm -q mesa-va-drivers &>/dev/null && ! rpm -q mesa-va-drivers-freeworld &>/dev/null; then
            return 0
        fi
    fi

    # Packages
    local missing
    missing=$(_packages_build_pkg_list | _packages_check_missing_pkgs)
    if [[ -n "$missing" ]]; then
        return 0
    fi

    return 1
}

packages::preview() {
    info "[packages] Preview:"

    echo "  Mode: Sway Spin=$_PKG_SWAY_SPIN  ROCm=$_PKG_INSTALL_ROCM"
    echo "  DNF update: ${PROFILE_PACKAGES_DNF_UPDATE:-true}"
    echo "  RPM Fusion: ${PROFILE_PACKAGES_RPM_FUSION:-true}"
    echo "  Codec swaps: ${PROFILE_PACKAGES_CODEC_SWAPS:-true}"
    echo "  Flatpak: ${PROFILE_PACKAGES_FLATPAK:-true}"
    echo "  CLI tools: ${PROFILE_PACKAGES_CLI_TOOLS:-true}"
    echo "  Security: ${PROFILE_PACKAGES_SECURITY:-true}"
    echo ""

    # Repos
    if [[ "${PROFILE_PACKAGES_RPM_FUSION:-true}" == "true" ]]; then
        if ! rpm -q rpmfusion-free-release &>/dev/null; then
            echo "  Repos to configure:"
            echo "    RPM Fusion (free + nonfree)"
        fi
    fi
    if [[ "${PROFILE_PACKAGES_FLATPAK:-true}" == "true" ]]; then
        if ! flatpak remote-list --user 2>/dev/null | grep -q flathub; then
            echo "    Flathub"
        fi
    fi
    if [[ "$_PKG_INSTALL_ROCM" == "true" ]]; then
        if [[ ! -f /etc/yum.repos.d/amdgpu.repo ]]; then
            echo "    AMD GPU + ROCm repos"
        fi
    fi
    echo ""

    # Codec swaps
    if [[ "${PROFILE_PACKAGES_CODEC_SWAPS:-true}" == "true" ]]; then
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
    fi

    # Missing packages by category
    local missing
    missing=$(_packages_build_pkg_list | _packages_check_missing_pkgs)
    if [[ -n "$missing" ]]; then
        echo "  Packages to install:"
        # shellcheck disable=SC2001  # multiline indent, not a simple substitution
        echo "$missing" | sed 's/^/    /'
    else
        echo "  All packages already installed."
    fi
}

packages::apply() {
    preflight_checks

    # System update
    if [[ "${PROFILE_PACKAGES_DNF_UPDATE:-true}" == "true" ]]; then
        info "Updating system packages..."
        sudo dnf update -y
        ok "System updated"
    else
        info "DNF update: disabled by profile -- skipping"
    fi

    # dnf-plugins-core is always installed (non-optional base dependency)
    pkg_install dnf-plugins-core

    # RPM Fusion
    if [[ "${PROFILE_PACKAGES_RPM_FUSION:-true}" == "true" ]]; then
        info "Configuring RPM Fusion repositories..."
        local fedora_version
        fedora_version=$(rpm -E %fedora)

        if ! rpm -q rpmfusion-free-release &>/dev/null; then
            sudo dnf install -y \
                "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_version}.noarch.rpm" \
                "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_version}.noarch.rpm"
        fi
    else
        info "RPM Fusion: disabled by profile -- skipping"
    fi

    # Cisco OpenH264 + codec swaps
    if [[ "${PROFILE_PACKAGES_CODEC_SWAPS:-true}" == "true" ]]; then
        sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1

        if rpm -q ffmpeg-free &>/dev/null && ! rpm -q ffmpeg &>/dev/null; then
            sudo dnf swap ffmpeg-free ffmpeg --allowerasing -y
        fi
        if rpm -q mesa-va-drivers &>/dev/null && ! rpm -q mesa-va-drivers-freeworld &>/dev/null; then
            sudo dnf swap mesa-va-drivers mesa-va-drivers-freeworld --allowerasing -y
        fi
        ok "Codecs configured"
    else
        info "Codec swaps: disabled by profile -- skipping"
    fi

    # Flathub
    if [[ "${PROFILE_PACKAGES_FLATPAK:-true}" == "true" ]]; then
        info "Ensuring Flathub is configured..."
        pkg_install flatpak
        flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
        ok "Flathub ready"
    else
        info "Flatpak: disabled by profile -- skipping"
    fi

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
    if [[ "${PROFILE_PACKAGES_CLI_TOOLS:-true}" == "true" ]]; then
        info "Installing essential CLI utilities..."
        pkg_install "${_CLI_PKGS[@]}"
        ok "CLI tools installed"
    else
        info "CLI tools: disabled by profile -- skipping"
    fi

    # Security
    if [[ "${PROFILE_PACKAGES_SECURITY:-true}" == "true" ]]; then
        info "Installing Yubikey tooling..."
        pkg_install "${_SECURITY_PKGS[@]}"
        mkdir -p "$HOME/.config/Yubico"
        ok "Yubikey tools installed"
    else
        info "Security packages: disabled by profile -- skipping"
    fi

    # ROCm
    if [[ "$_PKG_INSTALL_ROCM" == "true" ]]; then
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
}

packages::status() {
    local rpm_count=0 total_leaves=0
    if [[ -f "$PKG_MANIFEST" ]]; then
        rpm_count=$(wc -l < "$PKG_MANIFEST")
    fi
    total_leaves=$(dnf5 leaves 2>/dev/null | grep -c '^\- ' || echo 0)
    echo "packages: ${rpm_count} managed, ${total_leaves} total leaves"
}
