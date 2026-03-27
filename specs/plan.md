# Implementation Plan

Concrete, step-by-step plan to migrate from v1 to the architecture described in `specs/architecture-v2.md`.

Each phase produces a working system. Old scripts in `scripts/` remain functional until their replacement is complete and tested. At the end, `scripts/` is removed.

---

## Phase 1 — Foundation: `lib/config.sh` + `profiles/`

**Goal:** INI profile parser that all modules will depend on.

### 1.1 Create `profiles/default.conf`

```ini
[system]
hostname = fedora
keyboard_layout = fr

[theme]
accent = green
gtk_theme = Adwaita-dark
icon_theme = Tela
cursor_theme = Adwaita

[shell]
default_shell = bash

[apps]
desktop_toolkit = qt
```

### 1.2 Create `profiles/local.conf.sample`

Documented example for users to copy to `local.conf`:

```ini
# Copy this file to local.conf and uncomment the lines you want to override.
# local.conf is gitignored.

# [system]
# hostname = workstation

# [theme]
# accent = orange
```

### 1.3 Add `profiles/local.conf` to `.gitignore`

### 1.4 Create `lib/config.sh`

Implements:

```bash
# _parse_ini <file>
# Reads an INI file into the global _CONFIG associative array.
# Keys stored as SECTION.KEY (e.g. "system.hostname").
# Lines with # comments and blank lines are skipped.
# Values are trimmed of leading/trailing whitespace.

declare -gA _CONFIG=()

_parse_ini() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    local section=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"                       # strip inline comments
        line="${line#"${line%%[![:space:]]*}"}"   # trim leading whitespace
        line="${line%"${line##*[![:space:]]}"}"   # trim trailing whitespace
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ ^\[([a-zA-Z_]+)\]$ ]]; then
            section="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^([a-zA-Z_]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local val="${BASH_REMATCH[2]}"
            _CONFIG["${section}.${key}"]="$val"
        fi
    done < "$file"
}

# load_profile <profiles_dir>
# Parses default.conf, then overlays local.conf if present.
load_profile() {
    local dir="$1"
    _parse_ini "$dir/default.conf"
    _parse_ini "$dir/local.conf"    # overlay — later values win

    # Export as PROFILE_SECTION_KEY variables for convenience
    for key in "${!_CONFIG[@]}"; do
        local var="PROFILE_${key^^}"    # system.hostname → PROFILE_SYSTEM.HOSTNAME
        var="${var//./_}"                # PROFILE_SYSTEM.HOSTNAME → PROFILE_SYSTEM_HOSTNAME
        printf -v "$var" '%s' "${_CONFIG[$key]}"
        export "$var"
    done
}

# profile_get <section> <key>
# Returns value or empty string.
profile_get() {
    echo "${_CONFIG["${1}.${2}"]:-}"
}
```

### 1.5 Verify

- Source `lib/config.sh` in a shell, call `load_profile profiles`, confirm `PROFILE_SYSTEM_HOSTNAME` etc. are set.
- Override with `local.conf`, confirm overlay works.

### 1.6 Commit

```
phase 1: profile system (lib/config.sh + profiles/)
```

---

## Phase 2 — Color presets: `lib/colors.sh` + `colors/`

**Goal:** Data-driven color presets in files, replacing the hardcoded `COLOR_PRESETS` array.

### 2.1 Create color preset files

Create `colors/green.conf`, `colors/orange.conf`, `colors/blue.conf` with INI format:

```ini
# colors/green.conf
name = green
primary = #88DD00
dim = #557700
dark = #2A3B00
bright = #8BE235
secondary = #ffaa00
ansi = 92
```

(Same for orange and blue, using values from current `scripts/lib/common.sh:121-123`.)

### 2.2 Create `lib/colors.sh`

Extract from `scripts/lib/common.sh` (lines 109-217):

```bash
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"   # needs _parse_ini

declare -gA COLOR_PRESETS=()

# load_all_presets [colors_dir]
# Reads every *.conf in colors/ into COLOR_PRESETS.
# Each entry: "PRIMARY DIM DARK BRIGHT SECONDARY ANSI"
load_all_presets() {
    local dir="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/colors}"
    for conf in "$dir"/*.conf; do
        [[ -f "$conf" ]] || continue
        local -A _preset=()
        _parse_ini "$conf"      # reuse profile parser
        # _parse_ini writes to _CONFIG; extract what we need
        local name="${_CONFIG[".name"]:-}"
        [[ -z "$name" ]] && continue
        COLOR_PRESETS["$name"]="${_CONFIG[".primary"]} ${_CONFIG[".dim"]} ${_CONFIG[".dark"]} ${_CONFIG[".bright"]} ${_CONFIG[".secondary"]} ${_CONFIG[".ansi"]}"
        # Clean up keys for next iteration
        for k in name primary dim dark bright secondary ansi; do
            unset '_CONFIG[".'"$k"'"]' 2>/dev/null || true
        done
    done
}
```

**Note on `_parse_ini` and sectionless keys:** Color files have no `[section]` headers. `_parse_ini` will store them as `.key` (empty section + dot + key). The `load_all_presets` function reads `_CONFIG[".name"]` etc. This requires `_parse_ini` to handle sectionless lines — the current implementation already does this since `section` starts as empty string, producing keys like `.name`.

Move these functions verbatim from `scripts/lib/common.sh`:

| Function | Source lines | Notes |
|----------|-------------|-------|
| `load_accent()` | common.sh:131-155 | Change: read ACCENT from `PROFILE_THEME_ACCENT` instead of sourcing env files. Fallback to env files if profile not loaded. |
| `apply_accent()` | common.sh:162-217 | Verbatim copy. No changes needed. |

Updated `load_accent`:

```bash
load_accent() {
    # Prefer profile, fall back to ACCENT env var, then "green"
    local accent="${PROFILE_THEME_ACCENT:-${ACCENT:-green}}"

    # Ensure presets are loaded
    [[ ${#COLOR_PRESETS[@]} -eq 0 ]] && load_all_presets

    if [[ -z "${COLOR_PRESETS[$accent]+x}" ]]; then
        warn "Unknown accent '$accent', falling back to green"
        accent="green"
    fi

    read -r ACCENT_PRIMARY ACCENT_DIM ACCENT_DARK ACCENT_BRIGHT ACCENT_SECONDARY ACCENT_ANSI \
        <<< "${COLOR_PRESETS[$accent]}"
    ACCENT_NAME="$accent"
}
```

### 2.3 Verify

- Source `lib/colors.sh`, call `load_all_presets`, confirm 3 presets loaded.
- Add a `colors/purple.conf`, confirm it loads as a 4th preset without code changes.
- Call `load_accent` with `PROFILE_THEME_ACCENT=orange`, confirm `ACCENT_PRIMARY` is `#ff8800`.

### 2.4 Commit

```
phase 2: data-driven color presets (lib/colors.sh + colors/)
```

---

## Phase 3 — Symlink helpers: `lib/links.sh`

**Goal:** Extract `link_file` and `ensure_local_override` from `scripts/dotfiles.sh` into a reusable library.

### 3.1 Create `lib/links.sh`

Extract from `scripts/dotfiles.sh`:
- `link_file()` (lines 67-94) — verbatim
- `ensure_local_override()` (lines 101-116) — verbatim

