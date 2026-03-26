# theme-accent-color.sh — Specification & Design

## Purpose

Applies a named accent color preset across all config files in the repo,
installs the matching Tela icon theme variant, and updates shell prompt colors.
Provides an audit mode to detect drift between the expected preset and what is
actually present in config files.

## CLI Interface

```
theme-accent-color.sh start [--list]
theme-accent-color.sh audit
theme-accent-color.sh --list
theme-accent-color.sh -h | --help
```

| Command        | Effect                                                    |
|----------------|-----------------------------------------------------------|
| `start`        | Apply accent to all config files, install icon theme      |
| `start --list` | Apply accent, then print the preset table                 |
| `audit`        | Read-only check of applied vs expected colors             |
| `--list`       | Print all presets with hex values (no changes)            |
| `-h / --help`  | Print usage and exit                                      |

Exit codes: 0 on success, 1 on unknown option or missing dependency.

---

## Preset System

Defined in `scripts/lib/common.sh` as the `COLOR_PRESETS` associative array.
Each preset maps to six values:

```
PRIMARY DIM DARK BRIGHT SECONDARY ANSI_CODE
```

| Preset   | PRIMARY   | DIM       | DARK      | BRIGHT    | SECONDARY | ANSI |
|----------|-----------|-----------|-----------|-----------|-----------|------|
| green    | `#88DD00` | `#557700` | `#2A3B00` | `#8BE235` | `#ffaa00` | 92   |
| orange   | `#ff8800` | `#995200` | `#4d2900` | `#ffcc44` | `#88DD00` | 33   |
| blue     | `#4488ff` | `#2a5599` | `#152a4d` | `#88bbff` | `#ffaa00` | 34   |

Role semantics:
- **PRIMARY** — focused borders, login button, clock, cursor, selection
- **DIM** — focused-inactive borders
- **DARK** — unfocused borders
- **BRIGHT** — placeholder borders
- **SECONDARY** — bemenu highlight text, power icons
- **ANSI_CODE** — terminal escape code for bash prompt hostname color

The active preset is read from `scripts/env` (`ACCENT="green"`), falling back
to `scripts/env-sample` if no local override exists, and then to `"green"` if
neither file sets it. An unknown preset name logs a warning and falls back to
green.

---

## Target Files — Config Format & Substitution Method

| Target file                        | Config format            | Color format                   | Substitution method                | Color roles used                              |
|------------------------------------|--------------------------|--------------------------------|------------------------------------|-----------------------------------------------|
| `config/sway/config`               | sway config (key-value)  | `#RRGGBB`                      | `apply_accent` (sed, case-insensitive) | PRIMARY, DIM, DARK, BRIGHT, SECONDARY + Tela name |
| `config/waybar/style.css`          | CSS                      | `#RRGGBB`                      | `apply_accent`                     | PRIMARY                                       |
| `config/sddm/theme.conf`          | INI (`key="value"`)      | `#RRGGBB`                      | `apply_accent`                     | PRIMARY                                       |
| `config/fish/conf.d/02-colors.fish`| fish shell script        | `#RRGGBB` (vars strip `#`)    | `apply_accent`                     | PRIMARY, DIM, DARK, BRIGHT, SECONDARY         |
| `config/kitty/kitty.conf`         | key-value (space-delim)  | `#RRGGBB`                      | `apply_accent`                     | PRIMARY                                       |
| `config/tmux/tmux.conf`           | tmux config              | `#RRGGBB`                      | `apply_accent`                     | PRIMARY                                       |
| `config/dunst/dunstrc`            | INI (sections)           | `#RRGGBB`                      | `apply_accent`                     | PRIMARY                                       |
| `config/gtk/settings.ini`         | INI                      | icon theme name only           | `apply_accent` (Tela-name sed)     | Tela icon theme name                          |
| `config/kde/kdeglobals`           | INI (KDE color scheme)   | icon theme name only           | `apply_accent` (Tela-name sed)     | Tela icon theme name                          |
| `config/swaylock/config`          | key=value (one per line) | `RRGGBB` (bare, no `#`)       | `apply_accent` (bare hex branch)   | PRIMARY, DIM                                  |
| `config/bash/prompt.sh`           | bash script              | ANSI escape code (numeric)     | dedicated `sed` (not `apply_accent`) | ANSI code only                              |

Sway-only targets (`sway/config`, `waybar/style.css`, `swaylock/config`) are
conditionally included — only added to the file list when `sway` is on `$PATH`.

---

## Substitution Strategy

### The problem

Presets share colors across roles. For example, orange's SECONDARY (`#88DD00`)
is green's PRIMARY. A naive single-pass `sed s/old/new/g` would cause chain
reactions: replacing green PRIMARY with orange PRIMARY, then that same value
getting replaced again when processing another preset.

