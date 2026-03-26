# Architecture Document

## 1. Current Architecture

### 1.1 Repository Layout

```
systems/
├── scripts/                  # Automation entry points
│   ├── env-sample            # Default variables (checked in)
│   ├── env                   # User overrides (gitignored)
│   ├── bootstrap.sh          # System packages, repos, env vars
│   ├── dotfiles.sh           # Symlink config/ → ~/.config/
│   ├── apps.sh               # User applications + optional DevOps
│   ├── audit.sh              # Package manifest audit (read-only)
│   ├── theme-accent-color.sh # Accent color + icon theme
│   ├── theme-sddm.sh         # SDDM greeter theming
│   └── lib/
│       └── common.sh         # Shared helpers, color presets, logging
│
├── config/                   # Dotfiles (source of truth, symlinked out)
│   ├── sway/config           # Compositor
│   ├── waybar/{config,style.css,scripts/}  # Status bar
│   ├── kanshi/config         # Display profiles
│   ├── swaylock/config       # Lock screen
│   ├── gtk/settings.ini      # GTK 3+4 (single file, dual symlink)
│   ├── qt5ct/qt5ct.conf      # Qt5 theme
│   ├── qt6ct/qt6ct.conf      # Qt6 theme
│   ├── kde/kdeglobals        # KDE Frameworks color scheme
│   ├── bash/prompt.sh        # Shell prompt + git status
│   ├── bash/completions.sh   # Bash completions
│   ├── fish/                 # Fish shell (optional)
│   ├── kitty/kitty.conf      # Terminal emulator
│   ├── tmux/tmux.conf        # Terminal multiplexer
│   ├── dunst/dunstrc         # Notification daemon
│   └── sddm/{theme.conf,background-dark-grey.png}  # Login screen
│
├── documentation/            # Reference cheatsheets
│   ├── sway.md, fedora.md, ROCm.md, gemini.md, claude.md
│
├── specs/                    # Design specifications
│   └── theme-accent-color.spec
│
└── CLAUDE.md                 # Development guidelines
```

### 1.2 Execution Flow

Scripts are run sequentially, each idempotent and safe to re-run:

```
bootstrap.sh start [--sway-spin] [--rocm]
    │  Installs packages, repos, env vars
    │  Creates ~/.config/shell/bootstrap-env.sh
    │  Persists mode to ~/.config/shell/.bootstrap-mode
    │
    ▼  (reboot)
dotfiles.sh start
    │  Symlinks config/ → ~/.config/
    │  Creates .local override files for per-machine customization
    │
    ▼
theme-accent-color.sh start
    │  Installs Tela-{accent} icon theme
    │  Applies color preset to all config files
    │
    ▼  (optional)
theme-sddm.sh start [--corners]
    │  Configures SDDM login screen
    │
    ▼
apps.sh start [--devops] [--gtk-apps|--qt-apps]
    │  Installs user-facing applications
    │
    ▼  (optional)
audit.sh
       Read-only package manifest report
```

### 1.3 Environment System

Two-layer env with gitignored overrides:

| File | Purpose | Tracked |
|------|---------|---------|
| `scripts/env-sample` | Defaults (`HOSTNAME="fedora"`, `ACCENT="green"`) | Yes |
| `scripts/env` | User overrides | No (.gitignored) |

Flow: scripts source `env` (falls back to `env-sample`) → variables available to all downstream logic.

Bootstrap also generates `~/.config/shell/bootstrap-env.sh` (sourced from `.bashrc`) with runtime env vars:
- `QT_QPA_PLATFORMTHEME=kde`
- `QT_STYLE_OVERRIDE=Breeze`
- `alias docker=podman`

### 1.4 Theming Stack

All layers must agree for consistent dark theme:

| Layer | Mechanism | Config |
|-------|-----------|--------|
| GTK 3/4 | gsettings + settings.ini | `config/gtk/settings.ini` → both gtk-3.0 and gtk-4.0 |
| Qt apps | `QT_QPA_PLATFORMTHEME=kde` + plasma-integration reads kdeglobals | `config/kde/kdeglobals` |
| Qt style | `QT_STYLE_OVERRIDE=Breeze` | Set in bootstrap-env.sh |
| SDDM | sddm-theme-corners (Qt6) or stock with dark bg | `config/sddm/theme.conf` |
| Accent | Named presets applied via two-pass sed | `scripts/lib/common.sh` (COLOR_PRESETS) |

