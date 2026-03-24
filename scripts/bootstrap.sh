#!/bin/bash

# Fedora Bootstrap Script
# =======================
# Target: AMD GPU, Sway/Wayland, DevOps Tooling
# Machines: Home desktop, work laptop, personal laptop
# System repos, packages, and system-level config only.
# User-level configs (sway, waybar, dotfiles) are handled by dotfiles.sh.
#
# Usage:
#   ./scripts/bootstrap.sh                          # prints usage
#   ./scripts/bootstrap.sh start                    # auto-detects Sway Spin vs KDE Spin
#   ./scripts/bootstrap.sh start --sway-spin        # force Sway Spin mode
#   ./scripts/bootstrap.sh start --sway-spin --rocm # Sway Spin + ROCm

set -euo pipefail

# Global cleanup — temp files register here; EXIT trap cleans them all.
_cleanup_files=()
_cleanup() { rm -rf "${_cleanup_files[@]}" 2>/dev/null || true; }
trap _cleanup EXIT

# shellcheck source=scripts/lib/common.sh
source "$(dirname "$0")/lib/common.sh"

# Source user env (gitignored), fall back to sample
if [[ -f "$(dirname "$0")/env" ]]; then
    # shellcheck source=scripts/env
    source "$(dirname "$0")/env"
else
    # shellcheck source=scripts/env-sample
    source "$(dirname "$0")/env-sample"
fi

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $(basename "$0") start [OPTIONS]

Bootstrap a Fedora system with Sway/Wayland, DevOps tooling, and optionally ROCm.

Options:
  --sway-spin       Force Sway Spin mode (skip core Sway packages already in the spin)
  --kde-spin        Force KDE Spin mode (install full Sway stack)
  --rocm            Install ROCm stack for AMD GPU compute (requires discrete AMD GPU)
  -h, --help        Show this help message and exit

Environment variables:
  K8S_VERSION   Kubernetes repo channel (default: v1.34)

Examples:
  $(basename "$0") start                        Auto-detect mode, skip ROCm
  $(basename "$0") start --sway-spin            Sway Spin mode
  $(basename "$0") start --rocm                 Auto-detect mode + install ROCm
  $(basename "$0") start --kde-spin --rocm      KDE Spin + ROCm
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

# Version pins — override via environment if needed
K8S_VERSION="${K8S_VERSION:-v1.34}"   # Kubernetes repo channel

INSTALL_ROCM=false
_force_mode=""

# Require "start" subcommand; no args or -h/--help prints usage
if [[ $# -eq 0 ]]; then
    usage
fi
case "$1" in
    start)      shift ;;
    -h|--help)  usage ;;
    *)
        echo "ERROR: Unknown command: $1" >&2
        echo "Run '$(basename "$0") --help' for usage." >&2
        exit 1
        ;;
esac

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sway-spin)    _force_mode="sway-spin";  shift ;;
        --kde-spin)     _force_mode="kde-spin";    shift ;;
        --rocm)         INSTALL_ROCM=true;         shift ;;
        -h|--help)      usage ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            echo "Run '$(basename "$0") --help' for usage." >&2
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Mode detection: Sway Spin ships sway pre-installed; base Fedora does not.
# The detected mode is persisted to a state file so re-runs use the same mode
# (after base Fedora installs sway, auto-detection alone would flip to Sway
# Spin mode and change the shell environment).
# Override with --sway-spin / --kde-spin flag if auto-detection doesn't fit.
# ---------------------------------------------------------------------------
_MODE_FILE="$HOME/.config/shell/.bootstrap-mode"
SWAY_SPIN=false
if [[ "$_force_mode" == "sway-spin" ]]; then
    SWAY_SPIN=true
elif [[ "$_force_mode" == "kde-spin" ]]; then
    SWAY_SPIN=false
elif [[ -f "$_MODE_FILE" ]] && grep -qxE 'true|false' "$_MODE_FILE"; then
    # Re-run: use the mode from the first run
    SWAY_SPIN=$(cat "$_MODE_FILE")
elif rpm -q sway &>/dev/null; then
    SWAY_SPIN=true
fi
mkdir -p "$(dirname "$_MODE_FILE")"
echo "$SWAY_SPIN" > "$_MODE_FILE"

if [ "$SWAY_SPIN" = true ]; then
    init_logging "bootstrap-sway-spin"
    info "Mode: Sway Spin (core Sway packages assumed pre-installed)"
else
    init_logging "bootstrap"
    info "Mode: Base Fedora (full Sway stack will be installed)"
fi

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

preflight_checks

# ---------------------------------------------------------------------------
# Machine detection (expand as needed)
# ---------------------------------------------------------------------------

HAS_DISCRETE_AMD_GPU=false

if lspci 2>/dev/null | grep -qi 'VGA.*AMD.*Navi\|VGA.*AMD.*RDNA'; then
    HAS_DISCRETE_AMD_GPU=true
fi

# ---------------------------------------------------------------------------
# Hostname — read from scripts/env
# ---------------------------------------------------------------------------
_target_hostname="$HOSTNAME"

