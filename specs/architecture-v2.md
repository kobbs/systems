# Architecture v2

Redesign of the Fedora + Sway/Wayland bootstrap and dotfiles system.
Based on the analysis in `specs/architecture.md` and the user's decisions on open questions.

---

## Design Decisions (from v1 open questions)

| # | Question | Decision |
|---|----------|----------|
| 1 | Profile granularity | `default` + per-machine is sufficient. No role-based profiles. |
| 2 | Dry-run default | `--apply` is always required. Dry-run is the default and will be verbose. |
| 3 | Accent extensibility | Adding a preset should be as simple as adding a line to a config file. |
| 4 | Testing | Container-based smoke tests using Podman. |
| 5 | Scope | Incremental, module by module. Detailed plan in a separate `plan.md`. |

---

## 1. Repository Layout

```
systems/
├── setup                             # Single entry point (executable bash script)
│
├── modules/                          # Independent, composable modules
│   ├── packages.sh                   # System packages + repos + codecs
│   ├── dotfiles.sh                   # Symlink deployment + diff
│   ├── theme.sh                      # Accent colors + icon theme + SDDM
│   ├── apps.sh                       # User applications + Flatpaks
│   ├── shell-env.sh                  # bootstrap-env.sh generation + bashrc sourcing
│   ├── system.sh                     # Hostname, keyboard, GPU groups, firewall, services
│   └── audit.sh                      # Package manifest audit (read-only)
│
├── lib/                              # Shared library
│   ├── common.sh                     # Logging, preflight checks, pkg_install, require_cmd
│   ├── colors.sh                     # Color presets (data) + apply_accent + load_accent
│   ├── links.sh                      # link_file, backup, ensure_local_override
│   └── config.sh                     # Profile loading + variable resolution
│
├── profiles/                         # Machine configuration (declarative)
│   ├── default.conf                  # Base settings (checked in)
│   └── local.conf                    # Per-machine overrides (gitignored)
│
├── apps.conf                         # App registry — single source of truth for apps.sh
│
├── colors/                           # Color preset definitions (one file per preset)
│   ├── green.conf
│   ├── orange.conf
│   └── blue.conf
│
├── config/                           # Dotfiles (unchanged — source of truth)
│   ├── sway/config
│   ├── waybar/{config,style.css,scripts/}
│   ├── kanshi/config
│   ├── swaylock/config
│   ├── gtk/settings.ini
│   ├── qt5ct/qt5ct.conf
│   ├── qt6ct/qt6ct.conf
│   ├── kde/kdeglobals
│   ├── bash/{prompt.sh,completions.sh}
│   ├── fish/{config.fish,conf.d/,functions/}
│   ├── kitty/kitty.conf
│   ├── tmux/tmux.conf
│   ├── dunst/dunstrc
│   └── sddm/{theme.conf,background-dark-grey.png}
│
├── tests/                            # Container-based smoke tests
│   ├── Containerfile                 # Fedora base image for testing
│   └── smoke.sh                     # Test runner
│
├── specs/                            # Design documents
├── documentation/                    # Reference cheatsheets
└── CLAUDE.md
```

### What changed from v1

| v1 (current) | v2 (proposed) | Rationale |
|--------------|---------------|-----------|
| `scripts/bootstrap.sh` (monolith) | Split → `modules/packages.sh` + `modules/system.sh` + `modules/shell-env.sh` | Single-responsibility. Each module can be run and tested independently. |
| `scripts/dotfiles.sh` | `modules/dotfiles.sh` | Gains diff/status capability. |
| `scripts/theme-accent-color.sh` + `scripts/theme-sddm.sh` | `modules/theme.sh` | Merge related theming concerns into one module. |
| `scripts/apps.sh` | `modules/apps.sh` | Reads `desktop_toolkit` from profile instead of CLI flag. |
| `scripts/audit.sh` | `modules/audit.sh` | Unchanged logic, new location. |
| `scripts/lib/common.sh` (everything) | Split → `lib/common.sh` + `lib/colors.sh` + `lib/links.sh` + `lib/config.sh` | Focused files. Colors become data-driven. |
| `scripts/env-sample` + `scripts/env` | `profiles/default.conf` + `profiles/local.conf` | Structured config with sections. |
| Color presets hardcoded in bash array | `colors/*.conf` files | Adding a preset = adding a file. No code changes needed. |
| App lists hardcoded in bash arrays | `apps.conf` | Adding an app = adding a line. Category/flag filtering built in. |
| (none) | `setup` | Single entry point replacing 6 separate script invocations. |
| (none) | `tests/` | Container-based smoke tests with Podman. |

