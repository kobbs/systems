#!/bin/bash

# Fedora Application Stack
# ========================
# Installs user-facing applications. Run after bootstrap and dotfiles.
# Run as a regular user (not root).
#
# RPM vs Flatpak rationale is documented per section below.

set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "$0")/lib/common.sh"

# Version pins — override via environment if needed
PROTON_RPM="${PROTON_RPM:-protonvpn-stable-release-1.0.1-2.noarch.rpm}"
K8S_VERSION="${K8S_VERSION:-v1.34}"   # Kubernetes repo channel

# ---------------------------------------------------------------------------
# Usage / argument parsing
# ---------------------------------------------------------------------------

usage() {
    cat <<EOF
Usage: $(basename "$0") start [OPTIONS]

Install user-facing applications.

Options:
  --devops      Install DevOps tooling (Terraform, Ansible, Helm, kubectl, …)
  --gtk-apps    Install GTK desktop utilities (Thunar, Evince, GNOME Calculator, …)
  --qt-apps     Install Qt/KDE desktop utilities (Dolphin, Okular, KCalc, …)
  -h, --help    Show this help message and exit

Flags --gtk-apps and --qt-apps are mutually exclusive.
--devops can be combined with either.

Environment variables:
  K8S_VERSION   Kubernetes repo channel (default: v1.34)

Examples:
  $(basename "$0") start                    Install apps (no extras)
  $(basename "$0") start --devops           Install apps + DevOps tooling
  $(basename "$0") start --qt-apps --devops Install apps + Qt utilities + DevOps
EOF
    exit 0
}

DESKTOP_TOOLKIT=""
INSTALL_DEVOPS=false

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
        --devops)   INSTALL_DEVOPS=true; shift ;;
        --gtk-apps)
            [[ -n "$DESKTOP_TOOLKIT" ]] && { echo "ERROR: --gtk-apps and --qt-apps are mutually exclusive." >&2; exit 1; }
            DESKTOP_TOOLKIT="gtk"; shift ;;
        --qt-apps)
            [[ -n "$DESKTOP_TOOLKIT" ]] && { echo "ERROR: --gtk-apps and --qt-apps are mutually exclusive." >&2; exit 1; }
            DESKTOP_TOOLKIT="qt"; shift ;;
        -h|--help)  usage ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            echo "Run '$(basename "$0") --help' for usage." >&2
            exit 1
            ;;
    esac
done

init_logging "apps"

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

preflight_checks
require_cmd flatpak "sudo dnf install -y flatpak"

# ---------------------------------------------------------------------------
# Helpers (specific to this script)
# ---------------------------------------------------------------------------

flatpak_install() {
    flatpak install --user -y flathub "$1"
    mkdir -p "$(dirname "$FLATPAK_MANIFEST")"
    grep -qFx "$1" "$FLATPAK_MANIFEST" 2>/dev/null || echo "$1" >> "$FLATPAK_MANIFEST"
}

# ---------------------------------------------------------------------------
# 1. Browsers
# ---------------------------------------------------------------------------
# Firefox: RPM — standard Fedora package; Wayland env var set system-wide.
# Brave:   RPM from vendor repo — vendor recommends RPM; Flatpak disables
#          parts of Chromium's internal sandbox.

info "Installing browsers..."

pkg_install firefox

# Enable native Wayland rendering for Firefox in Sway.
# grep -xF matches the exact line, preventing false positives on substrings.
if ! grep -xF 'MOZ_ENABLE_WAYLAND=1' /etc/environment 2>/dev/null; then
    echo 'MOZ_ENABLE_WAYLAND=1' | sudo tee -a /etc/environment > /dev/null
    ok "MOZ_ENABLE_WAYLAND=1 added to /etc/environment"
else
    ok "MOZ_ENABLE_WAYLAND already set in /etc/environment"
fi

# Brave — official vendor RPM repo
if [[ ! -f /etc/yum.repos.d/brave-browser.repo ]]; then
    sudo dnf config-manager addrepo \
        --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
fi
pkg_install brave-browser

ok "Browsers installed"

# ---------------------------------------------------------------------------
# 2. Audio
# ---------------------------------------------------------------------------
# PipeWire is pre-installed on Fedora. pavucontrol is in bootstrap.
# EasyEffects: Flatpak — RPM version has PipeWire context connection failures
#              reported on Fedora 41+.

info "Ensuring Flathub user remote is configured..."
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
ok "Flathub user remote ready"