### 1.5 Accent Color System

Three presets defined in `lib/common.sh`:

| Preset | PRIMARY | DIM | DARK | BRIGHT | SECONDARY | ANSI |
|--------|---------|-----|------|--------|-----------|------|
| green | `#88DD00` | `#557700` | `#2A3B00` | `#8BE235` | `#ffaa00` | 92 |
| orange | `#ff8800` | `#995200` | `#4d2900` | `#ffcc44` | `#88DD00` | 33 |
| blue | `#4488ff` | `#2a5599` | `#152a4d` | `#88bbff` | `#ffaa00` | 34 |

**Substitution method:** Two-pass placeholder strategy prevents chain reactions when preset colors overlap (e.g. orange SECONDARY = green PRIMARY):
1. All known preset colors → preset-specific placeholders (`#ff8800` → `@@orange_PRIMARY@@`)
2. All placeholders → target preset colors

**Files touched by accent system:**

| Config | Colors Used | Format |
|--------|-------------|--------|
| sway/config | PRIMARY, DIM, DARK, BRIGHT, SECONDARY + Tela name | `#RRGGBB` |
| waybar/style.css | PRIMARY | `#RRGGBB` |
| swaylock/config | PRIMARY, DIM | `RRGGBB` (bare, no `#`) |
| kitty/kitty.conf | PRIMARY | `#RRGGBB` |
| tmux/tmux.conf | PRIMARY | `#RRGGBB` |
| dunst/dunstrc | PRIMARY | `#RRGGBB` |
| sddm/theme.conf | PRIMARY | `#RRGGBB` |
| fish/conf.d/02-colors.fish | PRIMARY, DIM, DARK, BRIGHT, SECONDARY | `#RRGGBB` |
| bash/prompt.sh | ANSI code only | Numeric (dedicated sed) |
| gtk/settings.ini | Icon theme name only | `Tela-{name}` |
| kde/kdeglobals | Icon theme name only | `Tela-{name}` |

### 1.6 Deployment Mechanism

`dotfiles.sh` uses a `link_file()` helper:
- Checks `readlink` — skips if symlink already correct
- Backs up existing files with `.bak.YYYYMMDDHHMMSS`
- Creates parent dirs as needed
- Validates source exists before linking

Per-machine customization via `.local` override files (created once, never overwritten):
- `~/.config/sway/config.local`
- `~/.config/fish/config.local.fish`
- `~/.config/dunst/dunstrc.local`
- `~/.config/kitty/config.local`
- `~/.config/tmux/local.conf`

### 1.7 Package Management

`bootstrap.sh` and `apps.sh` track installed packages in manifests:
- `~/.config/shell/.pkg-manifest` — RPM packages
- `~/.config/shell/.flatpak-manifest` — Flatpaks

`audit.sh` compares manifests against `dnf5 leaves` and `flatpak list` to identify managed vs unmanaged packages.

---

## 2. Feature Inventory

### Core Features
- **F1 — System bootstrap**: Package installation, repo setup, env var deployment, keyboard layout, GPU group membership
- **F2 — Dotfile deployment**: Symlink-based config management with idempotent link helper
- **F3 — Accent color theming**: Three-preset color system applied across 11 config files
- **F4 — Icon theme management**: Tela icon theme variant installation and switching
- **F5 — SDDM theming**: Login screen customization (corners theme or stock dark)
- **F6 — Application installation**: User apps, Flatpaks, optional DevOps/desktop tooling
- **F7 — Package audit**: Manifest-based drift detection for installed packages

### Platform Detection
- **F8 — Sway Spin detection**: Auto-detect vs base Fedora, skip redundant packages
- **F9 — Mode persistence**: First-run mode saved to prevent re-detection drift
- **F10 — Conditional deployment**: Sway/Fish configs only deployed if respective tools installed

### Robustness
- **F11 — Idempotency**: All scripts safe to re-run (grep guards, readlink checks, cmp skips)
- **F12 — Backup on conflict**: Timestamped backups when overwriting existing configs
- **F13 — Per-machine overrides**: `.local` files for machine-specific customization
- **F14 — Network resilience**: Timeouts on URL probes, version fallback for ProtonVPN repo

---

## 3. Pain Points & Gaps

### Architecture Issues