---

## 2. Entry Point: `setup`

Single executable that dispatches to modules.

### Usage

```bash
# Full system setup (dry-run — verbose preview of all changes)
./setup install

# Full system setup (execute)
./setup install --apply

# Individual modules
./setup packages --apply
./setup dotfiles --apply
./setup theme --apply
./setup apps --apply
./setup shell-env --apply
./setup system --apply

# Read-only utilities (no --apply needed)
./setup audit                     # Package manifest audit
./setup diff                      # Deployed vs repo config differences
./setup status                    # Current profile, accent, deployment state

# Theming shortcuts
./setup theme --accent orange     # Change accent color
./setup theme --list              # Show available presets
./setup theme --audit             # Check for color drift

# Module-specific flags (passed through to module)
./setup packages --rocm           # Include ROCm stack
./setup apps --devops             # Include DevOps tooling
./setup system --sway-spin        # Force Sway Spin mode detection
```

### Dispatch Logic

```bash
#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
source "$REPO_ROOT/lib/common.sh"
source "$REPO_ROOT/lib/config.sh"

# Load profile
load_profile "$REPO_ROOT/profiles"

cmd="${1:-help}"
shift || true

case "$cmd" in
    install)    run_all_modules "$@" ;;
    packages)   run_module packages "$@" ;;
    dotfiles)   run_module dotfiles "$@" ;;
    theme)      run_module theme "$@" ;;
    apps)       run_module apps "$@" ;;
    shell-env)  run_module shell-env "$@" ;;
    system)     run_module system "$@" ;;
    audit)      run_module audit "$@" ;;
    diff)       run_diff ;;
    status)     run_status ;;
    help|-h|--help) usage ;;
    *)          echo "Unknown command: $cmd" >&2; usage; exit 1 ;;
esac
```

### `run_module` Behavior

```bash
run_module() {
    local module="$1"; shift
    local apply=false

    # Parse --apply from args, pass remaining to module
    local args=()
    for arg in "$@"; do
        [[ "$arg" == "--apply" ]] && apply=true || args+=("$arg")
    done

    source "$REPO_ROOT/modules/${module}.sh"

    if ! "${module}::check" "${args[@]}"; then
        info "$module: already up to date"
        return 0
    fi

    if [[ "$apply" == true ]]; then
        "${module}::apply" "${args[@]}"
    else
        "${module}::preview" "${args[@]}"
        echo ""
        info "Dry run. Pass --apply to execute."
    fi
}
```

### `install` Behavior

Runs all modules in dependency order:

```
system → packages → shell-env → dotfiles → theme → apps
```

Each module gets `check` → `preview` (dry-run) or `check` → `apply`. Modules that are already up-to-date are skipped with a message.

---

## 3. Module Contract

Every module in `modules/` exports four functions:

```bash
module_name::check()      # Return 0 if changes are needed, 1 if up-to-date
                          # Args: module-specific flags (e.g. --rocm, --devops)

module_name::preview()    # Print verbose description of what would change
                          # Must NOT modify the system
                          # Args: same as check

module_name::apply()      # Execute changes
                          # Must be idempotent
                          # Args: same as check

module_name::status()     # Report current state (for ./setup status)
                          # Must NOT modify the system
```