Add one new function for diff/status:

```bash
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
```

### 3.2 Verify

- Source `lib/links.sh`, test `check_link` against existing symlinks, missing files, wrong symlinks.

### 3.3 Commit

```
phase 3: symlink helpers (lib/links.sh)
```

---

## Phase 4 — Trim `lib/common.sh`

**Goal:** `lib/common.sh` becomes the core utility library. Color and link functions are removed (they live in `lib/colors.sh` and `lib/links.sh`).

### 4.1 Create `lib/common.sh`

Copy from `scripts/lib/common.sh`, keeping only:
- `info()`, `ok()`, `warn()` (lines 11-13)
- `init_logging()` (lines 20-26)
- `preflight_checks()` (lines 32-41)
- `require_cmd()` (lines 47-54)
- `PKG_MANIFEST`, `FLATPAK_MANIFEST` (lines 59-60)
- `pkg_install()` (lines 66-74)
- `ensure_bashrc_source()` (lines 80-87)
- `find_fedora_version()` (lines 95-107)

Remove:
- `COLOR_PRESETS` declaration (line 120-123) → now in `lib/colors.sh`
- `load_accent()` (lines 131-155) → now in `lib/colors.sh`
- `apply_accent()` (lines 162-217) → now in `lib/colors.sh`

### 4.2 Verify

