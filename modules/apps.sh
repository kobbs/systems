# modules/apps.sh — User application installation module.
# Source this file; do not execute it directly.
#
# Handles: browsers, audio, Mesa/AMD, communication, Nextcloud, ProtonVPN,
#          KeePassXC, KVM, desktop utilities (GTK/Qt), DevOps tooling.
#
# Assumes lib/common.sh, lib/config.sh are sourced.
# pkg_install(), require_cmd(), find_fedora_version(), REPO_ROOT,
# PROFILE_*, PKG_MANIFEST, FLATPAK_MANIFEST are available.

# ---------------------------------------------------------------------------
# Package lists (sorted alphabetically)
# ---------------------------------------------------------------------------

_BROWSER_PKGS=( brave-browser firefox )
_MESA_PKGS=( libva-utils mesa-vdpau-drivers-freeworld mesa-vulkan-drivers )
_COMM_FLATPAKS=( com.slack.Slack org.signal.Signal )
_AUDIO_FLATPAKS=( com.github.wwmm.easyeffects )
_MISC_PKGS=( keepassxc nextcloud-client )
_KVM_PKGS=( libvirt libvirt-daemon-config-network qemu-kvm virt-install virt-manager virt-viewer )
_GTK_DESKTOP_PKGS=( celluloid evince file-roller gnome-calculator loupe thunar )
_QT_DESKTOP_PKGS=( ark dolphin gwenview haruna kcalc okular )
_DEVOPS_PKGS=( ansible helm kind kubectl podman-compose yq )

# Version pins
_PROTON_RPM="${PROTON_RPM:-protonvpn-stable-release-1.0.1-2.noarch.rpm}"
_K8S_VERSION="${K8S_VERSION:-v1.34}"

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

_flatpak_install() {
    flatpak install --user -y flathub "$1"
    mkdir -p "$(dirname "$FLATPAK_MANIFEST")"
    grep -qFx "$1" "$FLATPAK_MANIFEST" 2>/dev/null || echo "$1" >> "$FLATPAK_MANIFEST"
}

_apps_parse_flags() {
    _APPS_INSTALL_DEVOPS=false
    _APPS_DESKTOP_TOOLKIT="$(profile_get apps desktop_toolkit 2>/dev/null || true)"
    local arg
    for arg in "$@"; do
        case "$arg" in
            --devops) _APPS_INSTALL_DEVOPS=true ;;
        esac
    done
}

_get_all_rpm_targets() {
    local pkgs=()
    pkgs+=("${_BROWSER_PKGS[@]}")
    pkgs+=("${_MESA_PKGS[@]}")
    pkgs+=("${_MISC_PKGS[@]}")
    pkgs+=("${_KVM_PKGS[@]}")

    if [[ "$_APPS_DESKTOP_TOOLKIT" == "gtk" ]]; then
        pkgs+=("${_GTK_DESKTOP_PKGS[@]}")
    elif [[ "$_APPS_DESKTOP_TOOLKIT" == "qt" ]]; then
        pkgs+=("${_QT_DESKTOP_PKGS[@]}")
    fi

    if [[ "$_APPS_INSTALL_DEVOPS" == "true" ]]; then
        pkgs+=("${_DEVOPS_PKGS[@]}")
    fi

    printf '%s\n' "${pkgs[@]}"
}

_get_all_flatpak_targets() {
    printf '%s\n' "${_COMM_FLATPAKS[@]}" "${_AUDIO_FLATPAKS[@]}"
}

# ---------------------------------------------------------------------------
# Module contract
# ---------------------------------------------------------------------------

apps::check() {
    _apps_parse_flags "$@"

    # Check RPMs
    local pkg
    while IFS= read -r pkg; do
        rpm -q "$pkg" &>/dev/null || return 0
    done < <(_get_all_rpm_targets)

    # Check Flatpaks
    local app_id
    while IFS= read -r app_id; do
        flatpak list --user --app --columns=application 2>/dev/null | grep -qFx "$app_id" || return 0
    done < <(_get_all_flatpak_targets)

    # ProtonVPN
    rpm -q proton-vpn-gtk-app &>/dev/null || return 0

    return 1
}