if [[ "$(hostname -s)" != "$_target_hostname" ]]; then
    sudo hostnamectl set-hostname "$_target_hostname"
    ok "Hostname set to $_target_hostname"
else
    ok "Hostname already set to $_target_hostname"
fi

info "Host: $_target_hostname | Discrete AMD GPU detected: $HAS_DISCRETE_AMD_GPU"

# ---------------------------------------------------------------------------
# 1. System Update
# ---------------------------------------------------------------------------

info "Updating system packages..."
sudo dnf update -y
sudo dnf install -y dnf-plugins-core
ok "System updated"

# ---------------------------------------------------------------------------
# 2. RPM Fusion + Multimedia Codecs
# ---------------------------------------------------------------------------

info "Configuring RPM Fusion repositories..."

FEDORA_VERSION=$(rpm -E %fedora)

if ! rpm -q rpmfusion-free-release &>/dev/null; then
    sudo dnf install -y \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm"
fi

sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1

if rpm -q ffmpeg-free &>/dev/null && ! rpm -q ffmpeg &>/dev/null; then
    sudo dnf swap ffmpeg-free ffmpeg --allowerasing -y
fi

# AMD Mesa freeworld drivers (hardware video decode via VA-API)
if rpm -q mesa-va-drivers &>/dev/null && ! rpm -q mesa-va-drivers-freeworld &>/dev/null; then
    sudo dnf swap mesa-va-drivers mesa-va-drivers-freeworld --allowerasing -y
fi

ok "RPM Fusion + multimedia configured"

# ---------------------------------------------------------------------------
# 3. Flatpak / Flathub
# ---------------------------------------------------------------------------

info "Ensuring Flathub is configured..."
sudo dnf install -y flatpak
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
ok "Flathub ready"

# ---------------------------------------------------------------------------
# 4. Sway + Wayland Tooling
# ---------------------------------------------------------------------------

# Packages needed on both base Fedora and Sway Spin (sorted alphabetically)
SWAY_COMMON_PKGS=(
    bemenu
    bluez
    google-roboto-mono-fonts
    kitty
    libnotify
    mate-polkit
    mesa-demos
    network-manager-applet
    pavucontrol
    plasma-integration
    qt5ct
    qt6ct
    tuned
    tuned-ppd
    vulkan-tools
    bat
    vim
)

if [ "$SWAY_SPIN" = true ]; then
    # Sway Spin ships: sway, waybar, foot, mako, grim, slurp, wl-clipboard,
    # swaylock, swayidle, swaybg, kanshi, xdg-desktop-portal-wlr, polkit-gnome.
    # Only install what's missing from the spin.
    # mate-polkit (in SWAY_COMMON_PKGS) replaces polkit-gnome for USB/device auth prompts.
    info "Installing Sway extras (beyond Sway Spin defaults)..."
    sudo dnf install -y "${SWAY_COMMON_PKGS[@]}"
    ok "Sway extras installed"
else
    info "Installing Sway and Wayland tools..."
    # Core Sway/Wayland stack (not present on base Fedora)
    # xdg-desktop-portal-wlr works alongside xdg-desktop-portal-kde;
    # the active portal is selected at runtime based on the running session.
    sudo dnf install -y \
        "${SWAY_COMMON_PKGS[@]}" \
        grim \
        kanshi \
        mako \
        slurp \
        sway \
        swaybg \
        swayidle \
        swaylock \
        waybar \
        wl-clipboard \
        xdg-desktop-portal-wlr
    ok "Sway stack installed"
fi

sudo systemctl enable --now bluetooth
sudo systemctl enable --now tuned

# --- Firewall ---
info "Enabling firewall..."
sudo systemctl enable --now firewalld
ok "firewalld enabled (default zone: $(sudo firewall-cmd --get-default-zone))"

# ---------------------------------------------------------------------------
# 5. DevOps Stack
# ---------------------------------------------------------------------------

info "Installing DevOps tooling..."

# HashiCorp repo (Terraform, Packer, etc.)
if [ ! -f /etc/yum.repos.d/hashicorp.repo ]; then
    sudo dnf config-manager addrepo --from-repofile=https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
fi

# Kubernetes repo (kubectl)
if [ ! -f /etc/yum.repos.d/kubernetes.repo ]; then
    cat <<KREPO | sudo tee /etc/yum.repos.d/kubernetes.repo > /dev/null
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/rpm/repodata/repomd.xml.key
KREPO
    sudo chmod 644 /etc/yum.repos.d/kubernetes.repo
fi

sudo dnf install -y \
    ansible \
    helm \
    jq \
    kind \
    kubectl \
    podman \
    podman-compose \
    terraform \
    yq

ok "DevOps stack installed"

# ---------------------------------------------------------------------------
# 6. ROCm / AI Workloads
# ---------------------------------------------------------------------------
# GPU group membership is always configured when a discrete AMD GPU is present.
# The full ROCm stack (runtime, HIP, libraries) is installed only with --rocm.