### Two-pass placeholder approach (`apply_accent` in `lib/common.sh`)

**Pass 0 — Cleanup.** Replace any leftover `@@placeholder@@` strings from a
previously interrupted run with the target preset's colors. This makes the
function safe to re-run after a crash.

**Pass 1 — Colors to placeholders.** For every preset *other than the target*,
replace its hex values with preset-specific placeholder tokens:
```
#ff8800  →  @@orange_PRIMARY@@
995200   →  @@BARE_orange_DIM@@    (for swaylock-style bare hex)
```
Also replaces `Tela-<preset>` with `Tela-<target>` in the same pass.

Case-insensitive matching (`sed .../gI`) handles mixed-case hex in config files.

Bare hex is handled with a separate sed that anchors on `=` to avoid false
matches mid-value: `s/=RRGGBB$/=@@BARE_preset_ROLE@@/gI`.

**Pass 2 — Placeholders to target colors.** All preset-specific placeholders
are replaced with the target preset's values:
```
@@orange_PRIMARY@@      →  #88DD00
@@BARE_orange_DIM@@     →  557700
```

### Bash prompt (special case)

The bash prompt uses ANSI escape codes, not hex. A single dedicated `sed`
replaces the numeric code in the `_GREEN="$(_pc NN)"` pattern:
```bash
sed -i "s/^\(_GREEN=\"\$(_pc \)[0-9]*/\1${ACCENT_ANSI}/" "$_prompt_file"
```

### Fish prompt

Fish prompt colors derive from variables set in `02-colors.fish`, which is
already processed by `apply_accent`. No additional substitution needed.

---

## Audit Mode

`audit` reads each target file and detects which preset's colors are present,
then compares against the expected preset from `scripts/env`.

### Detection methods

| Method | How it works | Used for |
|--------|--------------|----------|
| `hex`  | `grep -qi` for PRIMARY `#RRGGBB` of each preset | Most config files |
| `bare` | `grep -qi` for PRIMARY `RRGGBB` (no `#`) | swaylock/config |
| `ansi` | `sed -n` extracts numeric code from `_GREEN="$(_pc N)"` | bash/prompt.sh |

For gtk/kde where no hex colors are present, a fallback checks for `Tela-<preset>`
in the file content.

### Anomaly categories

| Result | Meaning |
|--------|---------|
| `OK` | Detected preset matches expected |
| `missing` | Target file not found |
| `broken` | Leftover `@@placeholder@@` tokens from interrupted run |
| `mixed(a+b)` | Multiple presets' colors detected in same file |
| `unknown` | No known preset colors found (falls through to Tela check) |
| `MISMATCH` | Detected preset differs from expected |

---

## Icon Theme (Tela)

Installed to `$HOME/.local/share/icons/Tela-<accent>` (user-local, no sudo).

Install logic:
1. If directory doesn't exist → install
2. If directory exists but `scalable/places/default-folder.svg` contains
   default blue (`#5294e2`) → reinstall (wrong accent baked in)
3. If directory exists but marker file missing → reinstall (incomplete)
4. Otherwise → skip

Installation clones `vinceliuice/Tela-icon-theme` (depth 1) into a temp
directory, runs `install.sh -d <target> <accent>`, then cleans up. Temp dir
is registered with the EXIT trap for cleanup on interrupt.

---

## Portability

| Concern | How it's handled |
|---------|------------------|
| No hardcoded usernames | All paths use `$HOME` or `$XDG_RUNTIME_DIR` |
| XDG compliance | Icons installed to `$HOME/.local/share/icons` (XDG data dir) |
| Log files | Written to `$XDG_RUNTIME_DIR` (falls back to `/tmp`), mode 077 |
| Repo-relative paths | `SCRIPT_DIR` and `REPO_DIR` computed from `$0` at runtime |
| Sway-optional | Sway-specific targets gated on `command -v sway` |
| Temp file safety | All temp dirs registered in `_cleanup_files[]`, cleaned by EXIT trap |
| Re-run safety | Pass 0 cleans leftover placeholders; Tela install checks existing state |
| Fedora-specific | `require_cmd` gives actionable `dnf install` hints |

---

## Dependencies

- `git` — cloning Tela icon theme
- `sed` — all color substitution (GNU sed, uses `-i` in-place and `I` flag)
- `grep` — preset detection in audit mode
- `bash` 4+ — associative arrays (`declare -A`)
- `scripts/lib/common.sh` — `COLOR_PRESETS`, `load_accent`, `apply_accent`,
  logging helpers, `require_cmd`