- Source `lib/common.sh`, confirm logging and package functions work.
- Confirm `COLOR_PRESETS` is NOT defined (it's in colors.sh now).

### 4.3 Commit

```
phase 4: trim lib/common.sh (colors/links extracted)
```

---

## Phase 5 — `modules/system.sh`

**Goal:** Hostname, keyboard layout, GPU groups, firewall, bluetooth, tuned.

### 5.1 Extract from `scripts/bootstrap.sh`

| Source section | Lines | Target function |
|---------------|-------|-----------------|
| Mode detection | 102-123 | internal `_detect_mode()` |
| Machine detection (GPU) | 135-139 | internal `_detect_gpu()` |
| Hostname | 144-151 | `system::apply` |
| Firewall | 260-263 | `system::apply` |
| GPU groups | 271-277 | `system::apply` |
| Keyboard layout | 389-391 | `system::apply` |
| Bluetooth + tuned enable | 257-258 | `system::apply` |

### 5.2 Implement contract

```bash
system::check() {
    local changes=false
    local target_hostname
    target_hostname="$(profile_get system hostname)"

    [[ "$(hostname -s)" != "$target_hostname" ]] && changes=true

    local target_kb
    target_kb="$(profile_get system keyboard_layout)"
    local current_kb
    current_kb=$(localectl status | sed -n 's/.*X11 Layout: //p')
    [[ "$current_kb" != "$target_kb" ]] && changes=true

    # GPU group check
    if _detect_gpu; then
        id -nG | grep -qw video || changes=true
        id -nG | grep -qw render || changes=true
    fi

    # Firewall
    systemctl is-active firewalld &>/dev/null || changes=true

    # Services
    systemctl is-enabled bluetooth &>/dev/null || changes=true
    systemctl is-enabled tuned &>/dev/null || changes=true

    $changes && return 0 || return 1
}

system::preview() {
    # Print each check with current → target
    info "[system] Preview:"
    local target_hostname
    target_hostname="$(profile_get system hostname)"
    echo "  Hostname:  $(hostname -s) → $target_hostname"
    # ... (same pattern for keyboard, GPU, firewall, services)
}

system::apply() {
    # Execute hostnamectl, localectl, usermod, systemctl
    # (code from bootstrap.sh, adapted to read from profile)
}

system::status() {
    echo "  hostname=$(hostname -s) keyboard=$(localectl status | sed -n 's/.*X11 Layout: //p') firewall=$(systemctl is-active firewalld 2>/dev/null || echo inactive)"
}
```

### 5.3 Module-specific flags

- `--sway-spin` / `--kde-spin`: override auto-detection for mode persistence.
- Sway Spin mode is still persisted to `~/.config/shell/.bootstrap-mode`.

### 5.4 Commit

```
phase 5: modules/system.sh (hostname, keyboard, GPU, firewall, services)
```

---

## Phase 6 — `modules/packages.sh`

**Goal:** System packages, repos, codecs, Sway stack, CLI tools, Yubikey.

### 6.1 Extract from `scripts/bootstrap.sh`

| Source section | Lines | Notes |
|---------------|-------|-------|
| System update | 158-162 | `dnf update -y` + dnf-plugins-core |
| RPM Fusion + codecs | 168-189 | Repo install + ffmpeg/mesa swap |
| Flatpak/Flathub | 195-198 | `flatpak remote-add` |
| Sway + Wayland | 204-258 | Conditional on Sway Spin mode. Uses `SWAY_COMMON_PKGS` array + extras for base Fedora. |
| ROCm | 279-318 | Conditional on `--rocm` flag + GPU detection |
| Yubikey | 324-328 | `pam-u2f`, `yubikey-manager` |
| CLI tools | 334-347 | `btop`, `curl`, `fd-find`, `fzf`, etc. |

### 6.2 Implement contract

```bash
# Package lists (sorted alphabetically, one per line)
_SWAY_COMMON_PKGS=( bat bemenu bluez fish ... )
_SWAY_EXTRA_PKGS=( grim kanshi mako slurp sway swaybg swayidle swaylock waybar wl-clipboard xdg-desktop-portal-wlr )
_CLI_PKGS=( btop curl fd-find fzf git htop p7zip ripgrep tmux unzip wget )
_SECURITY_PKGS=( pam-u2f yubikey-manager )

packages::check() {
    # Build target list based on mode + flags
    # Check each with rpm -q, return 0 if any missing
}

packages::preview() {
    info "[packages] Preview:"
    echo "  Repos to configure:"
    # List repos that don't exist yet (RPM Fusion, Flathub)
    echo "  Packages to install:"
    # List packages not yet installed
    echo "  Codec swaps:"
    # List pending swaps (ffmpeg-free → ffmpeg, mesa-va-drivers swap)
}

packages::apply() {
    # DNF operations from bootstrap.sh sections 1-5, 6, 7
    # Read Sway Spin mode from persisted file (set by system module)
}
```

### 6.3 Module-specific flags

- `--rocm`: include ROCm packages (from bootstrap.sh lines 279-318)
- `--sway-spin` / `--kde-spin`: override mode detection (affects package list)

### 6.4 Commit

```
phase 6: modules/packages.sh (system packages, repos, codecs)
```

---

## Phase 7 — `modules/shell-env.sh`

**Goal:** Generate `~/.config/shell/bootstrap-env.sh` and ensure `.bashrc` sources it.

### 7.1 Extract from `scripts/bootstrap.sh`

Source: lines 353-383 (section 8: Shell Environment).

### 7.2 Implement contract

```bash
_generate_env_content() {
    cat <<'EOF'
# Managed by ./setup shell-env
# Do not edit manually; changes will be overwritten.

alias docker=podman
export KIND_EXPERIMENTAL_PROVIDER=podman
export QT_QPA_PLATFORMTHEME=kde
export QT_STYLE_OVERRIDE=Breeze
unset SSH_ASKPASS
EOF
}

shell-env::check() {
    local target
    target="$(_generate_env_content)"
    local current=""
    [[ -f "$HOME/.config/shell/bootstrap-env.sh" ]] && \
        current="$(cat "$HOME/.config/shell/bootstrap-env.sh")"
    [[ "$target" != "$current" ]] && return 0

    # Also check .bashrc source line
    grep -qF "bootstrap-env.sh" "$HOME/.bashrc" 2>/dev/null || return 0

    return 1
}

shell-env::preview() {
    info "[shell-env] Preview:"
    local deployed="$HOME/.config/shell/bootstrap-env.sh"
    if [[ -f "$deployed" ]]; then
        echo "  Changes to bootstrap-env.sh:"
        diff <(_generate_env_content) "$deployed" || true
    else
        echo "  Will create: ~/.config/shell/bootstrap-env.sh"
        _generate_env_content | sed 's/^/    /'
    fi
}

shell-env::apply() {
    mkdir -p "$HOME/.config/shell"
    _generate_env_content > "$HOME/.config/shell/bootstrap-env.sh"
    ensure_bashrc_source
    ok "Shell environment configured"
}

shell-env::status() {
    if [[ -f "$HOME/.config/shell/bootstrap-env.sh" ]]; then
        local count
        count=$(grep -c '^export\|^alias\|^unset' "$HOME/.config/shell/bootstrap-env.sh")
        echo "  bootstrap-env.sh deployed, $count directives"
    else
        echo "  bootstrap-env.sh NOT deployed"
    fi
}
```

### 7.3 Commit

```
phase 7: modules/shell-env.sh (bootstrap-env.sh generation)
```

---

## Phase 8 — `modules/dotfiles.sh`

**Goal:** Symlink deployment with dry-run, diff, and status capabilities.

### 8.1 Define symlink map

Replace the imperative code in `scripts/dotfiles.sh` with a declarative map:

```bash
# Format: "source_relative|target_absolute|condition"
# Conditions: "always", "sway", "fish"
_SYMLINK_MAP=(
    # Sway/Wayland (conditional)
    "sway/config|$HOME/.config/sway/config|sway"
    "waybar/config|$HOME/.config/waybar/config|sway"
    "waybar/style.css|$HOME/.config/waybar/style.css|sway"
    "waybar/scripts|$HOME/.config/waybar/scripts|sway"
    "kanshi/config|$HOME/.config/kanshi/config|sway"
    "swaylock/config|$HOME/.config/swaylock/config|sway"

    # GTK (single source → dual targets)
    "gtk/settings.ini|$HOME/.config/gtk-3.0/settings.ini|always"
    "gtk/settings.ini|$HOME/.config/gtk-4.0/settings.ini|always"

    # Qt
    "qt5ct/qt5ct.conf|$HOME/.config/qt5ct/qt5ct.conf|always"
    "qt6ct/qt6ct.conf|$HOME/.config/qt6ct/qt6ct.conf|always"

    # KDE
    "kde/kdeglobals|$HOME/.config/kdeglobals|always"

    # Shell
    "bash/prompt.sh|$HOME/.config/shell/prompt.sh|always"
    "bash/completions.sh|$HOME/.config/shell/completions.sh|always"

    # Fish (conditional)
    "fish/config.fish|$HOME/.config/fish/config.fish|fish"
    "fish/conf.d/01-environment.fish|$HOME/.config/fish/conf.d/01-environment.fish|fish"
    "fish/conf.d/02-colors.fish|$HOME/.config/fish/conf.d/02-colors.fish|fish"
    "fish/conf.d/03-abbreviations.fish|$HOME/.config/fish/conf.d/03-abbreviations.fish|fish"
    "fish/conf.d/04-keybinds.fish|$HOME/.config/fish/conf.d/04-keybinds.fish|fish"
    "fish/functions/fish_prompt.fish|$HOME/.config/fish/functions/fish_prompt.fish|fish"
    "fish/functions/fish_right_prompt.fish|$HOME/.config/fish/functions/fish_right_prompt.fish|fish"
    "fish/functions/fish_greeting.fish|$HOME/.config/fish/functions/fish_greeting.fish|fish"
    "fish/functions/fish_mode_prompt.fish|$HOME/.config/fish/functions/fish_mode_prompt.fish|fish"
    "fish/functions/md.fish|$HOME/.config/fish/functions/md.fish|fish"

    # Apps
    "dunst/dunstrc|$HOME/.config/dunst/dunstrc|always"
    "kitty/kitty.conf|$HOME/.config/kitty/kitty.conf|always"
    "tmux/tmux.conf|$HOME/.config/tmux/tmux.conf|always"
)

# Local override files (created once, never overwritten)
_LOCAL_OVERRIDES=(
    "$HOME/.config/sway/config.local|#|sway"
    "$HOME/.config/fish/config.local.fish|#|fish"
    "$HOME/.config/dunst/dunstrc.local|#|always"
    "$HOME/.config/kitty/config.local|#|always"
    "$HOME/.config/tmux/local.conf|#|always"
)
```

### 8.2 Condition evaluation

```bash
_condition_met() {
    case "$1" in
        always) return 0 ;;
        sway)   command -v sway &>/dev/null ;;
        fish)   command -v fish &>/dev/null ;;
        *)      return 1 ;;
    esac
}
```

### 8.3 Implement contract

```bash
dotfiles::check() {
    local config_dir="$REPO_ROOT/config"
    for entry in "${_SYMLINK_MAP[@]}"; do
        IFS='|' read -r rel dst cond <<< "$entry"
        _condition_met "$cond" || continue
        local src="$config_dir/$rel"
        local status
        status=$(check_link "$src" "$dst")
        [[ "$status" != "ok" ]] && return 0
    done
    return 1
}

dotfiles::preview() {
    info "[dotfiles] Preview:"
    local config_dir="$REPO_ROOT/config"
    for entry in "${_SYMLINK_MAP[@]}"; do
        IFS='|' read -r rel dst cond <<< "$entry"
        _condition_met "$cond" || continue
        local src="$config_dir/$rel"
        local status
        status=$(check_link "$src" "$dst")
        local tag
        case "$status" in
            ok)         tag="[OK]" ;;
            missing)    tag="[WILL CREATE]" ;;
            wrong)      tag="[WILL RELINK]" ;;
            blocked)    tag="[WILL BACKUP + LINK]" ;;
            src_missing) tag="[SOURCE MISSING]" ;;
        esac
        printf "  %-20s → %-45s %s\n" "config/$rel" "$dst" "$tag"
    done
}

dotfiles::apply() {
    local config_dir="$REPO_ROOT/config"
    for entry in "${_SYMLINK_MAP[@]}"; do
        IFS='|' read -r rel dst cond <<< "$entry"
        _condition_met "$cond" || continue
        link_file "$config_dir/$rel" "$dst"
    done

    # Local overrides
    for entry in "${_LOCAL_OVERRIDES[@]}"; do
        IFS='|' read -r dst comment cond <<< "$entry"
        _condition_met "$cond" || continue
        ensure_local_override "$dst" "$comment"
    done

    # .bashrc source lines (idempotent)
    _ensure_bashrc_line "prompt.sh" \
        '[[ -f "$HOME/.config/shell/prompt.sh" ]] && source "$HOME/.config/shell/prompt.sh"'
    _ensure_bashrc_line "completions.sh" \
        '[[ -f "$HOME/.config/shell/completions.sh" ]] && source "$HOME/.config/shell/completions.sh"'

    # Make waybar scripts executable
    if _condition_met "sway" && compgen -G "$config_dir/waybar/scripts/*.sh" >/dev/null 2>&1; then
        chmod +x "$config_dir"/waybar/scripts/*.sh
    fi

    ok "Dotfiles deployed"
}

dotfiles::status() {
    local config_dir="$REPO_ROOT/config"
    local total=0 linked=0
    for entry in "${_SYMLINK_MAP[@]}"; do
        IFS='|' read -r rel dst cond <<< "$entry"
        _condition_met "$cond" || continue
        total=$((total + 1))
        [[ "$(check_link "$config_dir/$rel" "$dst")" == "ok" ]] && linked=$((linked + 1))
    done
    echo "  ${linked}/${total} symlinks active"
}
```

### 8.4 `_ensure_bashrc_line` helper

```bash
_ensure_bashrc_line() {
    local marker="$1" line="$2"
    grep -qF "$marker" "$HOME/.bashrc" 2>/dev/null || echo "$line" >> "$HOME/.bashrc"
}
```

### 8.5 Commit

```
phase 8: modules/dotfiles.sh (declarative symlink map + diff/status)
```

---

## Phase 9 — `modules/theme.sh`

**Goal:** Merge `scripts/theme-accent-color.sh` + `scripts/theme-sddm.sh` into a single module with improved error handling and maintainability (see architecture-v2.md section 12).

### 9.1 Constants

Replace hardcoded paths scattered throughout the module with constants at the top:

```bash
_SDDM_THEME_BASE="/usr/share/sddm/themes"
_TELA_ICON_BASE="$HOME/.local/share/icons"
```

All references to `/usr/share/sddm/themes/` and `$HOME/.local/share/icons/Tela-` use these constants.

### 9.2 Accent file lists

Declarative arrays (replaces `_accent_files` from theme-accent-color.sh:357-373):

```bash
_ACCENT_HEX_FILES=(
    "kitty/kitty.conf"
    "tmux/tmux.conf"
    "dunst/dunstrc"
    "sddm/theme.conf"
    "gtk/settings.ini"
    "kde/kdeglobals"
    "fish/conf.d/02-colors.fish"
)

_ACCENT_SWAY_FILES=(
    "sway/config"
    "waybar/style.css"
    "swaylock/config"
)

_ACCENT_BASH_PROMPT="bash/prompt.sh"
```

### 9.3 Merge detection functions

Replace three near-identical functions (`_detect_preset()`, `_detect_preset_bare()`, `_detect_bash_prompt()`) with a single unified function:

```bash
# _detect_preset_in_file <file> <method>
# method: "hex"  — match PRIMARY color with '#' prefix (most config files)
#         "bare" — match PRIMARY color without '#' (swaylock)
#         "ansi" — match ANSI code number (bash prompt)
# Returns: preset name, "missing", "broken", "unknown", or "mixed(a+b)"
_detect_preset_in_file() {
    local file="$1"
    local method="$2"
    [[ -f "$file" ]] || { echo "missing"; return; }

    # Check for leftover placeholders (interrupted run)
    if grep -q '@@[A-Za-z_]*@@' "$file" 2>/dev/null; then
        echo "broken"
        return
    fi

    # ANSI method has completely different matching logic
    if [[ "$method" == "ansi" ]]; then
        local ansi_code
        ansi_code=$(sed -n 's/^_GREEN="\$(_pc \([0-9]*\))".*/\1/p' "$file")
        [[ -z "$ansi_code" ]] && { echo "unknown"; return; }
        local preset
        for preset in "${!COLOR_PRESETS[@]}"; do
            read -r _p _d _dk _br _s ansi <<< "${COLOR_PRESETS[$preset]}"
            [[ "$ansi_code" == "$ansi" ]] && { echo "$preset"; return; }
        done
        echo "unknown(ANSI=$ansi_code)"
        return
    fi

    # hex/bare: scan for primary color of each preset
    local found="" count=0
    local preset
    for preset in "${!COLOR_PRESETS[@]}"; do
        read -r p _rest <<< "${COLOR_PRESETS[$preset]}"
        local needle="$p"
        [[ "$method" == "bare" ]] && needle="${p#\#}"
        if grep -qi "${needle}" "$file" 2>/dev/null; then
            found="${found:+${found}+}${preset}"
            count=$(( count + 1 ))
        fi
    done

    if [[ "$count" -eq 0 ]]; then
        echo "unknown"
    elif [[ "$count" -eq 1 ]]; then
        echo "$found"
    else
        echo "mixed($found)"
    fi
}
```

Update all call sites:
- `audit_accents()`: change `_detect_preset "$f"` → `_detect_preset_in_file "$f" hex`, etc.
- `theme::check()` and `theme::preview()`: same replacement.

### 9.4 Extract shared detection loop

Both `theme::check()` and `theme::preview()` iterate `_ACCENT_HEX_FILES` + `_ACCENT_SWAY_FILES` with identical detection logic. Extract into a helper that returns structured results:

```bash
# _detect_all_files
# Populates _DETECT_RESULTS associative array: file → detected preset name
# Must call load_all_presets + load_accent before calling.
declare -gA _DETECT_RESULTS=()

_detect_all_files() {
    _DETECT_RESULTS=()
    local config_dir="$REPO_ROOT/config"
    local f

    for f in "${_ACCENT_HEX_FILES[@]}"; do
        _DETECT_RESULTS["$f"]=$(_detect_preset_in_file "$config_dir/$f" hex)
    done

    # Sway files: only detect if sway is present
    if command -v sway &>/dev/null; then
        for f in "${_ACCENT_SWAY_FILES[@]}"; do
            _DETECT_RESULTS["$f"]=$(_detect_preset_in_file "$config_dir/$f" hex)
        done
    fi

    # Bash prompt
    _DETECT_RESULTS["$_ACCENT_BASH_PROMPT"]=$(
        _detect_preset_in_file "$config_dir/$_ACCENT_BASH_PROMPT" ansi
    )
}
```

Usage in `theme::check()` — short-circuit on first mismatch:

```bash
theme::check() {
    # ... flag parsing, load_all_presets, load_accent ...
    _detect_all_files
    local f
    for f in "${!_DETECT_RESULTS[@]}"; do
        [[ "${_DETECT_RESULTS[$f]}" != "$ACCENT_NAME" ]] && return 0
    done
    # Check icon theme
    [[ ! -d "${_TELA_ICON_BASE}/Tela-${ACCENT_NAME}" ]] && return 0
    return 1
}
```

Usage in `theme::preview()` — format full table:

```bash
theme::preview() {
    # ... flag parsing, load_all_presets, load_accent ...
    _detect_all_files
    echo "  Config file status:"
    local f
    for f in "${!_DETECT_RESULTS[@]}"; do
        local detected="${_DETECT_RESULTS[$f]}"
        local status="OK"
        [[ "$detected" != "$ACCENT_NAME" ]] && status="WILL UPDATE ($detected → $ACCENT_NAME)"
        printf "    %-40s %s\n" "config/$f" "$status"
    done
    # ... icon theme and SDDM status ...
}
```

### 9.5 Split `_apply_sddm()`

Break the 107-line `_apply_sddm()` into focused helpers:

```bash
# _install_sddm_corners <theme_dir>
# Git clones sddm-theme-corners, applies Qt6 patch, adds dark background.
_install_sddm_corners() {
    local sddm_theme_dir="$1"

    pkg_install qt6-qt5compat qt6-qtsvg

    if [[ -d "$sddm_theme_dir" ]]; then
        ok "sddm-theme-corners already installed (skipped)"
    else
        local corners_tmp="${_THEME_TMPDIR}/corners"
        if ! git clone --depth 1 https://github.com/aczw/sddm-theme-corners.git "$corners_tmp" 2>&1; then
            warn "Failed to clone sddm-theme-corners — skipping"
            return 0
        fi
        sudo cp -r "$corners_tmp/corners" "$sddm_theme_dir" \
            || { warn "Failed to install sddm-theme-corners"; return 0; }
        ok "sddm-theme-corners installed"
    fi

    sudo chmod -R a+rX "$sddm_theme_dir"

    # Qt5 → Qt6 patch
    if compgen -G "$sddm_theme_dir/components/*.qml" >/dev/null; then
        sudo sed -i 's/import QtGraphicalEffects.*/import Qt5Compat.GraphicalEffects/' \
            "$sddm_theme_dir"/components/*.qml
    fi

    # Dark background color
    if [[ -f "$sddm_theme_dir/Main.qml" ]]; then
        if ! sudo grep -q 'color: "#222222"' "$sddm_theme_dir/Main.qml"; then
            sudo sed -i '/id: root/a\    color: "#222222"' "$sddm_theme_dir/Main.qml"
        fi
    fi

    # Deploy theme.conf with accent colors
    local theme_tmp="${_THEME_TMPDIR}/sddm-theme.conf"
    cp "$REPO_ROOT/config/sddm/theme.conf" "$theme_tmp"
    apply_accent "$theme_tmp"
    sudo cp "$theme_tmp" "$sddm_theme_dir/theme.conf"
    sudo chmod 644 "$sddm_theme_dir/theme.conf"
}

# _apply_sddm_stock <theme_dir>
# Configures stock Fedora SDDM theme with dark grey background.
_apply_sddm_stock() {
    local sddm_theme_dir="$1"
    local bg_src="$REPO_ROOT/config/sddm/background-dark-grey.png"

    if [[ ! -d "$sddm_theme_dir" ]]; then
        warn "Stock SDDM theme not found at $sddm_theme_dir — is sddm installed?"
        return 0
    fi

    sudo cp "$bg_src" "$sddm_theme_dir/background-dark-grey.png" \
        || { warn "Failed to copy SDDM background"; return 0; }
    sudo chmod 644 "$sddm_theme_dir/background-dark-grey.png"

    local user_conf_tmp="${_THEME_TMPDIR}/sddm-user.conf"
    printf '[General]\nbackground=background-dark-grey.png\n' > "$user_conf_tmp"
    if ! sudo cmp -s "$user_conf_tmp" "$sddm_theme_dir/theme.conf.user" 2>/dev/null; then
        sudo cp "$user_conf_tmp" "$sddm_theme_dir/theme.conf.user"
        sudo chmod 644 "$sddm_theme_dir/theme.conf.user"
    fi
    ok "Dark grey background applied to stock SDDM theme"
}

# _set_sddm_active_theme <theme_name>
# Writes /etc/sddm.conf.d/theme.conf, disables greetd if active, enables sddm.
_set_sddm_active_theme() {
    local theme_name="$1"
    local sddm_conf_tmp="${_THEME_TMPDIR}/sddm-active.conf"
    printf '[Theme]\nCurrent=%s\n' "$theme_name" > "$sddm_conf_tmp"
    sudo mkdir -p /etc/sddm.conf.d
    if ! sudo cmp -s "$sddm_conf_tmp" /etc/sddm.conf.d/theme.conf 2>/dev/null; then
        sudo cp "$sddm_conf_tmp" /etc/sddm.conf.d/theme.conf
        sudo chmod 644 /etc/sddm.conf.d/theme.conf
    fi

    if systemctl is-enabled greetd &>/dev/null; then
        sudo systemctl disable greetd
    fi
    sudo systemctl enable sddm
    ok "SDDM configured (theme: $theme_name)"
}

# _apply_sddm — Orchestrator
# Calls the appropriate variant based on --corners flag, then sets active theme.
_apply_sddm() {
    if ! rpm -q sddm &>/dev/null; then
        info "SDDM not installed — skipping SDDM theming"
        return 0
    fi

    info "Configuring SDDM theme..."

    if [[ "$_THEME_CORNERS" == true ]]; then
        _install_sddm_corners "${_SDDM_THEME_BASE}/corners"
        _set_sddm_active_theme "corners"
    else
        _apply_sddm_stock "${_SDDM_THEME_BASE}/03-sway-fedora"
        _set_sddm_active_theme "03-sway-fedora"
    fi
}
```

### 9.6 Error handling: temp directory + trap cleanup

All temp files in `theme::apply()` are created under a single temp directory, cleaned up via trap:

```bash
_THEME_TMPDIR=""

_theme_cleanup() {
    [[ -n "$_THEME_TMPDIR" ]] && rm -rf "$_THEME_TMPDIR"
}

theme::apply() {
    _THEME_TMPDIR=$(mktemp -d)
    trap _theme_cleanup EXIT

    # ... all operations use $_THEME_TMPDIR for temp files ...
}
```

This replaces the scattered `mktemp` + `rm -f` pairs throughout the current code (currently ~6 individual temp files, each with its own `rm`).

### 9.7 Validate preset before apply

Add validation at the top of `theme::apply()` after loading:

```bash
theme::apply() {
    # ... flag parsing, load_all_presets, load_accent ...

    if [[ -z "${COLOR_PRESETS[$ACCENT_NAME]+x}" ]]; then
        warn "Unknown accent preset: $ACCENT_NAME (available: ${!COLOR_PRESETS[*]})"
        return 1
    fi

    # ... rest of apply ...
}
```

### 9.8 Consistent logging

Ensure all code paths log their outcome:

| Code path | Before | After |
|-----------|--------|-------|
| SDDM not installed | silent `return 0` | `info "SDDM not installed — skipping"` |
| Git clone fails | unhandled | `warn "Failed to clone ... — skipping"` |
| File copy to system path fails | unhandled | `warn "Failed to copy ..."` |
| Stock SDDM theme dir missing | `warn` but no return value context | `warn` + explicit `return 0` |
| Accent files updated | `ok "Config files updated"` | unchanged (already good) |
| Icon theme skipped | `ok "... already installed (skipped)"` | unchanged |

### 9.9 Module-specific flags

Unchanged from current implementation:

- `--accent <name>`: override profile accent for this run
- `--list`: call `list_presets()`, exit
- `--audit`: call `audit_accents()`, exit
- `--corners`: use sddm-theme-corners instead of stock SDDM theme

Flag parsing happens before contract dispatch. `--list` and `--audit` are read-only and bypass the check/preview/apply flow.

### 9.10 Full module structure

Final file structure after all changes:

```
modules/theme.sh
├── Constants (_SDDM_THEME_BASE, _TELA_ICON_BASE)
├── File lists (_ACCENT_HEX_FILES, _ACCENT_SWAY_FILES, _ACCENT_BASH_PROMPT)
├── Detection
│   ├── _detect_preset_in_file()      # unified — replaces 3 functions
│   └── _detect_all_files()           # shared loop — replaces duplication in check/preview
├── Display
│   ├── list_presets()                # --list handler
│   └── audit_accents()              # --audit handler (uses _detect_preset_in_file)
├── Apply helpers
│   ├── _install_tela_icon_theme()   # unchanged logic
│   ├── _install_sddm_corners()     # extracted from _apply_sddm
│   ├── _apply_sddm_stock()         # extracted from _apply_sddm
│   ├── _set_sddm_active_theme()    # extracted from _apply_sddm
│   └── _apply_sddm()               # orchestrator (now ~15 lines)
├── Error handling
│   └── _theme_cleanup()             # trap EXIT handler
├── Flag parsing
│   └── _theme_parse_flags()         # unchanged
└── Module contract
    ├── theme::check()               # uses _detect_all_files
    ├── theme::preview()             # uses _detect_all_files
    ├── theme::apply()               # trap + validate + existing logic
    └── theme::status()              # unchanged
```

### 9.11 Verify

1. `./setup theme` — dry-run preview should show same output as before.
2. `./setup theme --list` — should list all presets with colors.
3. `./setup theme --audit` — should audit all config files.
4. `./setup theme --accent orange --apply` — switch accent, verify config files updated.
5. `./setup theme --audit` — should show no anomalies after apply.
6. Interrupt `theme::apply` mid-run (Ctrl+C) — verify no temp files left behind.

### 9.12 Commit

```
phase 9: modules/theme.sh (structural improvements + error handling)
```

---

## Phase 10 — `apps.conf` + `modules/apps.sh`

**Goal:** Data-driven app registry with profile-driven toolkit selection (see architecture-v2.md section 11).

### 10.1 Create `apps.conf`

New file at repo root. INI-style with bare package names (one per line) under section headers. Section names encode package type and install conditions.

```ini
# apps.conf — App registry (single source of truth for modules/apps.sh)
# Adding/removing an app = editing this file. No code changes needed.

[browsers]
brave-browser
firefox

[mesa]
libva-utils
mesa-vdpau-drivers-freeworld
mesa-vulkan-drivers

[misc]
keepassxc
nextcloud-client

[kvm]
libvirt
libvirt-daemon-config-network
qemu-kvm
virt-install
virt-manager
virt-viewer

[desktop:gtk]
celluloid
evince
file-roller
gnome-calculator
loupe
thunar

[desktop:qt]
ark
dolphin
gwenview
haruna
kcalc
okular

[devops]
ansible
helm
kind
kubectl
podman-compose
yq

[flatpak:audio]
com.github.wwmm.easyeffects

[flatpak:comm]
com.slack.Slack
org.signal.Signal
```

Section name conventions:
- `[section]` — always-installed RPM packages
- `[section:devops]` — RPM packages, only with `--devops` flag
- `[section:gtk]` / `[section:qt]` — RPM packages, only when `desktop_toolkit` matches
- `[flatpak:section]` — always-installed Flatpak apps

### 10.2 Add `_load_apps_conf` parser to `apps.sh`

A dedicated parser in `apps.sh` — does **not** use `lib/config.sh`'s `_parse_ini` because `apps.conf` has bare lines (not `key = value` pairs). This avoids contaminating `_CONFIG` and needs no save/restore gymnastics.

```bash
declare -gA _APP_SECTIONS=()

# _load_apps_conf
# Reads apps.conf into _APP_SECTIONS: section name → space-delimited package list.
# Package names never contain spaces, so word-splitting gives arrays for free.
_load_apps_conf() {
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
```

### 10.3 Replace `_get_all_rpm_targets` and `_get_all_flatpak_targets`

The new versions iterate `_APP_SECTIONS` and filter by section name convention, replacing all the hardcoded `_*_PKGS` arrays and explicit `if/elif` blocks:

```bash
_get_all_rpm_targets() {
    local pkgs=()
    local section
    for section in "${!_APP_SECTIONS[@]}"; do
        # Skip Flatpak sections
        [[ "$section" == flatpak:* ]] && continue

        # Check qualifier (portion after ':')
        local qualifier="${section#*:}"
        [[ "$qualifier" == "$section" ]] && qualifier=""   # no ':' found

        case "$qualifier" in
            "")     ;;   # always included
            devops) [[ "$_APPS_INSTALL_DEVOPS" == "true" ]] || continue ;;
            gtk)    [[ "$_APPS_DESKTOP_TOOLKIT" == "gtk" ]] || continue ;;
            qt)     [[ "$_APPS_DESKTOP_TOOLKIT" == "qt" ]] || continue ;;
            *)      warn "Unknown qualifier ':$qualifier' in apps.conf section [$section]"; continue ;;
        esac

        local items
        read -ra items <<< "${_APP_SECTIONS[$section]}"
        pkgs+=("${items[@]}")
    done
    printf '%s\n' "${pkgs[@]}"
}

_get_all_flatpak_targets() {
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
```

### 10.4 Update `_apps_parse_flags`

Add `_load_apps_conf` call at the start:

```bash
_apps_parse_flags() {
    _load_apps_conf || return 1
    _APPS_INSTALL_DEVOPS=false
    _APPS_DESKTOP_TOOLKIT="$(profile_get apps desktop_toolkit 2>/dev/null || true)"
    local arg
    for arg in "$@"; do
        case "$arg" in
            --devops) _APPS_INSTALL_DEVOPS=true ;;
        esac
    done
}
```

### 10.5 Remove hardcoded arrays

Delete these arrays from the top of `apps.sh` (current lines 15-23):

```bash
# REMOVE:
_BROWSER_PKGS=( brave-browser firefox )
_MESA_PKGS=( libva-utils mesa-vdpau-drivers-freeworld mesa-vulkan-drivers )
_COMM_FLATPAKS=( com.slack.Slack org.signal.Signal )
_AUDIO_FLATPAKS=( com.github.wwmm.easyeffects )
_MISC_PKGS=( keepassxc nextcloud-client )
_KVM_PKGS=( libvirt libvirt-daemon-config-network qemu-kvm virt-install virt-manager virt-viewer )
_GTK_DESKTOP_PKGS=( celluloid evince file-roller gnome-calculator loupe thunar )
_QT_DESKTOP_PKGS=( ark dolphin gwenview haruna kcalc okular )
_DEVOPS_PKGS=( ansible helm kind kubectl podman-compose yq )
```

### 10.6 Update `apps::apply`

The `apply` function retains its special-case blocks for procedural setup (repo configuration, systemd enablement) but reads package names from `_APP_SECTIONS` instead of hardcoded arrays.

**What changes:**
- Package names come from `_APP_SECTIONS["browsers"]`, `_APP_SECTIONS["mesa"]`, etc.
- The `if gtk / elif qt` branching for desktop utilities is removed — `_get_all_rpm_targets` handles filtering automatically.
- `_DEVOPS_PKGS` references become `_APP_SECTIONS["devops"]`.

**What stays the same (special install logic):**
- Brave repo setup (`/etc/yum.repos.d/brave-browser.repo`)
- Firefox `MOZ_ENABLE_WAYLAND=1` in `/etc/environment`
- ProtonVPN repo probing (try current and previous Fedora versions)
- HashiCorp repo setup + version pinning
- Kubernetes repo template
- KVM `usermod -aG libvirt` + `systemctl enable libvirtd`
- Flathub remote setup

These remain as imperative code in `apps::apply` — `apps.conf` governs *what*, not *how*.

**Updated `apps::apply` structure:**

```bash
apps::apply() {
    _apps_parse_flags "$@"
    preflight_checks
    require_cmd flatpak "sudo dnf install -y flatpak"

    # --- Install all RPMs (generic path) ---
    # Sections that need special repo setup are handled first,
    # then pkg_install is called with the full RPM target list.

    # Brave repo (if brave-browser is in the registry)
    if [[ "${_APP_SECTIONS[browsers]:-}" == *brave-browser* ]]; then
        if [[ ! -f /etc/yum.repos.d/brave-browser.repo ]]; then
            sudo dnf config-manager addrepo \
                --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
        fi
    fi

    # Firefox Wayland env var
    if [[ "${_APP_SECTIONS[browsers]:-}" == *firefox* ]]; then
        if ! grep -xF 'MOZ_ENABLE_WAYLAND=1' /etc/environment 2>/dev/null; then
            echo 'MOZ_ENABLE_WAYLAND=1' | sudo tee -a /etc/environment > /dev/null
        fi
    fi

    # ProtonVPN repo (special: not in apps.conf, has its own repo probing)
    # ... existing ProtonVPN logic unchanged ...

    # HashiCorp + Kubernetes repos (if devops section active)
    if [[ "$_APPS_INSTALL_DEVOPS" == "true" ]]; then
        # ... existing repo setup logic unchanged ...
    fi

    # Install all RPM targets from registry
    local all_rpms
    mapfile -t all_rpms < <(_get_all_rpm_targets)
    if [[ ${#all_rpms[@]} -gt 0 ]]; then
        info "Installing RPM packages..."
        pkg_install "${all_rpms[@]}"
    fi

    # Terraform (conditional on HashiCorp repo)
    if [[ "$_APPS_INSTALL_DEVOPS" == "true" && "$hashi_available" == true ]]; then
        pkg_install terraform
    fi

    # Install all Flatpak targets from registry
    flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    local app_id
    while IFS= read -r app_id; do
        _flatpak_install "$app_id"
    done < <(_get_all_flatpak_targets)

    # KVM post-install (if kvm section packages were installed)
    if [[ -n "${_APP_SECTIONS[kvm]:-}" ]]; then
        sudo usermod -aG libvirt "$(id -un)"
        sudo systemctl enable --now libvirtd
    fi

    ok "Apps installed"
}
```

### 10.7 `apps::check`, `apps::preview`, `apps::status`

These are mostly unchanged — they already call `_get_all_rpm_targets` and `_get_all_flatpak_targets`, which now read from `_APP_SECTIONS` instead of hardcoded arrays.

`apps::check` and `apps::preview` get validation at the start (via `_apps_parse_flags` calling `_load_apps_conf`): if `apps.conf` is missing, the module fails with a clear error.

### 10.8 Module-specific flags

- `--devops`: include sections with `:devops` qualifier (plus Terraform if HashiCorp repo available)

Desktop toolkit selection comes from profile (`desktop_toolkit = gtk` or `qt`), not from CLI flags.

### 10.9 Files changed

| File | Change |
|------|--------|
| `apps.conf` (new) | App registry — all package names extracted from current `apps.sh` arrays |
| `modules/apps.sh` | Add `_load_apps_conf` parser, update `_get_all_rpm_targets`/`_get_all_flatpak_targets`, update `apps::apply`, remove hardcoded arrays |
| `lib/config.sh` | No changes |

### 10.10 Verify

1. `./setup apps` — dry-run should list the same packages as before.
2. `./setup apps --devops` — should additionally list devops packages.
3. Compare `_get_all_rpm_targets` output before and after (pipe to `sort` and `diff`).
4. Add a test package to `apps.conf` under `[misc]`, verify it appears in preview.
5. Remove the test package, verify it disappears from preview.
6. Delete `apps.conf`, run `./setup apps` — should fail with clear error, not silently install nothing.

### 10.11 Commit

```
phase 10: apps.conf registry + modules/apps.sh refactor
```

---

## Phase 11 — `modules/audit.sh`

**Goal:** Package manifest audit. Logic is unchanged, just wrapped in the module contract.

### 11.1 Extract from `scripts/audit.sh`

The entire script (143 lines) becomes this module. The core logic (manifest reading, leaf collection, categorization, report generation) is preserved verbatim.

### 11.2 Implement contract

```bash
audit::check() {
    return 0    # Always has output
}

audit::preview() {
    # Same as apply — audit is read-only by nature
    audit::apply "$@"
}

audit::apply() {
    # Verbatim from scripts/audit.sh lines 27-143
    # (manifest reading, dnf5 leaves, categorization, report generation)
}

audit::status() {
    local latest
    latest=$(ls -t /var/tmp/pkg-audit-*.txt 2>/dev/null | head -1)
    if [[ -n "$latest" ]]; then
        echo "  Last audit: $(basename "$latest")"
    else
        echo "  No audit reports found"
    fi
}
```

### 11.3 Commit

```
phase 11: modules/audit.sh (package audit)
```

---

## Phase 12 — `setup` entry point

**Goal:** Single executable that wires everything together.

### 12.1 Create `setup`

```bash
#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
export REPO_ROOT

# ---------------------------------------------------------------------------
# Load libraries
# ---------------------------------------------------------------------------
source "$REPO_ROOT/lib/common.sh"
source "$REPO_ROOT/lib/config.sh"
source "$REPO_ROOT/lib/colors.sh"
source "$REPO_ROOT/lib/links.sh"

# Load profile
load_profile "$REPO_ROOT/profiles"

# ---------------------------------------------------------------------------
# Module infrastructure
# ---------------------------------------------------------------------------

_MODULE_ORDER=( system packages shell-env dotfiles theme apps )

run_module() {
    local module="$1"; shift
    local apply=false
    local args=()
    for arg in "$@"; do
        [[ "$arg" == "--apply" ]] && apply=true || args+=("$arg")
    done

    source "$REPO_ROOT/modules/${module}.sh"

    if ! "${module}::check" "${args[@]+"${args[@]}"}"; then
        info "$module: already up to date"
        return 0
    fi

    if [[ "$apply" == true ]]; then
        "${module}::apply" "${args[@]+"${args[@]}"}"
    else
        "${module}::preview" "${args[@]+"${args[@]}"}"
    fi
}

run_all_modules() {
    local apply=false
    local args=()
    for arg in "$@"; do
        [[ "$arg" == "--apply" ]] && apply=true || args+=("$arg")
    done

    for module in "${_MODULE_ORDER[@]}"; do
        source "$REPO_ROOT/modules/${module}.sh"
        if "${module}::check" "${args[@]+"${args[@]}"}"; then
            if [[ "$apply" == true ]]; then
                "${module}::apply" "${args[@]+"${args[@]}"}"
            else
                "${module}::preview" "${args[@]+"${args[@]}"}"
            fi
        else
            info "$module: already up to date"
        fi
    done

    if [[ "$apply" == false ]]; then
        echo ""
        info "Dry run complete. Pass --apply to execute all changes."
    fi
}

run_diff() {
    for module in "${_MODULE_ORDER[@]}"; do
        source "$REPO_ROOT/modules/${module}.sh"
        "${module}::preview" 2>/dev/null || true
    done
}

run_status() {
    echo "Profile: $(profile_get system hostname) | accent=$(profile_get theme accent)"
    for module in "${_MODULE_ORDER[@]}"; do
        source "$REPO_ROOT/modules/${module}.sh"
        echo -n "  $module: "
        "${module}::status" 2>/dev/null || echo "unknown"
    done
    # Also check audit
    source "$REPO_ROOT/modules/audit.sh"
    echo -n "  audit: "
    audit::status 2>/dev/null || echo "unknown"
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: ./setup <command> [--apply] [options]

Commands:
  install                Run all modules (dry-run by default)
  system                 Hostname, keyboard, GPU groups, firewall
  packages               System packages and repos
  shell-env              Shell environment (bootstrap-env.sh)
  dotfiles               Symlink config files
  theme                  Accent colors, icon theme, SDDM
  apps                   User applications
  audit                  Package manifest audit (read-only)
  diff                   Show differences between repo and deployed state
  status                 Show current system state

Global options:
  --apply                Execute changes (without this, only previews)

Module options (passed through):
  packages --rocm        Include ROCm stack
  packages --sway-spin   Force Sway Spin mode
  apps --devops          Include DevOps tooling
  theme --accent <name>  Override accent color
  theme --list           List available presets
  theme --audit          Check for color drift
  theme --corners        Use sddm-theme-corners
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
cmd="${1:-help}"
shift || true

case "$cmd" in
    install)    run_all_modules "$@" ;;
    system)     run_module system "$@" ;;
    packages)   run_module packages "$@" ;;
    shell-env)  run_module shell-env "$@" ;;
    dotfiles)   run_module dotfiles "$@" ;;
    theme)      run_module theme "$@" ;;
    apps)       run_module apps "$@" ;;
    audit)      source "$REPO_ROOT/modules/audit.sh"; audit::apply "$@" ;;
    diff)       run_diff ;;
    status)     run_status ;;
    help|-h|--help) usage ;;
    *)          echo "Unknown command: $cmd" >&2; usage; exit 1 ;;
esac
```

### 12.2 Make executable

```bash
chmod +x setup
```

### 12.3 Verify end-to-end

```bash
# Dry-run (should produce verbose preview, no changes)
./setup install

# Individual modules
./setup dotfiles
./setup theme --list
./setup status

# Apply
./setup install --apply
```

### 12.4 Commit

```
phase 12: setup entry point
```

---

## Phase 13 — Tests

**Goal:** Container-based smoke tests with Podman.

### 13.1 Create `tests/Containerfile`

```dockerfile
FROM registry.fedoraproject.org/fedora:43
RUN dnf install -y bash coreutils findutils grep sed gawk procps-ng ShellCheck \
    && dnf clean all
WORKDIR /systems
COPY . .
```

### 13.2 Create `tests/smoke.sh`

```bash
#!/bin/bash
set -euo pipefail

IMAGE_NAME="systems-test"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$REPO_ROOT"

podman build -t "$IMAGE_NAME" -f tests/Containerfile .

_pass=0
_fail=0

run_test() {
    local name="$1"; shift
    echo "--- TEST: $name ---"
    if podman run --rm "$IMAGE_NAME" bash -c "$*"; then
        echo "--- PASS: $name ---"
        _pass=$((_pass + 1))
    else
        echo "--- FAIL: $name ---"
        _fail=$((_fail + 1))
    fi
}

# Shellcheck
run_test "shellcheck" \
    "shellcheck setup modules/*.sh lib/*.sh"

# Profile loading
run_test "profile-load" \
    "source lib/config.sh && load_profile profiles && [[ -n \"\$(profile_get system hostname)\" ]]"

# Color presets
run_test "color-presets" \
    "source lib/config.sh && source lib/colors.sh && load_all_presets && [[ \${#COLOR_PRESETS[@]} -ge 3 ]]"

# Each module preview (dry-run, no system changes)
for mod in system packages shell-env dotfiles theme apps; do
    run_test "preview-${mod}" \
        "./setup $mod 2>&1 | tail -5"
done

# Status command
run_test "status" \
    "./setup status 2>&1 | tail -10"

echo ""
echo "Results: $_pass passed, $_fail failed"
[[ $_fail -eq 0 ]] || exit 1
```

### 13.3 Commit

```
phase 13: container-based smoke tests
```

---

## Phase 14 — Cleanup

**Goal:** Remove old `scripts/` directory and update documentation.

### 14.1 Remove `scripts/`

Delete:
- `scripts/bootstrap.sh`
- `scripts/dotfiles.sh`
- `scripts/theme-accent-color.sh`
- `scripts/theme-sddm.sh`
- `scripts/apps.sh`
- `scripts/audit.sh`
- `scripts/lib/common.sh`
- `scripts/env-sample`
- `scripts/env` (gitignored, user deletes manually)

### 14.2 Update `.gitignore`

Replace `scripts/env` with `profiles/local.conf`.

### 14.3 Update `README.md`

Replace all references to `scripts/*.sh` with `./setup` commands.

### 14.4 Update `CLAUDE.md`

Reflect new repo structure, module system, profile system.

### 14.5 Commit

```
phase 14: remove old scripts/, update documentation
```

---

## Summary: File Creation/Deletion Tracker

### New files (created during migration)

| Phase | File | Type |
|-------|------|------|
| 1 | `lib/config.sh` | Library |
| 1 | `profiles/default.conf` | Config |
| 1 | `profiles/local.conf.sample` | Template |
| 2 | `lib/colors.sh` | Library |
| 2 | `colors/green.conf` | Data |
| 2 | `colors/orange.conf` | Data |
| 2 | `colors/blue.conf` | Data |
| 3 | `lib/links.sh` | Library |
| 4 | `lib/common.sh` | Library |
| 5 | `modules/system.sh` | Module |
| 6 | `modules/packages.sh` | Module |
| 7 | `modules/shell-env.sh` | Module |
| 8 | `modules/dotfiles.sh` | Module |
| 9 | `modules/theme.sh` | Module |
| 10 | `modules/apps.sh` | Module |
| 11 | `modules/audit.sh` | Module |
| 12 | `setup` | Entry point |
| 13 | `tests/Containerfile` | Test |
| 13 | `tests/smoke.sh` | Test |

### Deleted files (phase 14)

| File | Replaced by |
|------|-------------|
| `scripts/bootstrap.sh` | `modules/system.sh` + `modules/packages.sh` + `modules/shell-env.sh` |
| `scripts/dotfiles.sh` | `modules/dotfiles.sh` |
| `scripts/theme-accent-color.sh` | `modules/theme.sh` |
| `scripts/theme-sddm.sh` | `modules/theme.sh` |
| `scripts/apps.sh` | `modules/apps.sh` |
| `scripts/audit.sh` | `modules/audit.sh` |
| `scripts/lib/common.sh` | `lib/common.sh` + `lib/colors.sh` + `lib/links.sh` + `lib/config.sh` |
| `scripts/env-sample` | `profiles/default.conf` |

### Unchanged files

- Entire `config/` directory — no changes
- `documentation/` — no changes
- `specs/` — no changes (new files only)