if [ "$HAS_DISCRETE_AMD_GPU" = true ]; then
    info "Discrete AMD GPU found — adding user to render/video groups"
    sudo usermod -aG video,render "$(id -un)"
    ok "GPU groups configured"
else
    info "No discrete AMD GPU detected — skipping GPU group setup"
fi

if [ "$INSTALL_ROCM" = true ]; then
    if [ "$HAS_DISCRETE_AMD_GPU" = false ]; then
        warn "--rocm requested but no discrete AMD GPU detected — skipping ROCm install"
    else
        info "Installing ROCm stack..."

        # AMD ROCm repo (provides rocm-hip-runtime, rocminfo, etc.)
        if [ ! -f /etc/yum.repos.d/amdgpu.repo ]; then
            sudo tee /etc/yum.repos.d/amdgpu.repo > /dev/null <<AMDGPU
[amdgpu]
name=amdgpu
baseurl=https://repo.radeon.com/amdgpu/latest/rhel/\$releasever/main/x86_64/
enabled=1
gpgcheck=1
gpgkey=https://repo.radeon.com/rocm/rocm.gpg.key
AMDGPU
            sudo tee /etc/yum.repos.d/rocm.repo > /dev/null <<ROCM
[rocm]
name=ROCm
baseurl=https://repo.radeon.com/rocm/rhel9/\$releasever/main
enabled=1
gpgcheck=1
gpgkey=https://repo.radeon.com/rocm/rocm.gpg.key
ROCM
            sudo chmod 644 /etc/yum.repos.d/amdgpu.repo /etc/yum.repos.d/rocm.repo
        fi

        sudo dnf install -y \
            rocm-hip-runtime \
            rocm-opencl-runtime \
            rocm-smi-lib \
            rocminfo

        ok "ROCm stack installed"
        info "Verify with: rocminfo | head -30"
    fi
fi

# ---------------------------------------------------------------------------
# 7. Security (Yubikey tooling)
# ---------------------------------------------------------------------------

info "Installing Yubikey tooling..."
sudo dnf install -y pam-u2f yubikey-manager
mkdir -p "$HOME/.config/Yubico"
ok "Yubikey tools installed"
# PAM integration (authselect / pam.d edits) is deferred to dotfiles.sh.

# ---------------------------------------------------------------------------
# 8. Essential CLI Tools
# ---------------------------------------------------------------------------

info "Installing essential CLI utilities..."
sudo dnf install -y \
    btop \
    curl \
    fd-find \
    fzf \
    git \
    htop \
    p7zip \
    ripgrep \
    tmux \
    unzip \
    wget
ok "CLI tools installed"

# ---------------------------------------------------------------------------
# 9. Shell Environment (idempotent)
# ---------------------------------------------------------------------------

info "Configuring shell environment..."

ensure_bashrc_source

# Write bootstrap-env.sh only when the content has changed.
_env_tmp=$(mktemp)
_cleanup_files+=("$_env_tmp")
cat <<'ENVEOF' > "$_env_tmp"
# Managed by scripts/bootstrap.sh
# Do not edit manually; changes will be overwritten on next bootstrap run.
# Put personal overrides in ~/.bashrc or a separate sourced file.

alias docker=podman
export KIND_EXPERIMENTAL_PROVIDER=podman
export QT_QPA_PLATFORMTHEME=kde
export QT_STYLE_OVERRIDE=Breeze
ENVEOF

# kde-settings ships /etc/profile.d/kde-openssh-askpass.sh which sets
# SSH_ASKPASS=/usr/bin/ksshaskpass, but ksshaskpass is not installed.
# This breaks git HTTPS credential prompts. Unset unconditionally.
echo "unset SSH_ASKPASS" >> "$_env_tmp"

_env_file="$HOME/.config/shell/bootstrap-env.sh"
if ! cmp -s "$_env_tmp" "$_env_file" 2>/dev/null; then
    mv "$_env_tmp" "$_env_file"
    ok "Shell env configured"
else
    rm -f "$_env_tmp"
    ok "Shell env already up to date"
fi

# ---------------------------------------------------------------------------
# 10. Keyboard Layout (system-wide default)
# ---------------------------------------------------------------------------

info "Setting default keyboard layout to FR..."
sudo localectl set-x11-keymap fr
ok "Keyboard layout set to FR"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "============================================"
echo "  Bootstrap complete!"
echo "  Log: $LOG"
echo "============================================"
echo ""
echo "Next steps:"
echo "  1. REBOOT to apply group changes and keyboard layout"
echo "  2. Register Yubikey:  pamu2fcfg > ~/.config/Yubico/u2f_keys"
echo "  3. Run theme.sh:     scripts/theme.sh start   (icon theme + SDDM greeter)"
echo "  4. Run dotfiles.sh:  scripts/dotfiles.sh       (sway, waybar, user configs)"
if [ "$HAS_DISCRETE_AMD_GPU" = true ] && [ "$INSTALL_ROCM" = false ]; then
    echo "  5. ROCm: re-run with --rocm to install AMD compute stack"
fi
echo ""
