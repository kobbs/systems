# Systems / Dotfiles repo

Dotfiles and bootstrap scripts for Fedora + Sway (Wayland).

## Repo structure

```
scripts/              Automation
  bootstrap.sh        Phase 1 — system packages, repos, env vars
  deploy.sh           Phase 2 — symlink config/ into ~/.config/
  apps.sh             Phase 3 — user-facing applications
  lib/common.sh       Shared helpers (logging, preflight, ensure_bashrc_source)

config/               Dotfiles (deployed by scripts/deploy.sh)
  sway/               Sway compositor
  waybar/             Waybar modules, styles, scripts/
  kanshi/             Per-machine display profiles
  gtk/                GTK 3/4 (single file → both gtk-3.0 and gtk-4.0)
  qt5ct/ qt6ct/       Qt theme settings
  kde/                KDE Frameworks color scheme (kdeglobals)
  bash/               Shell prompt
```

## Theming stack

All layers must agree for dark theme to work everywhere:

| Layer | Mechanism | Config file |
|---|---|---|
| GTK 3/4 | gsettings + settings.ini | `config/gtk/settings.ini` (symlinked to both gtk-3.0 and gtk-4.0) |
| Qt (all apps) | `QT_QPA_PLATFORMTHEME=kde` + plasma-integration | `config/kde/kdeglobals` |
| Qt style | `QT_STYLE_OVERRIDE=Breeze` | set in bootstrap-env.sh |
| SDDM greeter | `theme.conf.user` override | Written by `scripts/bootstrap.sh` to `/usr/share/sddm/themes/01-breeze-fedora/` |

Key env vars are written by the bootstrap script into `~/.config/shell/bootstrap-env.sh`.
`QT_QPA_PLATFORMTHEME=kde` is required (not `qt5ct`) because `plasma-integration` reads `kdeglobals` for all Qt apps. Setting it to `qt5ct` would cause KDE apps like Dolphin to ignore `kdeglobals`.

## Working guidelines

### Verify before declaring done

For config/theming changes: don't just check that a file exists or a symlink points correctly. Trace the full chain — env vars, platform theme plugins, and how the target application discovers its config. Grep the repo for related env vars and settings to find conflicts.

### Plans are hypotheses, not conclusions

When a plan includes a "fallback" section, that's a signal the primary fix might not be sufficient. Investigate those scenarios before implementing, not after.

### Changes often span multiple files

A config change in this repo frequently touches:
1. The config file itself (e.g. `config/kde/kdeglobals`)
2. The deploy script (`scripts/deploy.sh`) to symlink it
3. The bootstrap script to set env vars that point apps at the config
4. The live env file (`~/.config/shell/bootstrap-env.sh`) for immediate effect

Check all four layers when making theming or environment changes.

### Idempotency patterns

All scripts are designed to be safe to re-run. Key patterns used:
- **dnf install/flatpak install**: inherently idempotent (no-op if already installed)
- **File appends (`>>`)**: always guarded by `grep -qF` to prevent duplicates
- **Symlinks** (`link_file`): checks `readlink` first, skips if already correct
- **Env file writes**: uses `cmp -s` to skip if content unchanged
- **Bootstrap mode**: persisted to `~/.config/shell/.bootstrap-mode` on first run — re-runs reuse the saved mode instead of re-detecting (prevents mode flip after sway is installed)
- **Backups**: timestamped (`*.bak.YYYYMMDDHHMMSS`) to prevent overwriting previous backups
- **Expensive network probes** (e.g. ProtonVPN URL discovery): guarded by `rpm -q` check, skipped if already installed

When adding new sections, follow these patterns. The most common idempotency bug is auto-detection that changes behavior after the script's own side effects alter the system state.

### Robustness patterns

All scripts use `set -euo pipefail`. Additional robustness measures:
- **`link_file` validates source exists** before creating symlinks — warns and continues (doesn't abort deploy) if a config file is missing from the repo
- **Temp files use `trap ... EXIT`** for cleanup on interrupt (Ctrl+C)
- **Mode file validated** with `grep -qxE 'true|false'` — falls through to auto-detection if corrupted
- **Network operations have timeouts** — `curl --connect-timeout 5` on URL probes
- **`.bashrc` appends use `$HOME` as a runtime variable** (not hardcoded at install time) so paths survive home directory moves
- Avoid `return 1` from helper functions called under `set -e` unless you want the script to abort — use `return 0` with a warning for non-fatal issues

### Deduplication principles

- Shared shell functions go in `scripts/lib/common.sh` — all scripts source it.
- Config files that are identical across versions (e.g. GTK 3 vs 4) use a single source file with multiple symlinks in `scripts/deploy.sh`.
- The bootstrap script uses a single file with mode flags rather than separate near-identical scripts per Fedora variant.
- Packages shared between bootstrap modes are in a `SWAY_COMMON_PKGS` array — add to the array, not to both branches.

### Maintainability conventions

- **Package lists**: one package per line, sorted alphabetically. This makes diffs clean and duplicates easy to spot.
- **No dead code**: don't comment out old themes/configs — they're in git history. Keep the active config only.
- **Constants over magic numbers**: define `KB`, `MB`, `GB` etc. at the top of scripts that do unit math.
- **Log files**: use `$XDG_RUNTIME_DIR` (user-private, tmpfs) not `/tmp` (world-writable).
- **Naming**: scripts use short verb-oriented names (`bootstrap`, `deploy`, `apps`). Config dirs match their XDG target names.