apps::preview() {
    _apps_parse_flags "$@"
    info "[apps] Preview:"

    echo "  Desktop toolkit: ${_APPS_DESKTOP_TOOLKIT:-none}"
    echo "  DevOps: $_APPS_INSTALL_DEVOPS"
    echo ""

    # RPMs
    local missing_rpms=()
    local pkg
    while IFS= read -r pkg; do
        rpm -q "$pkg" &>/dev/null || missing_rpms+=("$pkg")
    done < <(_get_all_rpm_targets)

    if ! rpm -q proton-vpn-gtk-app &>/dev/null; then
        missing_rpms+=("proton-vpn-gtk-app")
    fi

    if [[ ${#missing_rpms[@]} -gt 0 ]]; then
        echo "  RPM packages to install:"
        printf '    %s\n' "${missing_rpms[@]}"
    else
        echo "  All RPM packages installed."
    fi

    # Flatpaks
    local missing_flatpaks=()
    local app_id
    while IFS= read -r app_id; do
        flatpak list --user --app --columns=application 2>/dev/null | grep -qFx "$app_id" || missing_flatpaks+=("$app_id")
    done < <(_get_all_flatpak_targets)

    if [[ ${#missing_flatpaks[@]} -gt 0 ]]; then
        echo "  Flatpaks to install:"
        printf '    %s\n' "${missing_flatpaks[@]}"
    else
        echo "  All Flatpaks installed."
    fi
}

apps::apply() {
    _apps_parse_flags "$@"
    preflight_checks
    require_cmd flatpak "sudo dnf install -y flatpak"

    # --- Browsers ---
    info "Installing browsers..."
    pkg_install firefox

    if ! grep -xF 'MOZ_ENABLE_WAYLAND=1' /etc/environment 2>/dev/null; then
        echo 'MOZ_ENABLE_WAYLAND=1' | sudo tee -a /etc/environment > /dev/null
        ok "MOZ_ENABLE_WAYLAND=1 added to /etc/environment"
    fi

    if [[ ! -f /etc/yum.repos.d/brave-browser.repo ]]; then
        sudo dnf config-manager addrepo \
            --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
    fi
    pkg_install brave-browser
    ok "Browsers installed"

    # --- Audio ---
    info "Installing EasyEffects (Flatpak)..."
    flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    local app_id
    for app_id in "${_AUDIO_FLATPAKS[@]}"; do
        _flatpak_install "$app_id"
    done
    ok "Audio apps installed"

    # --- Mesa ---
    info "Installing Mesa/AMD acceleration packages..."
    pkg_install "${_MESA_PKGS[@]}"
    ok "Mesa packages installed"

    # --- Communication ---
    info "Installing communication apps (Flatpak)..."
    for app_id in "${_COMM_FLATPAKS[@]}"; do
        _flatpak_install "$app_id"
    done
    ok "Communication apps installed"

    # --- Nextcloud + KeePassXC ---
    info "Installing Nextcloud + KeePassXC..."
    pkg_install "${_MISC_PKGS[@]}"
    ok "Misc apps installed"

    # --- ProtonVPN ---
    if rpm -q proton-vpn-gtk-app &>/dev/null; then
        ok "ProtonVPN already installed (skipped)"
    else
        info "Installing ProtonVPN..."
        require_cmd curl "sudo dnf install -y curl"
        local fedora_ver
        fedora_ver=$(rpm -E %fedora)
        local proton_base="https://repo.protonvpn.com"
        local proton_url=""

        for ver in "$fedora_ver" $(( fedora_ver - 1 )) $(( fedora_ver - 2 )); do
            local candidate="${proton_base}/fedora-${ver}-stable/protonvpn-stable-release/${_PROTON_RPM}"
            local attempt
            for attempt in 1 2 3; do
                if curl -sf --head --connect-timeout 5 "$candidate" -o /dev/null; then
                    proton_url="$candidate"
                    break 2
                fi
                (( attempt < 3 )) && sleep 2
            done
            [[ "$ver" -ne "$fedora_ver" ]] && warn "ProtonVPN repo not found for Fedora ${fedora_ver}, trying Fedora ${ver}"
        done

        if [[ -z "$proton_url" ]]; then
            warn "Could not find a ProtonVPN repo for Fedora ${fedora_ver} or recent releases. Skipping."
        else
            sudo dnf install -y "$proton_url"
            pkg_install proton-vpn-gtk-app
            ok "ProtonVPN installed"
        fi
    fi

    # --- KVM ---
    info "Installing KVM / virt-manager..."
    pkg_install "${_KVM_PKGS[@]}"
    sudo usermod -aG libvirt "$(id -un)"
    sudo systemctl enable --now libvirtd
    ok "KVM stack installed"

    # --- Desktop utilities ---
    if [[ "$_APPS_DESKTOP_TOOLKIT" == "gtk" ]]; then
        info "Installing GTK desktop utilities..."
        pkg_install "${_GTK_DESKTOP_PKGS[@]}"
        ok "GTK desktop utilities installed"
    elif [[ "$_APPS_DESKTOP_TOOLKIT" == "qt" ]]; then
        info "Installing Qt/KDE desktop utilities..."
        pkg_install "${_QT_DESKTOP_PKGS[@]}"
        ok "Qt/KDE desktop utilities installed"
    fi

    # --- DevOps ---
    if [[ "$_APPS_INSTALL_DEVOPS" == "true" ]]; then
        info "Installing DevOps tooling..."

        # HashiCorp repo
        local hashi_available=false
        if [[ ! -f /etc/yum.repos.d/hashicorp.repo ]]; then
            local hashi_ver
            hashi_ver=$(find_fedora_version \
                "https://rpm.releases.hashicorp.com/fedora/{ver}/x86_64/stable/repodata/repomd.xml") || true
            if [[ -n "${hashi_ver:-}" ]]; then
                sudo dnf config-manager addrepo \
                    --from-repofile=https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
                sudo sed -i "s/\$releasever/$hashi_ver/g" /etc/yum.repos.d/hashicorp.repo
                [[ "$hashi_ver" != "$(rpm -E %fedora)" ]] && \
                    warn "HashiCorp repo pinned to Fedora $hashi_ver"
                hashi_available=true
            else
                warn "HashiCorp repo unavailable — skipping terraform"
            fi
        else
            if sudo grep -q '\$releasever' /etc/yum.repos.d/hashicorp.repo; then
                local hashi_ver
                hashi_ver=$(find_fedora_version \
                    "https://rpm.releases.hashicorp.com/fedora/{ver}/x86_64/stable/repodata/repomd.xml") || true
                if [[ -n "${hashi_ver:-}" ]]; then
                    sudo sed -i "s/\$releasever/$hashi_ver/g" /etc/yum.repos.d/hashicorp.repo
                    hashi_available=true
                else
                    warn "HashiCorp repo unavailable — disabling"
                    sudo dnf config-manager setopt hashicorp.enabled=0
                fi
            else
                hashi_available=true
            fi
        fi

        # Kubernetes repo
        if [[ ! -f /etc/yum.repos.d/kubernetes.repo ]]; then
            cat <<KREPO | sudo tee /etc/yum.repos.d/kubernetes.repo > /dev/null
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${_K8S_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${_K8S_VERSION}/rpm/repodata/repomd.xml.key
KREPO
            sudo chmod 644 /etc/yum.repos.d/kubernetes.repo
        fi

        pkg_install "${_DEVOPS_PKGS[@]}"

        if [[ "$hashi_available" == true ]]; then
            pkg_install terraform
        else
            warn "terraform skipped (HashiCorp repo not available)"
        fi

        ok "DevOps stack installed"
    fi
}

apps::status() {
    local rpm_count=0 flatpak_count=0
    [[ -f "$PKG_MANIFEST" ]] && rpm_count=$(wc -l < "$PKG_MANIFEST")
    [[ -f "$FLATPAK_MANIFEST" ]] && flatpak_count=$(wc -l < "$FLATPAK_MANIFEST")
    echo "apps: ${rpm_count} RPM + ${flatpak_count} Flatpak managed"
}