**P1 — Flat script structure with implicit ordering**
Scripts must be run in a specific order (`bootstrap` → `dotfiles` → `theme` → `apps`) but nothing enforces or documents this beyond the README. A user running `theme-accent-color.sh` before `dotfiles.sh` gets confusing results.

**P2 — Scattered responsibility boundaries**
`bootstrap.sh` does too many things: packages, repos, env vars, keyboard layout, GPU groups, shell env file, bashrc modifications. Changes to any of these require navigating a large monolithic script.

**P3 — Env system is minimal**
Only two variables (`HOSTNAME`, `ACCENT`). Many decisions are hardcoded that could be configurable: keyboard layout (`fr`), default shell, Wayland scaling, GTK/icon theme name, etc.

**P4 — No validation or dry-run mode**
Scripts go straight to execution. There's no way to preview what will change before running, apart from `audit.sh` for packages.

**P5 — Accent color files list is maintained in two places**
The `_accent_files` array in `theme-accent-color.sh` and the spec in `specs/theme-accent-color.spec` must be kept in sync manually.

**P6 — No rollback mechanism**
Backups are created but there's no script to restore from them. Recovery is manual.

**P7 — Documentation scattered across multiple files**
README.md, CLAUDE.md, specs/, documentation/ — the project knowledge is fragmented with overlap.

### Missing Features

**G1 — No unified entry point**
No single command to run the full setup. Each script must be invoked manually.

**G2 — No profile/machine concept**
Per-machine differences are handled by `.local` override files and kanshi profiles, but there's no structured way to define "this is my desktop config" vs "this is my laptop config."

**G3 — No update/diff mechanism**
When configs change in the repo, there's no way to see what's different from what's deployed, beyond manual diffing.

**G4 — No uninstall/cleanup**
No script to remove symlinks, restore backups, or undo bootstrap changes.

**G5 — No test infrastructure**
Scripts are only validated by running them on a live system. No shellcheck CI, no container-based testing.

**G6 — Limited accent palette**
Only 3 presets. Adding a new color requires editing `lib/common.sh` and understanding the placeholder system.

---

## 4. Proposed Architecture (v2)

### 4.1 Design Principles

1. **Single entry point** — one command with subcommands, not 6 separate scripts
2. **Declarative config** — machine profiles defined in data, not scattered across code
3. **Composable modules** — each concern (packages, dotfiles, theming) is an independent module
4. **Preview before apply** — dry-run by default, `--apply` to execute
5. **Keep what works** — symlink-based deployment, idempotency patterns, accent system

### 4.2 Proposed Layout

```
systems/
├── setup                         # Single entry point (executable)
│
├── modules/                      # Independent, composable modules
│   ├── packages.sh               # System packages + repos
│   ├── dotfiles.sh               # Symlink deployment
│   ├── theme.sh                  # Accent colors + icon theme + SDDM
│   ├── apps.sh                   # User applications
│   ├── shell-env.sh              # Shell env vars (bootstrap-env.sh)
│   ├── system.sh                 # Hostname, keyboard, GPU groups, firewall
│   └── audit.sh                  # Package audit (read-only)
│
├── lib/                          # Shared library
│   ├── common.sh                 # Logging, preflight, idempotency helpers
│   ├── colors.sh                 # Color presets + apply_accent
│   ├── links.sh                  # link_file, backup, restore helpers
│   └── config.sh                 # Profile/env loading
│
├── profiles/                     # Machine profiles (declarative)
│   ├── default.conf              # Base settings (accent, keyboard, theme)
│   ├── desktop.conf              # Desktop overrides (GPU, displays, apps)
│   └── laptop.conf               # Laptop overrides (battery, scaling)
│
├── config/                       # Dotfiles (unchanged — source of truth)
│   └── ...                       # Same structure as current
│
├── specs/                        # Design documents
├── documentation/                # Reference cheatsheets
└── CLAUDE.md
```

### 4.3 Entry Point

```bash
# Full setup
./setup install                   # Preview all changes
./setup install --apply           # Execute all changes

# Individual modules
./setup packages --apply
./setup dotfiles --apply
./setup theme --apply
./setup apps --apply [--devops] [--gtk-apps|--qt-apps]

# Utilities
./setup audit                     # Package audit (always read-only)
./setup diff                      # Show deployed vs repo config differences
./setup status                    # Show current profile, accent, deployed state

# Theming
./setup theme --accent orange     # Change accent color
./setup theme --list              # Show available presets
./setup theme --audit             # Check for color drift
```

