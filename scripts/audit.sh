#!/bin/bash

# Package Audit
# =============
# Reads manifest files written by bootstrap.sh and apps.sh, compares against
# installed leaf packages and flatpaks, and writes a diff-friendly report.
#
# Usage:  audit.sh
#
# The report is written to /var/tmp/pkg-audit-YYYYMMDD.txt.
# Diff reports across machines to spot bloat.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

REPORT_DIR="/var/tmp"
DATE_STAMP=$(date +%Y%m%d)

# ---------------------------------------------------------------------------
# Read manifests (graceful if missing — all packages show as [extra])
# ---------------------------------------------------------------------------

declare -A managed_pkgs=()
if [[ -f "$PKG_MANIFEST" ]]; then
    while IFS= read -r pkg; do
        [[ -n "$pkg" ]] && managed_pkgs["$pkg"]=1
    done < "$PKG_MANIFEST"
fi

declare -A managed_flatpaks=()
if [[ -f "$FLATPAK_MANIFEST" ]]; then
    while IFS= read -r app_id; do
        [[ -n "$app_id" ]] && managed_flatpaks["$app_id"]=1
    done < "$FLATPAK_MANIFEST"
fi

# ---------------------------------------------------------------------------
# Collect leaf packages from dnf5
# ---------------------------------------------------------------------------

info "Collecting leaf packages..."

declare -A leaves=()
while IFS= read -r line; do
    if [[ "$line" == "- "* ]]; then
        # Format: "- name-epoch:version-release.arch"
        # Strip prefix, then remove everything from the epoch separator onward
        nvra="${line#- }"
        name="${nvra%-[0-9]*:*}"
        [[ -n "$name" ]] && leaves["$name"]=1
    fi
done < <(dnf5 leaves 2>/dev/null || true)

# ---------------------------------------------------------------------------
# Categorize leaves
# ---------------------------------------------------------------------------

extra_leaves=()
managed_leaves=()
for pkg in $(printf '%s\n' "${!leaves[@]}" | sort); do
    if [[ -v managed_pkgs["$pkg"] ]]; then
        managed_leaves+=("$pkg")
    else
        extra_leaves+=("$pkg")
    fi
done

# ---------------------------------------------------------------------------
# Categorize flatpaks
# ---------------------------------------------------------------------------

extra_flatpaks=()
managed_flatpak_list=()
while IFS= read -r app_id; do
    [[ -z "$app_id" ]] && continue
    if [[ -v managed_flatpaks["$app_id"] ]]; then
        managed_flatpak_list+=("$app_id")
    else
        extra_flatpaks+=("$app_id")
    fi
done < <(flatpak list --user --app --columns=application 2>/dev/null | sort || true)

# ---------------------------------------------------------------------------
# Formatting helper
# ---------------------------------------------------------------------------

_pkg_line() {
    local tag="$1" pkg="$2"
    local size_bytes size_mb install_date
    size_bytes=$(rpm -q --qf '%{SIZE}\n' "$pkg" 2>/dev/null | head -1 || echo "0")
    size_mb=$(( size_bytes / 1048576 ))
    install_date=$(rpm -q --qf '%{INSTALLTIME}\n' "$pkg" 2>/dev/null | head -1 || echo "0")
    install_date=$(date -d "@$install_date" '+%Y-%m-%d' 2>/dev/null || echo "unknown")
    printf "%-10s %-35s %4s MB  %s\n" "$tag" "$pkg" "$size_mb" "$install_date"
}

# ---------------------------------------------------------------------------
# Generate report
# ---------------------------------------------------------------------------

report="$REPORT_DIR/pkg-audit-${DATE_STAMP}.txt"

{
    echo "# Package Audit — $(hostname -s) — $(date '+%Y-%m-%d')"
    echo ""
    echo "# Extra leaf packages (unmanaged)"
    echo ""
    for pkg in "${extra_leaves[@]+"${extra_leaves[@]}"}"; do
        _pkg_line "[extra]" "$pkg"
    done

    echo ""
    echo "# Managed leaf packages"
    echo ""
    for pkg in "${managed_leaves[@]+"${managed_leaves[@]}"}"; do
        _pkg_line "[managed]" "$pkg"
    done

    echo ""
    echo "# Flatpaks"
    echo ""
    for app_id in "${extra_flatpaks[@]+"${extra_flatpaks[@]}"}"; do
        printf "%-10s %s\n" "[extra]" "$app_id"
    done
    for app_id in "${managed_flatpak_list[@]+"${managed_flatpak_list[@]}"}"; do
        printf "%-10s %s\n" "[managed]" "$app_id"
    done
} > "$report"

ok "Report written to: $report"
echo ""
echo "Summary:"
echo "  Extra leaves:     ${#extra_leaves[@]}"
echo "  Managed leaves:   ${#managed_leaves[@]}"
echo "  Extra flatpaks:   ${#extra_flatpaks[@]}"
echo "  Managed flatpaks: ${#managed_flatpak_list[@]}"
echo ""
echo "Review: less $report"