### Module Definitions

#### `modules/system.sh`
Extracted from: `bootstrap.sh` sections for hostname, keyboard, GPU groups, firewall, services.

| Function | Behavior |
|----------|----------|
| `system::check` | Compare hostname, keyboard layout, GPU group membership, firewall state against profile |
| `system::preview` | Print what would change (e.g. "Hostname: current → target") |
| `system::apply` | `hostnamectl`, `localectl`, `usermod`, `systemctl enable` |
| `system::status` | Show hostname, keyboard, GPU groups, firewall zone, service states |

Reads from profile: `hostname`, `keyboard_layout`.
Detects: discrete AMD GPU (lspci), Sway Spin mode (persisted to `~/.config/shell/.bootstrap-mode`).

#### `modules/packages.sh`
Extracted from: `bootstrap.sh` sections for dnf update, RPM Fusion, Flathub, Sway/Wayland packages, CLI tools, Yubikey, ROCm.

| Function | Behavior |
|----------|----------|
| `packages::check` | Check if any packages from the target list are missing |
| `packages::preview` | Print list of packages that would be installed, repos that would be added |
| `packages::apply` | `dnf install`, repo setup, codec swaps |
| `packages::status` | Show package counts (managed vs total leaves) |

Flags: `--rocm`, `--sway-spin`, `--kde-spin`.
Reads from profile: (none — package lists are in the module code).

#### `modules/shell-env.sh`
Extracted from: `bootstrap.sh` section 8 (shell environment).

| Function | Behavior |
|----------|----------|
| `shell-env::check` | Compare generated bootstrap-env.sh content against deployed |
| `shell-env::preview` | Show diff of current vs target bootstrap-env.sh |
| `shell-env::apply` | Write `~/.config/shell/bootstrap-env.sh`, ensure `.bashrc` sources it |
| `shell-env::status` | Show deployed env vars |

#### `modules/dotfiles.sh`
Extracted from: current `scripts/dotfiles.sh`.

| Function | Behavior |
|----------|----------|
| `dotfiles::check` | Walk symlink map, return 0 if any link is missing or wrong |
| `dotfiles::preview` | Print each symlink with status: `[OK]`, `[MISSING]`, `[WRONG TARGET]`, `[BLOCKED BY FILE]` |
| `dotfiles::apply` | Create symlinks via `link_file`, create `.local` override files |
| `dotfiles::status` | Summary of deployed symlinks and their states |

#### `modules/theme.sh`
Merged from: `scripts/theme-accent-color.sh` + `scripts/theme-sddm.sh`.

| Function | Behavior |
|----------|----------|
| `theme::check` | Check if accent colors in config files match target preset, icon theme installed |
| `theme::preview` | Print color changes per file, icon theme status, SDDM status |
| `theme::apply` | Run `apply_accent` on target files, install Tela icon theme, configure SDDM |
| `theme::status` | Show active accent, icon theme, SDDM theme |

Flags: `--accent <name>` (override profile), `--list`, `--audit`, `--corners` (SDDM theme variant).
Reads from profile: `accent`, `icon_theme`.

See section 12 for the structural improvements to this module.

#### `modules/apps.sh`
Extracted from: current `scripts/apps.sh`.

| Function | Behavior |
|----------|----------|
| `apps::check` | Check which target apps are missing |
| `apps::preview` | Print apps that would be installed, grouped by category |
| `apps::apply` | Install RPMs and Flatpaks |
| `apps::status` | Show installed managed apps |

Flags: `--devops`.
Reads from profile: `desktop_toolkit` (gtk/qt).
Reads from: `apps.conf` (app registry — see section 11).

#### `modules/audit.sh`
Extracted from: current `scripts/audit.sh`.

| Function | Behavior |
|----------|----------|
| `audit::check` | Always returns 0 (always has output) |
| `audit::preview` | Same as apply (read-only by nature) |
| `audit::apply` | Generate report to `/var/tmp/pkg-audit-YYYYMMDD.txt` |
| `audit::status` | Show last audit date and summary |