info "Installing EasyEffects (Flatpak)..."
flatpak_install com.github.wwmm.easyeffects
ok "EasyEffects installed"

# ---------------------------------------------------------------------------
# 3. Mesa / AMD 3D Acceleration
# ---------------------------------------------------------------------------
# mesa-va-drivers-freeworld swap is handled in bootstrap.
# These packages add Vulkan, VDPAU, and VA-API verification tooling.

info "Installing Mesa/AMD acceleration packages..."
pkg_install \
    libva-utils \
    mesa-vdpau-drivers-freeworld \
    mesa-vulkan-drivers
ok "Mesa acceleration packages installed"

# ---------------------------------------------------------------------------
# 4. Communication — Flatpak
# ---------------------------------------------------------------------------
# Flatpak chosen for sandbox isolation (sensitive communications).
# Signal: no official Fedora RPM exists; Flathub is the standard path.
# Slack:  Flatpak provides better update cadence and sandboxing than the
#         unofficial RPM options.

info "Installing communication apps (Flatpak)..."
flatpak_install com.slack.Slack
flatpak_install org.signal.Signal
ok "Slack and Signal installed"

# ---------------------------------------------------------------------------
# 5. Nextcloud Desktop Client
# ---------------------------------------------------------------------------
# RPM — integrates cleanly with system file manager and tray.

info "Installing Nextcloud desktop client..."
pkg_install nextcloud-client
ok "Nextcloud client installed"

# ---------------------------------------------------------------------------
# 6. ProtonVPN
# ---------------------------------------------------------------------------
# RPM from official ProtonVPN repo — Flatpak version has known Wayland GUI
# rendering failures. NetworkManager integration requires native install.
# Launched manually as a tray app; no autostart needed.

if rpm -q proton-vpn-gtk-app &>/dev/null; then
    ok "ProtonVPN already installed (skipped)"
else
    info "Installing ProtonVPN..."
    require_cmd curl "sudo dnf install -y curl"
    FEDORA_VER=$(rpm -E %fedora)
    PROTON_BASE="https://repo.protonvpn.com"

    # ProtonVPN may not yet publish a repo for the current Fedora version.
    # Walk backwards until we find one that exists (try up to 3 versions back).
    # Each candidate URL is retried up to 3 times with a 2-second back-off.
    PROTON_URL=""
    for ver in "$FEDORA_VER" $(( FEDORA_VER - 1 )) $(( FEDORA_VER - 2 )); do
        candidate="${PROTON_BASE}/fedora-${ver}-stable/protonvpn-stable-release/${PROTON_RPM}"
        for attempt in 1 2 3; do
            if curl -sf --head --connect-timeout 5 "$candidate" -o /dev/null; then
                PROTON_URL="$candidate"
                break 2
            fi
            (( attempt < 3 )) && sleep 2
        done
        [ "$ver" -ne "$FEDORA_VER" ] && warn "ProtonVPN repo not found for Fedora ${FEDORA_VER}, trying Fedora ${ver}"
    done

    if [ -z "$PROTON_URL" ]; then
        warn "Could not find a ProtonVPN repo RPM for Fedora ${FEDORA_VER} or the two previous releases. Skipping."
    else
        [ "$(rpm -E %fedora)" -ne "$FEDORA_VER" ] && \
            warn "Using ProtonVPN repo from a different Fedora release: $PROTON_URL"
        sudo dnf install -y "$PROTON_URL"
        pkg_install proton-vpn-gtk-app
        ok "ProtonVPN installed"
    fi
fi

# ---------------------------------------------------------------------------
# 7. KeePassXC
# ---------------------------------------------------------------------------
# RPM — browser integration (native messaging) works between RPM KeePassXC
# and RPM browsers (Brave, Firefox). Flatpak-to-RPM native messaging works,
# but keeping all three as RPM is simplest.

info "Installing KeePassXC..."
pkg_install keepassxc
ok "KeePassXC installed"

# ---------------------------------------------------------------------------
# 8. KVM / virt-manager
# ---------------------------------------------------------------------------

info "Installing KVM / virt-manager..."
pkg_install \
    libvirt \
    libvirt-daemon-config-network \
    qemu-kvm \
    virt-install \
    virt-manager \
    virt-viewer
sudo usermod -aG libvirt "$(id -un)"
sudo systemctl enable --now libvirtd
ok "KVM stack installed; user added to libvirt group"

# ---------------------------------------------------------------------------
# 9. Podman
# ---------------------------------------------------------------------------
# Podman is already installed by bootstrap.

