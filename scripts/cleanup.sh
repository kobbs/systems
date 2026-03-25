#!/bin/bash

# Package Cleanup Utility
# =======================
# Two-phase workflow for finding and removing unused packages.
#
#   cleanup.sh audit   — generate a categorized package report
#   cleanup.sh remove  — safely remove packages with dependency review
#
# The audit cross-references installed packages against what bootstrap.sh
# and apps.sh manage, highlighting removal candidates.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

REPORT_DIR="/var/tmp"
DATE_STAMP=$(date +%Y%m%d)

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $(basename "$0") <command> [OPTIONS]

Commands:
  audit               Generate a categorized package report
  remove <pkg>...     Safely remove packages (with dependency review)

Options:
  -h, --help          Show this help message and exit

The audit report is written to $REPORT_DIR/pkg-audit-YYYYMMDD.txt.
Removal actions are logged to $REPORT_DIR/pkg-removed-YYYYMMDD.log.
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Collect known packages managed by this repo
# Parses bootstrap.sh and apps.sh at runtime to stay in sync.
# ---------------------------------------------------------------------------
collect_known_packages() {
    local -n _result=$1
    local bootstrap="$SCRIPT_DIR/bootstrap.sh"
    local apps="$SCRIPT_DIR/apps.sh"

    # bootstrap.sh: SWAY_COMMON_PKGS array members
    if [[ -f "$bootstrap" ]]; then
        while IFS= read -r pkg; do
            [[ -n "$pkg" ]] && _result["$pkg"]=1
        done < <(sed -n '/^SWAY_COMMON_PKGS=(/,/^)/{ //d; s/^[[:space:]]*//; s/[[:space:]]*$//; p }' "$bootstrap")

        # bootstrap.sh: packages from "dnf install -y" lines (inline + continuation lines)
        while IFS= read -r pkg; do
            [[ -n "$pkg" ]] && _result["$pkg"]=1
        done < <(sed -n '/sudo dnf install -y/,/^[^[:space:]\\"]/{ s/.*dnf install -y//; s/\\$//; p }' "$bootstrap" \
            | tr ' ' '\n' | sed 's/^[[:space:]]*//; /^$/d; /^"/d; /^\$/d; /^-/d; /^https:/d; s/"//g' \
            | grep -v '^\$' | grep -v '^{' | sort -u)

        # bootstrap.sh: full sway stack (base Fedora path)
        while IFS= read -r pkg; do
            [[ -n "$pkg" ]] && _result["$pkg"]=1
        done < <(grep -A 20 '"${SWAY_COMMON_PKGS\[@\]}"' "$bootstrap" \
            | grep -oP '^\s+\K[a-z][a-z0-9._-]+' | sort -u)
    fi

    # apps.sh: packages from "dnf install -y" lines
    if [[ -f "$apps" ]]; then
        while IFS= read -r pkg; do
            [[ -n "$pkg" ]] && _result["$pkg"]=1
        done < <(sed -n '/sudo dnf install -y/,/^[^[:space:]\\"]/{ s/.*dnf install -y//; s/\\$//; p }' "$apps" \
            | tr ' ' '\n' | sed 's/^[[:space:]]*//; /^$/d; /^"/d; /^\$/d; /^-/d; /^https:/d; s/"//g' \
            | grep -v '^\$' | grep -v '^{' | sort -u)
    fi
}

# ---------------------------------------------------------------------------
# Collect known Flatpak app IDs managed by this repo
# ---------------------------------------------------------------------------
collect_known_flatpaks() {
    local -n _result=$1
    local apps="$SCRIPT_DIR/apps.sh"

    if [[ -f "$apps" ]]; then
        while IFS= read -r app_id; do
            [[ -n "$app_id" ]] && _result["$app_id"]=1
        done < <(grep -oP 'flatpak_install \K\S+' "$apps" 2>/dev/null || true)
    fi
}