---

## 4. Profile System

### Format

INI-style config files parsed by `lib/config.sh`:

```ini
# profiles/default.conf — checked in, base settings
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

```ini
# profiles/local.conf — gitignored, per-machine overrides
[system]
hostname = workstation

[theme]
accent = orange
```

### Resolution Order

```
default.conf ← local.conf
```

`local.conf` values override `default.conf`. Missing keys fall back to `default.conf`. Missing sections are fine — modules use their own defaults if a key is absent.

### `lib/config.sh` API

```bash
load_profile()              # Parse default.conf + local.conf, populate PROFILE_* vars
profile_get "section" "key" # Return value or empty string
```

Variables exposed after `load_profile`:

```bash
PROFILE_SYSTEM_HOSTNAME         # "workstation"
PROFILE_SYSTEM_KEYBOARD_LAYOUT  # "fr"
PROFILE_THEME_ACCENT            # "orange"
PROFILE_THEME_GTK_THEME         # "Adwaita-dark"
PROFILE_THEME_ICON_THEME        # "Tela"
PROFILE_THEME_CURSOR_THEME      # "Adwaita"
PROFILE_SHELL_DEFAULT_SHELL     # "bash"
PROFILE_APPS_DESKTOP_TOOLKIT    # "qt"
```

---

## 5. Color Preset System

### Data-driven presets

Each preset is a plain config file in `colors/`:

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

```ini
# colors/orange.conf
name = orange
primary = #ff8800
dim = #995200
dark = #4d2900
bright = #ffcc44
secondary = #88DD00
ansi = 33
```

```ini
# colors/blue.conf
name = blue
primary = #4488ff
dim = #2a5599
dark = #152a4d
bright = #88bbff
secondary = #ffaa00
ansi = 34
```

### Adding a new preset

1. Create `colors/purple.conf` with the 6 color values
2. Set `accent = purple` in `profiles/local.conf`
3. Run `./setup theme --apply`

No code changes needed. `lib/colors.sh` reads all `*.conf` files in `colors/` at load time.

### `lib/colors.sh` API

```bash
load_all_presets()              # Read all colors/*.conf into COLOR_PRESETS associative array
load_accent()                   # Read target accent from profile, populate ACCENT_* vars
apply_accent "$file1" "$file2"  # Two-pass placeholder substitution (unchanged algorithm)
```

The two-pass placeholder substitution algorithm is preserved exactly as-is — it is proven and handles overlapping colors correctly.

### Target Files

Unchanged from v1. The list of files that receive accent color substitution:

| Config File | Colors Used | Format |
|-------------|-------------|--------|
| `config/sway/config` | PRIMARY, DIM, DARK, BRIGHT, SECONDARY + Tela name | `#RRGGBB` |
| `config/waybar/style.css` | PRIMARY | `#RRGGBB` |
| `config/swaylock/config` | PRIMARY, DIM | `RRGGBB` (bare) |
| `config/kitty/kitty.conf` | PRIMARY | `#RRGGBB` |
| `config/tmux/tmux.conf` | PRIMARY | `#RRGGBB` |
| `config/dunst/dunstrc` | PRIMARY | `#RRGGBB` |
| `config/sddm/theme.conf` | PRIMARY | `#RRGGBB` |
| `config/fish/conf.d/02-colors.fish` | PRIMARY, DIM, DARK, BRIGHT, SECONDARY | `#RRGGBB` |
| `config/bash/prompt.sh` | ANSI code only | Numeric (dedicated sed) |
| `config/gtk/settings.ini` | Icon theme name only | `Tela-{name}` |
| `config/kde/kdeglobals` | Icon theme name only | `Tela-{name}` |

---

## 6. Library Decomposition

### `lib/common.sh` — Core utilities

Retained from current `scripts/lib/common.sh`, minus colors and links:

```bash
# Logging
info()                    # Blue prefix
ok()                      # Green prefix
warn()                    # Yellow prefix
init_logging()            # Create timestamped log in $XDG_RUNTIME_DIR

# Preflight
preflight_checks()        # Ensure regular user, Fedora OS
require_cmd()             # Exit if command not found

# Package management
pkg_install()             # dnf install + record to manifest
FLATPAK_MANIFEST          # Path to flatpak manifest file
PKG_MANIFEST              # Path to RPM manifest file

# Detection
find_fedora_version()     # Probe URL template for compatible Fedora version
```

### `lib/colors.sh` — Color system

Extracted from `scripts/lib/common.sh`:

```bash
load_all_presets()        # Read colors/*.conf → COLOR_PRESETS
load_accent()             # Resolve target accent from profile
apply_accent()            # Two-pass placeholder substitution
```

### `lib/links.sh` — Symlink management

Extracted from `scripts/dotfiles.sh`:

```bash
link_file()               # Idempotent symlink with backup
ensure_local_override()   # Create .local file if missing
```

### `lib/config.sh` — Profile loading

New:

```bash
load_profile()            # Parse profiles/default.conf + local.conf
profile_get()             # Key lookup with section.key syntax
```

---

## 7. Diff & Status

### `./setup diff`

Walks the symlink map and reports:

```
Dotfiles:
  config/sway/config → ~/.config/sway/config              [OK]
  config/kitty/kitty.conf → ~/.config/kitty/kitty.conf     [OK]
  config/waybar/style.css → ~/.config/waybar/style.css     [WRONG TARGET]

Shell env:
  ~/.config/shell/bootstrap-env.sh                         [STALE]

Theme:
  Accent: orange                                           [OK]
  Icon theme: Tela-orange                                  [MISSING]
```

### `./setup status`

Aggregates `module::status()` from all modules:

```
Profile:    default + local (hostname=workstation, accent=orange)
System:     hostname=workstation, keyboard=fr, firewall=active
Packages:   247 managed, 12 extra leaves
Shell env:  bootstrap-env.sh deployed, 4 exports
Dotfiles:   19/19 symlinks active
Theme:      accent=orange, icon=Tela-orange, sddm=corners
Apps:       14 RPM + 3 Flatpak managed
Last audit: 2026-03-25 (/var/tmp/pkg-audit-20260325.txt)
```

---

## 8. Testing

### Approach

Container-based smoke tests using Podman. Tests verify that modules execute without errors on a clean Fedora image. They do not test GUI rendering or hardware-specific behavior.

### `tests/Containerfile`

```dockerfile
FROM registry.fedoraproject.org/fedora:43
RUN dnf install -y bash coreutils findutils grep sed gawk procps-ng \
    && dnf clean all
WORKDIR /systems
COPY . .
```

### `tests/smoke.sh`

```bash
#!/bin/bash
# Run from repo root: bash tests/smoke.sh
set -euo pipefail

IMAGE_NAME="systems-test"

podman build -t "$IMAGE_NAME" -f tests/Containerfile .

run_test() {
    local name="$1"; shift
    echo "--- TEST: $name ---"
    podman run --rm "$IMAGE_NAME" bash -c "$*"
    echo "--- PASS: $name ---"
}

# Profile loading
run_test "profile-load" \
    "source lib/config.sh && load_profile profiles && profile_get theme accent"

# Color preset loading
run_test "color-presets" \
    "source lib/colors.sh && load_all_presets && [[ \${#COLOR_PRESETS[@]} -ge 3 ]]"

# Dry-run of each module (preview only — no system changes)
for mod in system packages shell-env dotfiles theme apps; do
    run_test "module-${mod}-preview" \
        "./setup $mod 2>&1 | head -50"
done

# Shellcheck all scripts
run_test "shellcheck" \
    "dnf install -y ShellCheck && shellcheck setup modules/*.sh lib/*.sh"

echo "All tests passed."
```

