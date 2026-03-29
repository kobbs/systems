# shellcheck shell=bash
# modules/apps.sh -- User application installation module.
# Source this file; do not execute it directly.
#
# Handles: browsers, audio, Mesa/AMD, communication, Nextcloud, ProtonVPN,
#          KeePassXC, KVM, desktop utilities (GTK/Qt), DevOps tooling.
#
# Reads package lists from apps.conf (single source of truth).
# Assumes lib/common.sh, lib/config.sh are sourced.
# pkg_install(), require_cmd(), find_fedora_version(), REPO_ROOT,
# PROFILE_*, PKG_MANIFEST, FLATPAK_MANIFEST are available.

# ---------------------------------------------------------------------------
# App registry parser
# ---------------------------------------------------------------------------

declare -gA _APP_SECTIONS=()

# _apps_load_conf
# Reads apps.conf into _APP_SECTIONS: section name → space-delimited package list.
# Package names never contain spaces, so word-splitting gives arrays for free.
_apps_load_conf() {
    local file="${REPO_ROOT}/apps.conf"
    if [[ ! -f "$file" ]]; then
        warn "apps.conf not found at $file"
        return 1
    fi

    _APP_SECTIONS=()
    local section="" line

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Trim whitespace (same logic as lib/config.sh)
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        # Skip blanks and comments
        [[ -z "$line" || "$line" == \#* ]] && continue

        # Section header
        if [[ "$line" =~ ^\[([^]]+)\]$ ]]; then
            section="${BASH_REMATCH[1]}"
            continue
        fi

        # Bare package name under current section
        [[ -z "$section" ]] && continue
        _APP_SECTIONS["$section"]+="${_APP_SECTIONS["$section"]:+ }${line}"
    done < "$file"
}

# ---------------------------------------------------------------------------
# Version pins
# ---------------------------------------------------------------------------

_PROTON_RPM="${PROTON_RPM:-protonvpn-stable-release-1.0.1-2.noarch.rpm}"
_K8S_VERSION="${K8S_VERSION:-v1.34}"

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

_apps_flatpak_install() {
    flatpak install --user -y flathub "$1"
    mkdir -p "$(dirname "$FLATPAK_MANIFEST")"
    grep -qFx "$1" "$FLATPAK_MANIFEST" 2>/dev/null || echo "$1" >> "$FLATPAK_MANIFEST"
}

_apps_get_all_rpm_targets() {
    local pkgs=()
    local section
    for section in "${!_APP_SECTIONS[@]}"; do
        # Skip Flatpak sections
        [[ "$section" == flatpak:* ]] && continue

        # Check qualifier (portion after ':')
        local qualifier="${section#*:}"
        [[ "$qualifier" == "$section" ]] && qualifier=""   # no ':' found

        case "$qualifier" in
            "")     ;;   # always included (base)
            gtk)    [[ "$_APPS_DESKTOP_TOOLKIT" == "gtk" ]] || continue ;;
            qt)     [[ "$_APPS_DESKTOP_TOOLKIT" == "qt" ]] || continue ;;
            *)
                # Generic packs check
                if [[ -z "${_APPS_ACTIVE_PACKS[$qualifier]+x}" ]]; then
                    continue
                fi
                ;;
        esac

        local items
        read -ra items <<< "${_APP_SECTIONS[$section]}"
        pkgs+=("${items[@]}")
    done
    printf '%s\n' "${pkgs[@]}"
}

_apps_get_all_flatpak_targets() {
    local pkgs=()
    local section
    for section in "${!_APP_SECTIONS[@]}"; do
        [[ "$section" == flatpak:* ]] || continue
        local items
        read -ra items <<< "${_APP_SECTIONS[$section]}"
        pkgs+=("${items[@]}")
    done
    printf '%s\n' "${pkgs[@]}"
}

# ---------------------------------------------------------------------------
# Module contract
# ---------------------------------------------------------------------------

apps::init() {
    _apps_load_conf || return 1
    _APPS_DESKTOP_TOOLKIT="${PROFILE_APPS_DESKTOP_TOOLKIT:-qt}"

    # Build active packs set from profile
    declare -gA _APPS_ACTIVE_PACKS=()
    local packs_str="${PROFILE_APPS_PACKS:-base}"
    local pack
    for pack in $packs_str; do
        _APPS_ACTIVE_PACKS["$pack"]=1
    done
}

apps::check() {
    # Check RPMs
    local pkg
    while IFS= read -r pkg; do
        rpm -q "$pkg" &>/dev/null || return 0
    done < <(_apps_get_all_rpm_targets)

    # Check Flatpaks (if enabled)
    if [[ "${PROFILE_PACKAGES_FLATPAK:-true}" == "true" ]]; then
        local app_id
        while IFS= read -r app_id; do
            flatpak list --user --app --columns=application 2>/dev/null | grep -qFx "$app_id" || return 0
        done < <(_apps_get_all_flatpak_targets)
    fi

    # ProtonVPN
    if [[ "${PROFILE_APPS_PROTONVPN:-false}" == "true" ]]; then
        rpm -q proton-vpn-gtk-app &>/dev/null || return 0
    fi

    return 1
}

