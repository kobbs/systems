#!/bin/bash

# Fedora Bootstrap Script
# =======================
# Target: AMD GPU, Sway/Wayland, DevOps Tooling
# Machines: Home desktop, work laptop, personal laptop
# Phase 1: System repos, packages, and system-level config only.
#          User-level configs (sway, waybar, dotfiles) are handled in Phase 2.
#
# Usage:
#   ./scripts/bootstrap.sh              # auto-detects Sway Spin vs base Fedora
#   ./scripts/bootstrap.sh --sway-spin  # force Sway Spin mode (skip core Sway packages)

set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "$0")/lib/common.sh"

# Version pins — override via environment if needed
K8S_VERSION="${K8S_VERSION:-v1.32}"   # Kubernetes repo channel

# ---------------------------------------------------------------------------
# Mode detection: Sway Spin ships sway pre-installed; base Fedora does not.
# The detected mode is persisted to a state file so re-runs use the same mode
# (after base Fedora installs sway, auto-detection alone would flip to Sway
# Spin mode and change the shell environment).
# Override with --sway-spin / --base flag if auto-detection doesn't fit.
# ---------------------------------------------------------------------------
_MODE_FILE="$HOME/.config/shell/.bootstrap-mode"
SWAY_SPIN=false
if [[ "${1:-}" == "--sway-spin" ]]; then
    SWAY_SPIN=true
elif [[ "${1:-}" == "--base" ]]; then
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

HOSTNAME=$(hostname -s)
HAS_DISCRETE_AMD_GPU=false

if lspci 2>/dev/null | grep -qi 'VGA.*AMD.*Navi\|VGA.*AMD.*RDNA'; then
    HAS_DISCRETE_AMD_GPU=true
fi

info "Host: $HOSTNAME | Discrete AMD GPU detected: $HAS_DISCRETE_AMD_GPU"

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
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
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
    mesa-demos
    network-manager-applet
    pavucontrol
    qt5ct
    qt6ct
    vulkan-tools
)

if [ "$SWAY_SPIN" = true ]; then
    # Sway Spin ships: sway, waybar, foot, mako, grim, slurp, wl-clipboard,
    # swaylock, swayidle, swaybg, kanshi, xdg-desktop-portal-wlr, polkit-gnome.
    # Only install what's missing from the spin.
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
        mate-polkit \
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

# ---------------------------------------------------------------------------
# 5. DevOps Stack
# ---------------------------------------------------------------------------

info "Installing DevOps tooling..."

# HashiCorp repo (Terraform, Packer, etc.)
if ! dnf repolist --enabled | grep -q hashicorp; then
    sudo dnf config-manager addrepo --from-repofile=https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
fi

# Kubernetes repo (kubectl)
if ! dnf repolist --enabled | grep -q kubernetes; then
    cat <<KREPO | sudo tee /etc/yum.repos.d/kubernetes.repo > /dev/null
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/rpm/repodata/repomd.xml.key
KREPO
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
# NOTE: ROCm setup is intentionally excluded from this bootstrap.
# Only the home desktop has a capable discrete AMD GPU.
# ROCm on Fedora deserves its own dedicated setup:
#   - AMD's own RPM repo vs Fedora-packaged ROCm
#   - Confirm GPU is in the ROCm support matrix (RDNA2+/gfx1030+)
#   - Choose inference runtime (ollama, llama.cpp+hipBLAS, vllm, etc.)
#   - PyTorch ROCm if doing any training/fine-tuning
#   - Potential kernel module (amdgpu) config for large VRAM allocations
#
# For now, just ensure the user is in the right groups if a discrete GPU
# is present, so the device nodes are accessible when ROCm is installed later.

if [ "$HAS_DISCRETE_AMD_GPU" = true ]; then
    info "Discrete AMD GPU found — adding user to render/video groups (for future ROCm)"
    sudo usermod -aG video,render "$(id -un)"
    ok "GPU groups configured"
else
    info "No discrete AMD GPU detected — skipping GPU group setup"
fi

# ---------------------------------------------------------------------------
# 7. Security (Yubikey tooling)
# ---------------------------------------------------------------------------

info "Installing Yubikey tooling..."
sudo dnf install -y pam-u2f yubikey-manager
mkdir -p "$HOME/.config/Yubico"
ok "Yubikey tools installed"
# PAM integration (authselect / pam.d edits) is deferred to Phase 2 / dotfiles.

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
trap 'rm -f "$_env_tmp"' EXIT
cat <<'ENVEOF' > "$_env_tmp"
# Managed by scripts/bootstrap.sh — Phase 1
# Do not edit manually; changes will be overwritten on next bootstrap run.
# Put personal overrides in ~/.bashrc or a separate sourced file.

alias docker=podman
export KIND_EXPERIMENTAL_PROVIDER=podman
export QT_QPA_PLATFORMTHEME=kde
export QT_STYLE_OVERRIDE=Breeze
ENVEOF

# Base Fedora may have ksshaskpass from KDE — suppress its SSH popup
if [ "$SWAY_SPIN" = false ]; then
    echo "unset SSH_ASKPASS" >> "$_env_tmp"
fi

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
# 11. SDDM greeter — solid dark background (matches sway's #222222)
# ---------------------------------------------------------------------------
# The Breeze-Fedora theme reads theme.conf.user for per-site overrides.
# This replaces the default Fedora wallpaper with a flat color to match Sway.

SDDM_THEME_DIR="/usr/share/sddm/themes/01-breeze-fedora"
if [ -d "$SDDM_THEME_DIR" ]; then
    info "Configuring SDDM dark background..."
    cat <<'SDDM' | sudo tee "$SDDM_THEME_DIR/theme.conf.user" > /dev/null
[General]
type=color
color=#222222
SDDM
    ok "SDDM background set to #222222"
else
    warn "SDDM theme dir not found ($SDDM_THEME_DIR) — skipping greeter background"
fi

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
echo "  3. Phase 2: dotfile sync + user configs (sway, waybar, etc.)"
if [ "$HAS_DISCRETE_AMD_GPU" = true ]; then
    echo "  4. ROCm setup (dedicated process — home desktop only)"
fi
echo ""