### What tests cover

| Test | Validates |
|------|-----------|
| profile-load | Profile parser reads default.conf correctly |
| color-presets | All color preset files parse and load |
| module-*-preview | Each module's dry-run executes without error |
| shellcheck | Static analysis of all bash scripts |

### What tests do NOT cover

- Actual package installation (requires sudo/network)
- Hardware detection (GPU, display)
- GUI/theming visual correctness
- SDDM configuration (requires SDDM installed)

These are validated by running on real hardware.

---

## 9. Migration Path

Implementation is incremental, module by module. Each step produces a working system — no big-bang migration.

### Phase order

```
1.  lib/config.sh + profiles/         (new — foundation for everything)
2.  lib/colors.sh + colors/           (extract from lib/common.sh)
3.  lib/links.sh                      (extract from dotfiles.sh)
4.  lib/common.sh                     (trim to core utilities)
5.  modules/system.sh                 (extract from bootstrap.sh)
6.  modules/packages.sh               (extract from bootstrap.sh)
7.  modules/shell-env.sh              (extract from bootstrap.sh)
8.  modules/dotfiles.sh               (refactor from scripts/dotfiles.sh)
9.  modules/theme.sh                  (merge + structural improvements — see section 12)
10. apps.conf                         (app registry — see section 11)
11. modules/apps.sh                   (refactor to read from apps.conf)
12. modules/audit.sh                  (refactor from scripts/audit.sh)
13. setup                             (entry point, wires everything together)
14. tests/                            (smoke tests)
```

Old scripts remain functional until their replacement module is complete and tested.

Detailed implementation plan will be in `specs/plan.md`.

---

## 10. Preserved Patterns

These patterns are carried forward unchanged:

- **Symlink-based deployment** — `link_file` with readlink check, timestamped backups
- **Idempotency** — grep guards on file appends, cmp on env files, dnf's built-in idempotency
- **Sway Spin mode detection** — persisted to `~/.config/shell/.bootstrap-mode`
- **Two-pass accent substitution** — placeholder strategy for overlapping colors
- **Per-machine .local overrides** — created once, never overwritten
- **Package manifests** — `.pkg-manifest` and `.flatpak-manifest` for audit
- **`set -euo pipefail`** — all scripts
- **Temp file cleanup** — `trap ... EXIT` pattern
- **Config directory structure** — `config/` layout is unchanged

---

## 11. App Registry (`apps.conf`)

### Problem

App lists are hardcoded as bash arrays in `modules/apps.sh`. Adding or removing an app means editing shell code. There is no single source of truth that documents which apps are managed — the architecture doc and the code can drift.

### Design

A structured INI file at `apps.conf` serves as the single source of truth for all apps installed by `modules/apps.sh`. The file uses `lib/config.sh`'s existing INI parser.

Each section defines a category. Section names encode the package type and an optional install flag:

```
[section]           → always-installed RPM packages
[section:devops]    → RPM packages installed only with --devops flag
[section:gtk]       → RPM packages installed only when desktop_toolkit = gtk
[section:qt]        → RPM packages installed only when desktop_toolkit = qt
[flatpak:section]   → always-installed Flatpak apps
```

### `apps.conf`

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

### How `apps.sh` uses the registry

1. At module load, `apps.sh` reads `apps.conf` using `lib/config.sh`.
2. Categories are filtered based on active flags and profile:
   - Sections with no qualifier → always included
   - `:devops` → included only when `--devops` is passed
   - `:gtk` / `:qt` → included only when `desktop_toolkit` matches
   - `flatpak:*` → installed via `flatpak install` instead of `dnf install`
3. The hardcoded `_*_PKGS` arrays are removed from `apps.sh`. All package names come from `apps.conf`.
4. Special install logic (ProtonVPN repo probing, HashiCorp/Kubernetes repo setup, Brave repo) remains in `apps.sh` code — `apps.conf` only governs *what* gets installed, not *how*.