### 4.4 Profile System

Replace the flat `env` file with structured profiles:

```ini
# profiles/default.conf
[system]
keyboard_layout = fr

[theme]
accent = green
gtk_theme = Adwaita-dark
icon_theme = Tela
cursor_theme = Adwaita

[shell]
default_shell = bash        # bash | fish
```

```ini
# profiles/desktop.conf
inherit = default

[system]
hostname = workstation

[apps]
devops = true
desktop_toolkit = qt        # gtk | qt

[displays]
# kanshi profile selection
profile = desktop
```

Profiles are layered: `default.conf` ← `{machine}.conf` ← `local.conf` (gitignored). This replaces the `env-sample`/`env` pattern with something more structured while keeping the same override semantics.

### 4.5 Module Contract

Each module follows a standard interface:

```bash
module_name::check()    # Return 0 if changes needed, 1 if up-to-date
module_name::preview()  # Print what would change (dry-run)
module_name::apply()    # Execute changes
module_name::status()   # Report current state
```

This enables:
- `./setup install` calls `check()` then `preview()` for each module
- `./setup install --apply` calls `check()` then `apply()`
- `./setup status` calls `status()` for each module

### 4.6 Theming Consolidation

Merge `theme-accent-color.sh` and `theme-sddm.sh` into a single `modules/theme.sh`:
- Accent color application (current two-pass system — keep as-is, it works well)
- Icon theme installation
- SDDM theming
- GTK/KDE theme name settings

Move color presets from `lib/common.sh` to `lib/colors.sh` for cleaner separation.

### 4.7 Diff & Status

New capability: show what's different between repo and deployed state.

```bash
./setup diff
# config/sway/config → ~/.config/sway/config  [symlink OK]
# config/kitty/kitty.conf → ~/.config/kitty/kitty.conf  [symlink OK]
# config/waybar/style.css → ~/.config/waybar/style.css  [MODIFIED locally]
# bootstrap-env.sh  [STALE — env vars changed]
```

### 4.8 What Stays The Same

- **Config directory structure** — no changes to `config/`
- **Symlink-based deployment** — proven, simple, transparent
- **Idempotency patterns** — grep guards, readlink checks, cmp skips
- **Accent color two-pass substitution** — elegant solution to color overlap
- **Per-machine .local overrides** — simple and effective
- **Package manifest tracking** — enables audit

### 4.9 Migration Path

This is not a rewrite. It's a reorganization:

| Current | Proposed | Change |
|---------|----------|--------|
| `scripts/bootstrap.sh` | Split → `modules/packages.sh` + `modules/system.sh` + `modules/shell-env.sh` | Decompose monolith |
| `scripts/dotfiles.sh` | `modules/dotfiles.sh` | Rename + add diff capability |
| `scripts/theme-accent-color.sh` + `scripts/theme-sddm.sh` | `modules/theme.sh` | Merge related concerns |
| `scripts/apps.sh` | `modules/apps.sh` | Rename, read toolkit preference from profile |
| `scripts/audit.sh` | `modules/audit.sh` | Rename |
| `scripts/lib/common.sh` | Split → `lib/common.sh` + `lib/colors.sh` + `lib/links.sh` + `lib/config.sh` | Decompose |
| `scripts/env-sample` + `scripts/env` | `profiles/default.conf` + `profiles/*.conf` + `local.conf` | Structured config |
| (none) | `setup` | New entry point |

---

## 5. Open Questions for Discussion

1. **Profile granularity** — Is `default` + per-machine sufficient, or do we need role-based profiles (e.g. `work` vs `personal`)?

answer 1: it is sufficient

2. **Dry-run default** — Should `--apply` be required, or should some modules (like `dotfiles`) apply by default since symlinks are low-risk?

answer 2: yes. The dry-run will be verbose

3. **Accent extensibility** — Should adding a new color preset be as simple as adding a line to a config file, or is the current `lib/common.sh` array acceptable?

answer 3: yes

4. **Testing** — Is shellcheck + container-based smoke tests worth the investment, or is manual testing on real hardware sufficient?

answer 4: yes container based smole test. All this system have podman installed

5. **Scope** — Should this v2 be implemented incrementally (module by module) or as a single migration?

answer 5: implemtation will be detailed in another file called plan.md and will be modules. This is will worked on at a later stage, not now.
