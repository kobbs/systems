# Systems / Dotfiles repo

Dotfiles and bootstrap system for Fedora + Sway (Wayland).

## Repo structure

```
setup                     Single entry point — dispatches to modules

modules/                  Independent modules (check/preview/apply/status contract)
  system.sh               Hostname, keyboard, GPU groups, firewall, services
  packages.sh             System packages, repos, codecs, ROCm
  shell-env.sh            bootstrap-env.sh generation + .bashrc sourcing
  dotfiles.sh             Symlink config/ → ~/.config/ (declarative map)
  theme.sh                Accent colors + icon theme + SDDM
  apps.sh                 User applications + Flatpaks + DevOps
  audit.sh                Package manifest audit (read-only)

lib/                      Shared libraries (sourced by setup + modules)
  common.sh               Logging, preflight, pkg_install, find_fedora_version
  config.sh               INI profile parser (load_profile, profile_get)
  colors.sh               Color presets + apply_accent (two-pass placeholder)
  links.sh                Symlink helpers (link_file, check_link, ensure_local_override)

profiles/                 Machine configuration (INI format)
  default.conf            Base settings (checked in)
  local.conf              Per-machine overrides (gitignored)

colors/                   Color preset definitions (one file per preset)
  green.conf              Green accent preset
  orange.conf             Orange accent preset
  blue.conf               Blue accent preset

config/                   Dotfiles (source of truth, symlinked into ~/.config/)
  sway/                   Sway compositor
  waybar/                 Waybar modules, styles, scripts/
  kanshi/                 Per-machine display profiles
  gtk/                    GTK 3/4 (single file → both gtk-3.0 and gtk-4.0)
  qt5ct/ qt6ct/           Qt theme settings
  kde/                    KDE Frameworks color scheme (kdeglobals)
  bash/                   Shell prompt + completions
  fish/                   Fish shell (optional — prompt, abbreviations, vi mode)
  kitty/                  Kitty terminal
  tmux/                   tmux
  dunst/                  Notification daemon
  swaylock/               Screen locker
  sddm/                   Login greeter

tests/                    Container-based smoke tests (Podman)
```

## Module contract

Every module exports five functions:

```bash
module::init()      # Read PROFILE_* vars, parse flags, set module-local state (called once)
module::check()     # Return 0 if changes needed, 1 if up-to-date
module::preview()   # Print what would change (read-only)
module::apply()     # Execute changes (idempotent)
module::status()    # One-line current state summary
```

`./setup` dispatches to modules. Dry-run by default, `--apply` to execute. `::init` is called before `::check` so modules can read profile keys and cache state once.

## Theming stack

All layers must agree for dark theme to work everywhere:

| Layer | Mechanism | Config file |
|---|---|---|
| GTK 3/4 | gsettings + settings.ini | `config/gtk/settings.ini` (symlinked to both gtk-3.0 and gtk-4.0) |
| Qt (all apps) | `QT_QPA_PLATFORMTHEME=kde` + plasma-integration | `config/kde/kdeglobals` |
| Qt style | `QT_STYLE_OVERRIDE=Breeze` | set in bootstrap-env.sh |
| SDDM greeter | sddm-theme-corners (Qt6) | `config/sddm/theme.conf` deployed by `modules/theme.sh` |
| Accent color | Named presets in `colors/*.conf` | Read from `profiles/local.conf`. Applied by `modules/theme.sh` via two-pass sed |

Key env vars are written by `modules/shell-env.sh` into `~/.config/shell/bootstrap-env.sh`.
`QT_QPA_PLATFORMTHEME=kde` is required (not `qt5ct`) because `plasma-integration` reads `kdeglobals` for all Qt apps. Setting it to `qt5ct` would cause KDE apps like Dolphin to ignore `kdeglobals`.

**Do not remove Qt5 packages.** `plasma-integration` and `plasma-breeze` depend on Qt5 libraries (`kf5-frameworkintegration`, etc.). Removing Qt5 packages (e.g. `qt5-qtquickcontrols2`) triggers a cascade that pulls out the entire Qt dark theme stack. The SDDM greeter uses Qt6, but the dark theme integration layer still requires Qt5.