### Adding an app

1. Add the package name to the appropriate section in `apps.conf`
2. Run `./setup apps --apply` (or `./setup apps --devops --apply`)

No code changes needed unless the app requires special repo setup.

### Validation

`apps::check` and `apps::preview` validate that `apps.conf` exists and is non-empty. If the file is missing, the module fails with a clear error rather than silently installing nothing.

---

## 12. Theme Module Improvements (`modules/theme.sh`)

### Problems identified

| Issue | Impact |
|-------|--------|
| `_detect_preset()` and `_detect_preset_bare()` are 95% identical | Code duplication |
| `_apply_sddm()` is 107 lines handling multiple concerns | Hard to read and test |
| No error checking on file operations (`cp`, `sed`, `git clone`) | Silent failures |
| No temp file cleanup on failure | Leftover state after interrupted runs |
| Repeated detection loops in `check()` and `preview()` | Code duplication |
| Hardcoded paths scattered throughout | Maintenance burden |

### Structural changes

#### 1. Merge detection functions

Replace `_detect_preset()`, `_detect_preset_bare()`, and `_detect_bash_prompt()` with a single function:

```bash
_detect_preset_in_file() {
    local file="$1"
    local method="$2"    # "hex" | "bare" | "ansi"
    # ... unified logic, method selects which color field to match
}
```

#### 2. Split `_apply_sddm()`

Break into focused helpers:

```bash
_install_sddm_corners()     # Git clone + Qt6 patch + dark bg
_apply_sddm_stock()         # Stock Fedora theme + dark grey background
_set_sddm_active_theme()    # Write /etc/sddm.conf.d/theme.conf + enable sddm
_apply_sddm()               # Orchestrator: calls the above based on --corners flag
```

#### 3. Extract shared detection loop

`theme::check()` and `theme::preview()` both iterate over `_ACCENT_HEX_FILES` with identical detection logic. Extract to:

```bash
_detect_all_files()          # Returns list of (file, detected_preset) pairs
```

Both `check` and `preview` call this. `check` short-circuits on first mismatch. `preview` formats the full table.

#### 4. Constants for paths

```bash
_SDDM_THEME_BASE="/usr/share/sddm/themes"
_TELA_ICON_BASE="$HOME/.local/share/icons"
```

### Error handling improvements

#### 1. Temp file cleanup via trap

```bash
_theme_cleanup() {
    [[ -n "${_THEME_TMPDIR:-}" ]] && rm -rf "$_THEME_TMPDIR"
}

theme::apply() {
    _THEME_TMPDIR=$(mktemp -d)
    trap _theme_cleanup EXIT
    # ... all temp files created under $_THEME_TMPDIR
}
```

#### 2. Git clone with error context

```bash
if ! git clone --depth 1 "$url" "$dest" 2>&1; then
    warn "Failed to clone $url — skipping"
    return 0    # Non-fatal: theme still works without optional component
fi
```

#### 3. File operation guards

Critical file operations (`cp` to system paths, `sed -i` on config files) get explicit checks:

```bash
cp "$src" "$dest" || { warn "Failed to copy $src → $dest"; return 0; }
```

Non-fatal operations (icon theme, SDDM) warn and continue. Fatal operations (accent color substitution on repo config files) propagate errors.

#### 4. Validate preset before apply

```bash
theme::apply() {
    load_all_presets
    load_accent
    if [[ -z "${COLOR_PRESETS[$ACCENT_NAME]+x}" ]]; then
        warn "Unknown preset: $ACCENT_NAME"
        return 1
    fi
    # ...
}
```

### Logging improvements

Use `info()` / `warn()` / `ok()` from `lib/common.sh` consistently:
- `info` before each major step (icon theme, accent files, SDDM)
- `ok` after each successful step
- `warn` for non-fatal failures (SDDM not installed, git clone failed)

Currently some paths (e.g., SDDM not installed) skip silently. All skipped steps should log why.
