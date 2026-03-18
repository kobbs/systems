#!/bin/bash

# Fedora Application Stack — Phase 3
# ====================================
# Installs user-facing applications after Phase 1 (system bootstrap) and
# Phase 2 (dotfiles). Run as a regular user (not root).
#
# RPM vs Flatpak rationale is documented per section below.

set -euo pipefail

LOG="/tmp/apps-install-$(date +%s).log"
exec > >(tee -a "$LOG") 2>&1

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info() { echo -e "\n\033[1;34m→ $*\033[0m"; }
ok()   { echo -e "\033[1;32m✓ $*\033[0m"; }
warn() { echo -e "\033[1;33m⚠ $*\033[0m"; }

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

if [[ $EUID -eq 0 ]]; then
    echo "ERROR: Run as a regular user, not root. The script uses sudo internally." >&2
    exit 1
fi

if ! grep -q '^ID=fedora$' /etc/os-release 2>/dev/null; then
    echo "ERROR: This script targets Fedora. Detected OS is not Fedora." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 1. Browsers
# ---------------------------------------------------------------------------
# Firefox: RPM — standard Fedora package; Wayland env var set system-wide.
# Brave:   RPM from vendor repo — vendor recommends RPM; Flatpak disables
#          parts of Chromium's internal sandbox.

info "Installing browsers..."

sudo dnf install -y firefox

# Enable native Wayland rendering for Firefox in Sway
if ! grep -q 'MOZ_ENABLE_WAYLAND' /etc/environment 2>/dev/null; then
    echo 'MOZ_ENABLE_WAYLAND=1' | sudo tee -a /etc/environment > /dev/null
    ok "MOZ_ENABLE_WAYLAND=1 added to /etc/environment"
else
    ok "MOZ_ENABLE_WAYLAND already set in /etc/environment"
fi

# Brave — official vendor RPM repo
if ! dnf repolist --enabled | grep -q brave-browser; then
    sudo dnf config-manager addrepo \
        --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
fi
sudo dnf install -y brave-browser

ok "Browsers installed"

# ---------------------------------------------------------------------------
# 2. Audio
# ---------------------------------------------------------------------------
# PipeWire is pre-installed on Fedora. pavucontrol is in Phase 1.
# EasyEffects: Flatpak — RPM version has PipeWire context connection failures
#              reported on Fedora 41+.

info "Ensuring Flathub user remote is configured..."
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
ok "Flathub user remote ready"

info "Installing EasyEffects (Flatpak)..."
flatpak install --user -y flathub com.github.wwmm.easyeffects
ok "EasyEffects installed"

# ---------------------------------------------------------------------------
# 3. Mesa / AMD 3D Acceleration
# ---------------------------------------------------------------------------
# mesa-va-drivers-freeworld swap is handled in Phase 1.
# These packages add Vulkan, VDPAU, and VA-API verification tooling.

info "Installing Mesa/AMD acceleration packages..."
sudo dnf install -y \
    mesa-vulkan-drivers \
    libva-utils \
    mesa-vdpau-drivers-freeworld
ok "Mesa acceleration packages installed"

# ---------------------------------------------------------------------------
# 4. Communication — Flatpak
# ---------------------------------------------------------------------------
# Flatpak chosen for sandbox isolation (sensitive communications).
# Signal: no official Fedora RPM exists; Flathub is the standard path.
# Slack:  Flatpak provides better update cadence and sandboxing than the
#         unofficial RPM options.

info "Installing communication apps (Flatpak)..."
flatpak install --user -y flathub com.slack.Slack
flatpak install --user -y flathub org.signal.Signal
ok "Slack and Signal installed"

# ---------------------------------------------------------------------------
# 5. Nextcloud Desktop Client
# ---------------------------------------------------------------------------
# RPM — integrates cleanly with system file manager and tray.

info "Installing Nextcloud desktop client..."
sudo dnf install -y nextcloud-client
ok "Nextcloud client installed"

# ---------------------------------------------------------------------------
# 6. ProtonVPN
# ---------------------------------------------------------------------------
# RPM from official ProtonVPN repo — Flatpak version has known Wayland GUI
# rendering failures. NetworkManager integration requires native install.
# Launched manually as a tray app; no autostart needed.

info "Installing ProtonVPN..."
FEDORA_VER=$(rpm -E %fedora)
PROTON_BASE="https://repo.protonvpn.com"
PROTON_RPM="protonvpn-stable-release-1.0.1-2.noarch.rpm"

# ProtonVPN may not yet publish a repo for the current Fedora version.
# Walk backwards until we find one that exists (try up to 3 versions back).
PROTON_URL=""
for ver in "$FEDORA_VER" $(( FEDORA_VER - 1 )) $(( FEDORA_VER - 2 )); do
    candidate="${PROTON_BASE}/fedora-${ver}-stable/protonvpn-stable-release/${PROTON_RPM}"
    if curl -sf --head "$candidate" -o /dev/null; then
        PROTON_URL="$candidate"
        [ "$ver" -ne "$FEDORA_VER" ] && warn "ProtonVPN repo not found for Fedora ${FEDORA_VER}, using Fedora ${ver} repo"
        break
    fi
done

if [ -z "$PROTON_URL" ]; then
    warn "Could not find a ProtonVPN repo RPM for Fedora ${FEDORA_VER} or the two previous releases. Skipping."
else
    sudo dnf install -y "$PROTON_URL"
    sudo dnf install -y proton-vpn-gtk-app
    ok "ProtonVPN installed"
fi

# ---------------------------------------------------------------------------
# 7. KeePassXC
# ---------------------------------------------------------------------------
# RPM — browser integration (native messaging) works between RPM KeePassXC
# and RPM browsers (Brave, Firefox). Flatpak-to-RPM native messaging works,
# but keeping all three as RPM is simplest.

info "Installing KeePassXC..."
sudo dnf install -y keepassxc
ok "KeePassXC installed"

# ---------------------------------------------------------------------------
# 8. KVM / virt-manager
# ---------------------------------------------------------------------------

info "Installing KVM / virt-manager..."
sudo dnf group install -y "Virtualization"
sudo usermod -aG libvirt "$USER"
sudo systemctl enable --now libvirtd
ok "KVM stack installed; user added to libvirt group"

# ---------------------------------------------------------------------------
# 9. Podman
# ---------------------------------------------------------------------------
# Podman is already installed in Phase 1.

info "Podman check..."
if command -v podman &>/dev/null; then
    ok "Podman already installed (Phase 1): $(podman --version)"
else
    warn "Podman not found — was Phase 1 run? Install with: sudo dnf install -y podman"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "============================================"
echo "  App stack install complete!"
echo "  Log: $LOG"
echo "============================================"
echo ""
echo "Verification checklist:"
echo "  1. firefox / brave-browser — launch and confirm Wayland (check title bar)"
echo "  2. vainfo — shows AMD VAAPI decoder entries"
echo "  3. vulkaninfo | grep driverName — shows radv or AMD driver"
echo "  4. EasyEffects — opens and connects to PipeWire"
echo "  5. Slack / Signal — open from app launcher"
echo "  6. Nextcloud — tray icon appears after launch"
echo "  7. proton-vpn-gtk-app — launches"
echo "  8. KeePassXC — browser plugin connects from Brave/Firefox"
echo "  9. virt-manager — opens; virsh list --all works without sudo (re-login first)"
echo " 10. podman run hello-world — succeeds"
echo ""
echo "NOTE: Log out and back in for libvirt group membership to take effect."
echo ""
