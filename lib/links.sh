# shellcheck shell=bash
# lib/links.sh -- Symlink management library
# Sourced by other scripts, not executed directly.
# Requires: lib/common.sh sourced first (provides ok() and warn())

# link_file <src> <dst>
# Idempotent symlink creator with backup of existing files.
link_file() {
    local src="$1"
    local dst="$2"

    if [[ ! -e "$src" ]]; then
        warn "Source does not exist, skipping: $src"
        return 0
    fi

    mkdir -p "$(dirname "$dst")"

    if [[ "$(readlink "$dst" 2>/dev/null)" == "$src" ]]; then
        ok "$dst already linked (skipped)"
        return 0
    fi

    if [[ -L "$dst" ]]; then
        rm "$dst"
    elif [[ -e "$dst" ]]; then
        local bak
        bak="$dst.bak.$(date +%Y%m%d%H%M%S)"
        warn "Backing up existing file: $dst → $bak"
        mv "$dst" "$bak"
    fi

    ln -s "$src" "$dst"
    ok "$dst → $src"
}

# ensure_local_override <dst> [comment_char]
# Create per-machine override file if missing.
ensure_local_override() {
    local dst="$1"
    local comment="${2:-#}"

    if [[ -e "$dst" ]]; then
        ok "Local override exists (kept): $dst"
        return 0
    fi

    mkdir -p "$(dirname "$dst")"
    cat > "$dst" <<EOF
${comment} Local overrides for this machine (not tracked by git).
${comment} Settings here take precedence over the base config.
EOF
    ok "Created local override: $dst"
}

# check_link <src> <dst>
# Returns status string: "ok", "missing", "wrong", "blocked", "src_missing"
check_link() {
    local src="$1" dst="$2"
    [[ ! -e "$src" ]] && { echo "src_missing"; return; }
    [[ ! -e "$dst" && ! -L "$dst" ]] && { echo "missing"; return; }
    [[ "$(readlink "$dst" 2>/dev/null)" == "$src" ]] && { echo "ok"; return; }
    [[ -L "$dst" ]] && { echo "wrong"; return; }
    echo "blocked"
}