# ---------------------------------------------------------------------------
# audit — generate a categorized package report
# ---------------------------------------------------------------------------
cmd_audit() {
    local report="$REPORT_DIR/pkg-audit-${DATE_STAMP}.txt"

    info "Collecting installed packages..."

    # Collect repo-managed packages (parsed from bootstrap.sh + apps.sh)
    local -A known_pkgs=()
    collect_known_packages known_pkgs
    local known_count="${#known_pkgs[@]}"

    # All installed RPM package names
    local -A all_installed=()
    while IFS= read -r pkg; do
        [[ -n "$pkg" ]] && all_installed["$pkg"]=1
    done < <(rpm -qa --qf '%{NAME}\n' | sort -u)

    # Leaf packages (nothing depends on them) — primary source for removal candidates.
    # Works on fresh installs where --userinstalled returns nothing.
    # dnf5 leaves prefixes leaf packages with "- " and dependents with "  "
    local -A leaves=()
    while IFS= read -r line; do
        if [[ "$line" == "- "* ]]; then
            # Format: "- name-epoch:version-release.arch"
            # Strip prefix, then remove everything from the epoch separator onward
            local nvra="${line#- }"
            local name="${nvra%-[0-9]*:*}"
            [[ -n "$name" ]] && leaves["$name"]=1
        fi
    done < <(dnf5 leaves 2>/dev/null || true)
    local leaf_count="${#leaves[@]}"

    # Categorize leaves: repo-managed vs removal candidate
    local -a leaf_repo_managed=()
    local -a leaf_candidates=()

    if (( leaf_count > 0 )); then
        for pkg in $(printf '%s\n' "${!leaves[@]}" | sort); do
            if [[ -v known_pkgs["$pkg"] ]]; then
                leaf_repo_managed+=("$pkg")
            else
                leaf_candidates+=("$pkg")
            fi
        done
    fi

    # Repo-managed packages found on this system (non-leaf)
    local -a repo_managed_installed=()
    if (( known_count > 0 )); then
        for pkg in $(printf '%s\n' "${!known_pkgs[@]}" | sort); do
            if [[ -v all_installed["$pkg"] ]] && ! [[ -v leaves["$pkg"] ]]; then
                repo_managed_installed+=("$pkg")
            fi
        done
    fi

    # Helper: format a package line with size and install date
    _pkg_line() {
        local pkg="$1"
        local size_bytes
        size_bytes=$(rpm -q --qf '%{SIZE}' "$pkg" 2>/dev/null || echo "0")
        local size_mb=$(( size_bytes / 1048576 ))
        local install_date
        install_date=$(rpm -q --qf '%{INSTALLTIME:date}' "$pkg" 2>/dev/null || echo "unknown")
        printf "  %-35s  %4s MB  %s\n" "$pkg" "$size_mb" "$install_date"
    }

    # Generate report
    {
        echo "Package Audit Report — $(date '+%Y-%m-%d %H:%M')"
        echo "=================================================="
        echo ""
        echo "Total installed packages: ${#all_installed[@]}"
        echo "Repo-managed packages parsed: $known_count"
        echo "Leaf packages found: $leaf_count"
        echo ""

        echo "--- LEAF CANDIDATES (${#leaf_candidates[@]} packages — review for removal) ---"
        echo "Nothing depends on these. Safe to remove individually."
        echo ""
        for pkg in "${leaf_candidates[@]}"; do
            _pkg_line "$pkg"
        done

        echo ""
        echo "--- REPO-MANAGED LEAVES (${#leaf_repo_managed[@]} packages — keep) ---"
        echo "Leaf packages that are managed by bootstrap.sh or apps.sh."
        echo ""
        for pkg in "${leaf_repo_managed[@]}"; do
            _pkg_line "$pkg"
        done

        echo ""
        echo "--- REPO-MANAGED INSTALLED (${#repo_managed_installed[@]} packages — reference) ---"
        echo "Non-leaf packages from bootstrap.sh/apps.sh found on this system."
        echo ""
        for pkg in "${repo_managed_installed[@]}"; do
            _pkg_line "$pkg"
        done

        # Flatpak section
        echo ""
        echo "--- FLATPAKS ---"
        echo ""
        local -A known_flatpaks=()
        collect_known_flatpaks known_flatpaks
        while IFS=$'\t' read -r app_id _name; do
            if [[ -v known_flatpaks["$app_id"] ]]; then
                printf "  %-45s  [repo-managed]\n" "$app_id"
            else
                printf "  %-45s  [not in repo]\n" "$app_id"
            fi
        done < <(flatpak list --user --app --columns=application,name 2>/dev/null || true)

    } > "$report"

    ok "Report written to: $report"
    echo ""
    echo "Summary:"
    echo "  Leaf candidates:       ${#leaf_candidates[@]} (review for removal)"
    echo "  Repo-managed leaves:   ${#leaf_repo_managed[@]} (keep)"
    echo "  Repo-managed (other):  ${#repo_managed_installed[@]} (reference)"
    echo ""
    echo "Review: less $report"
}

# ---------------------------------------------------------------------------
# remove — safely remove packages with dependency review
# ---------------------------------------------------------------------------
cmd_remove() {
    if [[ $# -eq 0 ]]; then
        echo "ERROR: No packages specified." >&2
        echo "Usage: $(basename "$0") remove <package>..." >&2
        exit 1
    fi

    local log="$REPORT_DIR/pkg-removed-${DATE_STAMP}.log"

    # Check against repo-managed packages
    local -A known_pkgs=()
    collect_known_packages known_pkgs

    for pkg in "$@"; do
        echo ""
        echo "=========================================="
        echo "  Package: $pkg"
        echo "=========================================="

        # Verify package is installed
        if ! rpm -q "$pkg" &>/dev/null; then
            warn "$pkg is not installed — skipping"
            continue
        fi

        # Warn if repo-managed
        if [[ -v known_pkgs["$pkg"] ]]; then
            warn "$pkg is managed by this repo (bootstrap.sh or apps.sh)."
            warn "Removing it may cause issues on next bootstrap run."
            echo ""
        fi

        # Show reverse dependencies
        echo "Reverse dependencies (packages that require $pkg):"
        local rev_deps
        rev_deps=$(dnf5 repoquery --installed --whatrequires "$pkg" --qf '%{name}' 2>/dev/null | sort -u)
        if [[ -n "$rev_deps" ]]; then
            echo "$rev_deps" | sed 's/^/  /'
        else
            echo "  (none — this is a leaf package)"
        fi
        echo ""

        # Dry-run removal
        echo "Dry-run — dnf would remove:"
        echo "---"
        sudo dnf remove --assumeno "$pkg" 2>&1 | tail -n +2 || true
        echo "---"
        echo ""

        # Prompt
        read -rp "Remove $pkg? [y/N] " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            sudo dnf remove -y "$pkg"
            echo "$(date '+%Y-%m-%d %H:%M:%S') REMOVED $pkg" >> "$log"
            ok "$pkg removed"
        else
            info "$pkg skipped"
        fi
    done

    if [[ -f "$log" ]]; then
        echo ""
        echo "Removal log: $log"
    fi
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
if [[ $# -eq 0 ]]; then
    usage
fi

case "$1" in
    audit)
        shift
        cmd_audit "$@"
        ;;
    remove)
        shift
        cmd_remove "$@"
        ;;
    -h|--help)
        usage
        ;;
    *)
        echo "ERROR: Unknown command: $1" >&2
        echo "Run '$(basename "$0") --help' for usage." >&2
        exit 1
        ;;
esac