info "Podman check..."
if command -v podman &>/dev/null; then
    ok "Podman already installed (bootstrap): $(podman --version)"
else
    warn "Podman not found — was bootstrap run? Install with: sudo dnf install -y podman"
fi

# ---------------------------------------------------------------------------
# 10. Desktop Utilities (optional — requires --gtk-apps or --qt-apps)
# ---------------------------------------------------------------------------

if [[ -n "$DESKTOP_TOOLKIT" ]]; then
    if [[ "$DESKTOP_TOOLKIT" == "gtk" ]]; then
        info "Installing GTK desktop utilities..."
        pkg_install \
            celluloid \
            evince \
            file-roller \
            gnome-calculator \
            loupe \
            thunar
        ok "GTK desktop utilities installed"
    else
        info "Installing Qt/KDE desktop utilities..."
        pkg_install \
            ark \
            dolphin \
            gwenview \
            haruna \
            kcalc \
            okular
        ok "Qt/KDE desktop utilities installed"
    fi
fi

# ---------------------------------------------------------------------------
# 11. DevOps Tooling (optional — requires --devops)
# ---------------------------------------------------------------------------
# Third-party repos (HashiCorp, Kubernetes) may not support the latest Fedora
# version yet. The find_fedora_version helper probes backwards to find a
# working version and pins $releasever in the repo file.

if [[ "$INSTALL_DEVOPS" == true ]]; then
    info "Installing DevOps tooling..."

    # HashiCorp repo (Terraform, Packer, etc.)
    _HASHI_AVAILABLE=false
    if [ ! -f /etc/yum.repos.d/hashicorp.repo ]; then
        _hashi_ver=$(find_fedora_version \
            "https://rpm.releases.hashicorp.com/fedora/{ver}/x86_64/stable/repodata/repomd.xml") || true
        if [[ -n "${_hashi_ver:-}" ]]; then
            sudo dnf config-manager addrepo \
                --from-repofile=https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
            sudo sed -i "s/\$releasever/$_hashi_ver/g" /etc/yum.repos.d/hashicorp.repo
            [[ "$_hashi_ver" != "$(rpm -E %fedora)" ]] && \
                warn "HashiCorp repo pinned to Fedora $_hashi_ver ($(rpm -E %fedora) not yet available)"
            _HASHI_AVAILABLE=true
        else
            warn "HashiCorp repo unavailable for Fedora $(rpm -E %fedora) or recent versions — skipping terraform"
        fi
    else
        # Repo file exists — check if it still uses $releasever and fix if needed
        if sudo grep -q '\$releasever' /etc/yum.repos.d/hashicorp.repo; then
            _hashi_ver=$(find_fedora_version \
                "https://rpm.releases.hashicorp.com/fedora/{ver}/x86_64/stable/repodata/repomd.xml") || true
            if [[ -n "${_hashi_ver:-}" ]]; then
                sudo sed -i "s/\$releasever/$_hashi_ver/g" /etc/yum.repos.d/hashicorp.repo
                [[ "$_hashi_ver" != "$(rpm -E %fedora)" ]] && \
                    warn "HashiCorp repo pinned to Fedora $_hashi_ver ($(rpm -E %fedora) not yet available)"
                _HASHI_AVAILABLE=true
            else
                warn "HashiCorp repo unavailable for current Fedora — disabling"
                sudo dnf config-manager setopt hashicorp.enabled=0
            fi
        else
            _HASHI_AVAILABLE=true
        fi
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

    pkg_install \
        ansible \
        helm \
        kind \
        kubectl \
        podman-compose \
        yq

    if [[ "$_HASHI_AVAILABLE" == true ]]; then
        pkg_install terraform
    else
        warn "terraform skipped (HashiCorp repo not available)"
    fi

    ok "DevOps stack installed"
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
if [[ -n "$DESKTOP_TOOLKIT" ]]; then
    if [[ "$DESKTOP_TOOLKIT" == "gtk" ]]; then
        echo " 11. Desktop utils — thunar, evince, gnome-calculator, loupe, celluloid, file-roller"
    else
        echo " 11. Desktop utils — dolphin, okular, kcalc, gwenview, haruna, ark"
    fi
fi
if [[ "$INSTALL_DEVOPS" == true ]]; then
    echo " 12. DevOps — terraform version, kubectl version, ansible --version, helm version"
fi
echo ""
echo "NOTE: Log out and back in for libvirt group membership to take effect."
echo ""