apps::preview() {
    info "[apps] Preview:"

    echo "  Desktop toolkit: ${_APPS_DESKTOP_TOOLKIT:-none}"
    echo "  Active packs: ${!_APPS_ACTIVE_PACKS[*]:-base}"
    echo "  KVM: ${PROFILE_APPS_KVM:-false}"
    echo "  ProtonVPN: ${PROFILE_APPS_PROTONVPN:-false}"
    echo "  Firefox Wayland: ${PROFILE_APPS_FIREFOX_WAYLAND:-true}"
    echo "  Flatpak: ${PROFILE_PACKAGES_FLATPAK:-true}"
    echo ""

    # RPMs
    local missing_rpms=()
    local pkg
    while IFS= read -r pkg; do
        rpm -q "$pkg" &>/dev/null || missing_rpms+=("$pkg")
    done < <(_apps_get_all_rpm_targets)

    if [[ "${PROFILE_APPS_PROTONVPN:-false}" == "true" ]]; then
        if ! rpm -q proton-vpn-gtk-app &>/dev/null; then
            missing_rpms+=("proton-vpn-gtk-app")
        fi
    fi

    if [[ ${#missing_rpms[@]} -gt 0 ]]; then
        echo "  RPM packages to install:"
        printf '    %s\n' "${missing_rpms[@]}"
    else
        echo "  All RPM packages installed."
    fi

    # Flatpaks
    if [[ "${PROFILE_PACKAGES_FLATPAK:-true}" == "true" ]]; then
        local missing_flatpaks=()
        local app_id
        while IFS= read -r app_id; do
            flatpak list --user --app --columns=application 2>/dev/null | grep -qFx "$app_id" || missing_flatpaks+=("$app_id")
        done < <(_apps_get_all_flatpak_targets)

        if [[ ${#missing_flatpaks[@]} -gt 0 ]]; then
            echo "  Flatpaks to install:"
            printf '    %s\n' "${missing_flatpaks[@]}"
        else
            echo "  All Flatpaks installed."
        fi
    else
        echo "  Flatpaks: disabled by profile  [SKIP]"
    fi
}

apps::apply() {
    preflight_checks
    require_cmd flatpak "sudo dnf install -y flatpak"

    # --- Repo setup (before bulk install) ---

    # Brave repo
    if [[ "${_APP_SECTIONS[browsers]:-}" == *brave-browser* ]]; then
        if [[ ! -f /etc/yum.repos.d/brave-browser.repo ]]; then
            info "Adding Brave browser repo..."
            sudo dnf config-manager addrepo \
                --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
        fi
    fi

    # Firefox Wayland env var
    if [[ "${PROFILE_APPS_FIREFOX_WAYLAND:-true}" == "true" ]]; then
        if [[ "${_APP_SECTIONS[browsers]:-}" == *firefox* ]]; then
            if ! grep -xF 'MOZ_ENABLE_WAYLAND=1' /etc/environment 2>/dev/null; then
                echo 'MOZ_ENABLE_WAYLAND=1' | sudo tee -a /etc/environment > /dev/null
                ok "MOZ_ENABLE_WAYLAND=1 added to /etc/environment"
            fi
        fi
    fi

    # DevOps repos (HashiCorp + Kubernetes) -- only if devops pack is active
    local hashi_available=false
    if [[ -n "${_APPS_ACTIVE_PACKS[devops]+x}" ]]; then
        # HashiCorp repo
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
                warn "HashiCorp repo unavailable -- skipping terraform"
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
                    warn "HashiCorp repo unavailable -- disabling"
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
    fi

    # --- Bulk RPM install ---
    local all_rpms
    mapfile -t all_rpms < <(_apps_get_all_rpm_targets)
    if [[ ${#all_rpms[@]} -gt 0 ]]; then
        info "Installing RPM packages..."
        pkg_install "${all_rpms[@]}"
        ok "RPM packages installed"
    fi

    # Terraform (conditional on HashiCorp repo -- not in apps.conf)
    if [[ -n "${_APPS_ACTIVE_PACKS[devops]+x}" ]]; then
        if [[ "$hashi_available" == true ]]; then
            pkg_install terraform
        else
            warn "terraform skipped (HashiCorp repo not available)"
        fi
        ok "DevOps stack installed"
    fi

    # --- ProtonVPN (special repo probing -- not in apps.conf) ---
    if [[ "${PROFILE_APPS_PROTONVPN:-false}" == "true" ]]; then
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
    else
        info "ProtonVPN: disabled by profile -- skipping"
    fi

    # --- Flatpaks ---
    if [[ "${PROFILE_PACKAGES_FLATPAK:-true}" == "true" ]]; then
        info "Installing Flatpak apps..."
        flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
        local app_id
        while IFS= read -r app_id; do
            _apps_flatpak_install "$app_id"
        done < <(_apps_get_all_flatpak_targets)
        ok "Flatpak apps installed"
    else
        info "Flatpaks: disabled by profile -- skipping"
    fi

    # --- KVM post-install ---
    if [[ "${PROFILE_APPS_KVM:-false}" == "true" ]]; then
        if [[ -n "${_APP_SECTIONS[kvm]:-}" ]]; then
            info "Configuring KVM..."
            sudo usermod -aG libvirt "$(id -un)"
            sudo systemctl enable --now libvirtd
            ok "KVM stack configured"
        fi
    else
        info "KVM: disabled by profile -- skipping"
    fi

    ok "Apps installed"
}

apps::status() {
    local rpm_count=0 flatpak_count=0
    [[ -f "$PKG_MANIFEST" ]] && rpm_count=$(wc -l < "$PKG_MANIFEST")
    [[ -f "$FLATPAK_MANIFEST" ]] && flatpak_count=$(wc -l < "$FLATPAK_MANIFEST")
    echo "apps: ${rpm_count} RPM + ${flatpak_count} Flatpak managed"
}
