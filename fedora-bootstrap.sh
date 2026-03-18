#!/bin/bash

# Fedora 43+ Workstation Bootstrap Script
# ========================================
# Target: AMD GPU, Sway/Wayland, DevOps Tooling
# Machines: Home desktop, work laptop, personal laptop
# Phase 1: System repos, packages, and system-level config only.
#          User-level configs (sway, waybar, dotfiles) are handled in Phase 2.

set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

# Version pins — override via environment if needed
K8S_VERSION="${K8S_VERSION:-v1.32}"   # Kubernetes repo channel

init_logging "fedora-bootstrap"

# ---------------------------------------------------------------------------
# Helpers (specific to this script)
# ---------------------------------------------------------------------------

ensure_bashrc_source() {
    # Source a dedicated env file from .bashrc, idempotently.
    local env_file="$HOME/.config/shell/bootstrap-env.sh"
    local source_line="[[ -f \"$env_file\" ]] && source \"$env_file\""
    mkdir -p "$(dirname "$env_file")"
    grep -qF "bootstrap-env.sh" "$HOME/.bashrc" 2>/dev/null || \
        echo "$source_line" >> "$HOME/.bashrc"
}

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

info "Installing Sway and Wayland tools..."
# xdg-desktop-portal-wlr works alongside xdg-desktop-portal-kde (shipped by KDE spin);
# the active portal is selected at runtime based on the running desktop session.
sudo dnf install -y \
    sway \
    xdg-desktop-portal-wlr \
    waybar \
    kanshi \
    swaybg \
    swaylock \
    swayidle \
    grim \
    slurp \
    wl-clipboard \
    mako \
    mesa-demos \
    vulkan-tools \
    kitty \
    bemenu \
    libnotify \
    pavucontrol \
    network-manager-applet \
    bluez \
    mate-polkit
ok "Sway stack installed"

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
    terraform \
    kubectl \
    helm \
    podman \
    podman-compose \
    kind \
    jq \
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
    git \
    curl \
    wget \
    htop \
    btop \
    ripgrep \
    fd-find \
    fzf \
    tmux \
    unzip \
    p7zip
ok "CLI tools installed"

# ---------------------------------------------------------------------------
# 9. Shell Environment (idempotent)
# ---------------------------------------------------------------------------

info "Configuring shell environment..."

ensure_bashrc_source

# Write bootstrap-env.sh only when the content has changed.
_env_tmp=$(mktemp)
cat <<'ENVEOF' > "$_env_tmp"
# Managed by fedora-bootstrap.sh — Phase 1
# Do not edit manually; changes will be overwritten on next bootstrap run.
# Put personal overrides in ~/.bashrc or a separate sourced file.

alias docker=podman
export KIND_EXPERIMENTAL_PROVIDER=podman
unset SSH_ASKPASS
ENVEOF

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
echo "  3. Phase 2: dotfile sync + user configs (sway, waybar, etc.)"
if [ "$HAS_DISCRETE_AMD_GPU" = true ]; then
    echo "  4. ROCm setup (dedicated process — home desktop only)"
fi
echo ""