### Accent color system

Color presets are data-driven — each preset is a `.conf` file in `colors/` with 6 values: primary, dim, dark, bright, secondary, ansi.

- `colors/*.conf` — preset definitions (adding a file = adding a preset)
- `profiles/default.conf` — default accent (`green`)
- `profiles/local.conf` — gitignored, user's local override
- `modules/theme.sh` calls `apply_accent` which uses a two-pass placeholder strategy to swap colors without chain reactions
- `_ACCENT_HEX_FILES` and `_ACCENT_SWAY_FILES` arrays in `modules/theme.sh` define which config files receive color substitution

When adding a new config file that uses the accent color, add it to the appropriate array in `modules/theme.sh` and use colors from the green preset as defaults in the config file.

## Working guidelines

### Verify before declaring done

For config/theming changes: don't just check that a file exists or a symlink points correctly. Trace the full chain — env vars, platform theme plugins, and how the target application discovers its config. Grep the repo for related env vars and settings to find conflicts.

### Plans are hypotheses, not conclusions

When a plan includes a "fallback" section, that's a signal the primary fix might not be sufficient. Investigate those scenarios before implementing, not after.

### Changes often span multiple files

A config change in this repo frequently touches:
1. The config file itself (e.g. `config/kde/kdeglobals`)
2. The symlink map in `modules/dotfiles.sh` to deploy it
3. The shell-env module to set env vars that point apps at the config
4. The profile in `profiles/default.conf` if a new setting is introduced

Check all layers when making theming or environment changes.

### Idempotency patterns

All modules are designed to be safe to re-run. Key patterns used:
- **dnf install/flatpak install**: inherently idempotent (no-op if already installed)
- **File appends (`>>`)**: always guarded by `grep -qF` to prevent duplicates
- **Symlinks** (`link_file`): checks `readlink` first, skips if already correct
- **Env file writes**: uses `cmp -s` to skip if content unchanged
- **Bootstrap mode**: persisted to `~/.config/shell/.bootstrap-mode` on first run — re-runs reuse the saved mode instead of re-detecting (prevents mode flip after sway is installed)
- **Backups**: timestamped (`*.bak.YYYYMMDDHHMMSS`) to prevent overwriting previous backups
- **Expensive network probes** (e.g. ProtonVPN URL discovery): guarded by `rpm -q` check, skipped if already installed

When adding new sections, follow these patterns. The most common idempotency bug is auto-detection that changes behavior after the script's own side effects alter the system state.

### Robustness patterns

All modules use `set -euo pipefail` (inherited from `setup`). Additional robustness measures:
- **`link_file` validates source exists** before creating symlinks — warns and continues (doesn't abort deploy) if a config file is missing from the repo
- **Mode file validated** with `grep -qxE 'true|false'` — falls through to auto-detection if corrupted
- **Network operations have timeouts** — `curl --connect-timeout 5` on URL probes
- **`.bashrc` appends use `$HOME` as a runtime variable** (not hardcoded at install time) so paths survive home directory moves
- Avoid `return 1` from helper functions called under `set -e` unless you want the script to abort — use `return 0` with a warning for non-fatal issues

### Deduplication principles

- Shared shell functions go in `lib/` — `common.sh`, `config.sh`, `colors.sh`, `links.sh`.
- Config files that are identical across versions (e.g. GTK 3 vs 4) use a single source file with multiple symlinks in the `_SYMLINK_MAP` array.
- Packages shared between bootstrap modes are in `_SWAY_COMMON_PKGS` — add to the array, not to both branches.
- Color presets are data files (`colors/*.conf`), not code — adding a preset requires no code changes.

### Maintainability conventions

- **Package lists**: one package per line, sorted alphabetically. This makes diffs clean and duplicates easy to spot.
- **No dead code**: don't comment out old themes/configs — they're in git history. Keep the active config only.
- **Constants over magic numbers**: define `KB`, `MB`, `GB` etc. at the top of scripts that do unit math.
- **Log files**: use `$XDG_RUNTIME_DIR` (user-private, tmpfs) not `/tmp` (world-writable).
- **Naming**: modules use short descriptive names. Config dirs match their XDG target names.
