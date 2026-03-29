# Architecture

## Changes from previous version

### Profile as single source of truth

13. **`local.conf` becomes the single source of truth.** Previously, system behavior was split across CLI flags (`--rocm`, `--devops`, `--sway-spin`, `--corners`), hardcoded unconditional actions (firewalld, bluetooth, tuned, codec swaps, CLI tools, security packages), and a sparse 8-key profile. A user could not read any single file and know what their system would look like after a run. Fix: every action the bootstrap performs now has a corresponding toggle or value in the profile. `default.conf` expands from 8 to 28 keys. A blank `local.conf` produces a working system with sensible defaults.

14. **CLI flags are deprecated in favor of profile keys.** `--rocm`, `--devops`, `--sway-spin`/`--kde-spin`, and `--corners` are translated to profile overrides with a deprecation warning. Modules read only `PROFILE_*` variables — they never parse CLI flags directly. `--accent <name>` is retained as a permanent convenience for one-off testing.

15. **Packs mechanism replaces `--devops` flag.** The `apps.packs` profile key is a space-separated list of pack names. Each name activates matching `:qualifier` sections in `apps.conf`. Adding a pack means tagging `apps.conf` sections and adding the name to `packs` — no code changes. Toolkit qualifiers (`:gtk`/`:qt`) remain driven by `desktop_toolkit`, not packs.

16. **Profile validation catches typos at startup.** `validate_profile` in `lib/config.sh` runs immediately after `load_profile`. It checks every key against a known-key registry and rejects unknown keys with a clear error. Boolean keys are validated for `true`/`false` values. This is fail-fast — unknown keys abort before any module runs.

17. **Previously unconditional actions are now toggleable.** Firewalld, bluetooth, tuned, DNF update, RPM Fusion, codec swaps, Flathub, CLI tools, security packages, Tela icons, SDDM theming, KVM, and ProtonVPN all have boolean toggles. Shell-env content (docker alias, Qt env vars, SSH_ASKPASS) is individually toggleable.

### Bugs fixed

1. **`--accent` flag silently drops its value.** `_theme_parse_flags` uses a `_prev_arg` variable to associate `--accent` with the next argument. If `--accent` is the last argument, no value is captured and the override silently becomes empty string. Fix: use index-based lookahead and error if no value follows.

2. **`load_accent` doesn't fail when no presets are loaded.** If the green fallback preset is missing (meaning `load_all_presets` was never called or colors/ is empty), `load_accent` prints an error but returns 0. Callers proceed with empty `ACCENT_*` variables. Fix: return 1 — this is genuinely fatal.

3. **Duplicate GPU detection.** `_detect_gpu()` in system.sh and an inline `lspci | grep` in packages.sh (ROCm section) both detect AMD GPUs independently. If the detection logic needs updating, two places must change. Fix: single `detect_gpu` function in `lib/common.sh`.

4. **Duplicate mode handling.** `_detect_mode()` in system.sh writes the mode file; `_read_mode()` in packages.sh reads it back. Both modules independently parse `--sway-spin`/`--kde-spin` flags. Fix: single `detect_mode` function in `lib/common.sh` that handles flag parsing, file persistence, and auto-detection. Both modules call it.

### Complexity removed

5. **Repeated initialization in every contract function.** system.sh calls `_detect_gpu` + `_detect_mode` in check(), preview(), and apply(). theme.sh calls `load_all_presets` + `load_accent` + `_theme_parse_flags` in all four contract functions. This means the same work runs 2-3 times per invocation, and every contract function must remember the right init sequence. Fix: add a `module::init` phase. `run_module` calls init once before dispatching to check/preview/apply. Contract functions use cached state.

6. **`_CONFIG` global shared between profiles and color presets.** `load_all_presets()` must save/restore the `_CONFIG` associative array because `_parse_ini` writes to a single global, and color `.conf` files are parsed through the same function as profiles. If a future caller forgets the save/restore dance, profile data gets clobbered. Fix: `load_all_presets` uses its own 10-line key=value parser that reads directly into a local associative array. Color files are simple `key = value` with no sections — they don't need `_parse_ini`.

7. **`apply_accent` spawns O(presets x roles) sed processes per file.** For 3 presets and 5 color roles, each of the 3 passes runs ~15 separate `sed -i` invocations per file. Across 11 target files, that's ~300 sed calls per theme apply. Fix: build a single sed expression string (one `-e` per substitution) and apply it in one `sed -i` invocation per file per pass. Same algorithm, ~30 sed calls total instead of ~300.

8. **Module function namespaces leak.** `run_module` sources module files at call time into the same shell. Function names from earlier modules persist — if two modules define `_detect_gpu`, the second silently overwrites the first. Fix: prefix all module-internal functions with the module name: `_system_detect_gpu`, `_theme_parse_flags`, etc.

### Things that were unclear, now specified

9. **Module execution order is hardcoded but dependencies are undocumented.** The `_MODULE_ORDER` array says `system packages shell-env dotfiles theme apps` but doesn't explain why. See [Execution model](#execution-model) for the dependency rationale.

10. **Error return convention is inconsistent.** Some helpers return 0 on failure (non-fatal skip), others return 1 (abort). Under `set -euo pipefail`, a `return 1` from a helper kills the script unless the caller traps it. Convention is now documented: return 0 + `warn` for non-fatal skips, return 1 for fatal errors. See [Conventions](#conventions).

11. **Audit module doesn't follow the contract.** `audit::check` always returns 0, `audit::preview` just calls `audit::apply`, and setup dispatches it specially. Audit is a read-only utility, not a stateful module. It keeps the `::check`/`::apply` interface for consistency with `run_module`, but the architecture acknowledges that its check is always-true and its preview equals apply.

12. **ProtonVPN and Terraform break "apps.conf is the single source of truth."** Both require special repo-probing or conditional logic that can't be expressed as a package name in a config file. They are now documented as special-install apps. Their package names appear in `apps.conf` under a `[special]` section for audit/manifest tracking, but install logic stays in `apps.sh`.

---

## Execution model

```
./setup <command> [--apply] [flags]
```

Dry-run by default. `--apply` executes changes. Single-threaded, linear, no parallelism.

### Startup sequence

```
load_profile profiles/          # Parse default.conf + local.conf overlay
validate_profile                # Reject unknown keys, validate types — fail-fast
_apply_cli_overrides "$@"       # Deprecated flags → PROFILE_* overrides + warnings
run_module ...                  # Dispatch to modules
```

### Module lifecycle

`run_module` dispatches each module through this sequence:

```
source module file
  -> module::init(flags)     # parse flags, detect state, cache results (runs once)
  -> module::check()         # return 0 if changes needed, 1 if up-to-date
  -> module::preview()       # print what would change (dry-run)
     OR module::apply()      # execute changes (--apply)
```

`module::status()` is called independently by `./setup status` — it does not go through init/check.

### Module order and dependencies

```
system -> packages -> shell-env -> dotfiles -> theme -> apps
```

| Step | Depends on | Why |
|---|---|---|
| system | nothing | Persists mode file (`~/.config/shell/.bootstrap-mode`), sets hostname, enables services |
| packages | system | Reads mode file to decide Sway package set (common-only vs full stack) |
| shell-env | packages | Needs `~/.config/shell/` directory to exist (created by package setup or prior runs) |
| dotfiles | shell-env | Symlinks config files; bootstrap-env.sh must exist before .bashrc sources it |
| theme | dotfiles | Modifies config files in-place — files must be symlinked into `config/` first |
| apps | packages | Needs repos configured, flatpak installed |

Each module is independently re-runnable and idempotent. Running out of order works (may skip steps or warn), but the full `install` command runs them in this order.

### Dispatch commands

| Command | Action |
|---|---|
| `install` | Run all modules in order |
| `<module>` | Run single module |
| `audit` | Package manifest audit (read-only) |
| `diff` | Show preview for all modules |
| `status` | One-line summary per module |

### CLI flags

```
Global:
  --apply                Execute changes (default is dry-run)

Permanent:
  --accent <name>        Override accent color (one-off, not persisted to profile)

Read-only utilities:
  theme --list           List available color presets
  theme --audit          Check config files for color drift

Deprecated (use profiles/local.conf instead):
  --sway-spin            -> system.sway_spin = true
  --kde-spin             -> system.sway_spin = false
  --rocm                 -> packages.rocm = true
  --devops               -> apps.packs = base devops
  --corners              -> theme.sddm_theme = corners
```

Deprecated flags are translated to `PROFILE_*` overrides with a warning. They will be removed in a future version.

---

## Module contract

Every module in `modules/` exports five functions:

```bash
module::init()      # Parse flags, detect state, cache to module-level vars
module::check()     # Return 0 = changes needed, 1 = up-to-date
module::preview()   # Print what would change (read-only)
module::apply()     # Execute changes (idempotent)
module::status()    # One-line current state summary (standalone, no init)
```

Rules:
- `init` runs exactly once per `run_module` invocation. check/preview/apply use cached state from init.
- `check` must be fast. No network calls, no sudo. Read local files and system state only.
- `preview` and `apply` may call sudo, download packages, clone repos.
- `status` is self-contained — it does its own minimal detection, does not depend on `init`.
- Internal helper functions are prefixed with `_modulename_` (e.g., `_theme_install_tela`, `_system_detect_gpu`).

### Error convention

Under `set -euo pipefail` (inherited from `setup`):

- **return 0 + `warn`**: non-fatal skip (source file missing, optional feature unavailable, network probe failed). Caller continues.
- **return 1**: fatal error that should abort the module. Only use when continuing would produce a broken state.
- Never `return 1` from a helper called in a pipeline or `if` — `set -e` won't catch it there, so the behavior is inconsistent. Use explicit error checking instead.

---

## Module responsibilities

### system

**Reads:** `PROFILE_SYSTEM_HOSTNAME`, `PROFILE_SYSTEM_KEYBOARD_LAYOUT`, `PROFILE_SYSTEM_SWAY_SPIN`, `PROFILE_SYSTEM_FIREWALLD`, `PROFILE_SYSTEM_BLUETOOTH`, `PROFILE_SYSTEM_TUNED`, `lspci` output.

**Writes:** hostname (`hostnamectl`), keyboard layout (`localectl`), user groups (`video`, `render`), service state for firewalld/bluetooth/tuned. Persists `~/.config/shell/.bootstrap-mode`.

**Init detects:** GPU presence, Sway Spin mode (`PROFILE_SYSTEM_SWAY_SPIN`: `true`/`false` = force, `auto` = detect via `rpm -q sway` on first run then persist). Mode is persisted on first detection to prevent flip-flopping after Sway is installed by a later module.

**Profile-gated actions:**
| Profile key | Action when true | Action when false |
|---|---|---|
| `firewalld` | `systemctl enable --now firewalld` | skip |
| `bluetooth` | `systemctl enable --now bluetooth` | skip |
| `tuned` | `systemctl enable --now tuned` | skip |

### packages

**Reads:** `PROFILE_SYSTEM_SWAY_SPIN`, `PROFILE_PACKAGES_DNF_UPDATE`, `PROFILE_PACKAGES_RPM_FUSION`, `PROFILE_PACKAGES_CODEC_SWAPS`, `PROFILE_PACKAGES_FLATPAK`, `PROFILE_PACKAGES_CLI_TOOLS`, `PROFILE_PACKAGES_SECURITY`, `PROFILE_PACKAGES_ROCM`, `rpm -q` for installed state.

**Writes:** RPM Fusion repos, codec swaps, Flathub remote, system packages. Records to `~/.config/shell/.pkg-manifest`.

**Package groups:**
- `_SWAY_COMMON_PKGS` — always installed (bemenu, kitty, plasma-integration, etc.)
- `_SWAY_EXTRA_PKGS` — only on non-Sway-Spin (sway, waybar, swaylock, etc.)
- `_CLI_PKGS` — gated by `PROFILE_PACKAGES_CLI_TOOLS`
- `_SECURITY_PKGS` — gated by `PROFILE_PACKAGES_SECURITY`
- `_ROCM_PKGS` — gated by `PROFILE_PACKAGES_ROCM` + discrete AMD GPU

**Apply order:** dnf update (if `dnf_update`) -> RPM Fusion repos (if `rpm_fusion`) -> Cisco OpenH264 + codec swaps (if `codec_swaps`) -> Flathub (if `flatpak`) -> Sway packages -> CLI tools (if `cli_tools`) -> security tools (if `security`) -> ROCm (if `rocm`).

### shell-env

**Reads:** `PROFILE_SHELL_DOCKER_ALIAS`, `PROFILE_SHELL_QT_ENV`, `PROFILE_SHELL_UNSET_SSH_ASKPASS`.

**Writes:** `~/.config/shell/bootstrap-env.sh` (atomically via temp file + `cmp -s`), appends source line to `~/.bashrc`.

**Generated env content is conditional:**

| Profile key | Lines emitted when true |
|---|---|
| `docker_alias` | `alias docker=podman`, `export KIND_EXPERIMENTAL_PROVIDER=podman` |
| `qt_env` | `export QT_QPA_PLATFORMTHEME=kde`, `export QT_STYLE_OVERRIDE=Breeze` |
| `unset_ssh_askpass` | `unset SSH_ASKPASS` |

If all three are false, bootstrap-env.sh is empty (header comment only). The `.bashrc` source line is always added (non-optional base dependency).

### dotfiles

**Reads:** `_SYMLINK_MAP` and `_LOCAL_OVERRIDES` arrays (declarative, defined at top of file).

**Writes:** symlinks from `config/` into `~/.config/`, local override stub files, `.bashrc` source lines for prompt.sh and completions.sh, `chmod +x` on waybar scripts.

**Conditions:** `always`, `sway` (command -v sway), `fish` (command -v fish). Evaluated at deploy time.

**Symlink map format:** `"source_relative|target_absolute|condition"`. Single source can map to multiple targets (e.g., `gtk/settings.ini` -> both `gtk-3.0` and `gtk-4.0`).

**Local overrides:** created once, never overwritten. Per-machine customization files (e.g., `~/.config/sway/config.local`).

### theme

**Reads:** `PROFILE_THEME_ACCENT`, `PROFILE_THEME_TELA_ICONS`, `PROFILE_THEME_SDDM_THEME`, color presets from `colors/*.conf`, current state of config files. `--accent <name>` overrides `PROFILE_THEME_ACCENT` for one-off testing.

**Writes:** accent colors into config files (in-place sed), Tela icon theme to `~/.local/share/icons/`, SDDM theme to `/usr/share/sddm/themes/` and `/etc/sddm.conf.d/`.

**Init:** load presets, load accent, detect current preset in all target files.

**Apply order:**
1. Install Tela icon theme (if `tela_icons` = true) — git clone + installer, user-local to `~/.local/share/icons/`
2. Apply accent colors to config files via `apply_accent`
3. Update bash prompt ANSI code (separate sed — ANSI codes, not hex)
4. Configure SDDM based on `sddm_theme`:
   - `stock` — dark background PNG, stock Fedora theme
   - `corners` — git clone + Qt6 QML patch
   - `none` — skip SDDM theming entirely

**Special modes:** `--list` and `--audit` bypass the normal check/apply flow. They print information and return.

**SDDM sub-concern:** SDDM theming lives inside theme.sh because the SDDM `theme.conf` receives accent color substitution. The decomposition is:
- `_theme_install_sddm_corners` — git clone, Qt6 QML patch, deploy
- `_theme_apply_sddm_stock` — copy dark background PNG
- `_theme_set_sddm_active` — write `/etc/sddm.conf.d/theme.conf`, disable greetd, enable sddm

### apps

**Reads:** `apps.conf` (parsed by module-internal INI reader), `PROFILE_APPS_DESKTOP_TOOLKIT`, `PROFILE_APPS_PACKS`, `PROFILE_APPS_KVM`, `PROFILE_APPS_PROTONVPN`, `PROFILE_APPS_FIREFOX_WAYLAND`.

**Writes:** third-party repos to `/etc/yum.repos.d/`, RPM packages, Flatpak apps, `MOZ_ENABLE_WAYLAND=1` to `/etc/environment`, KVM group membership.

**apps.conf section resolution:**

| Qualifier | Activation rule |
|---|---|
| `[section]` | Always (base) |
| `[section:devops]` | `devops` in `PROFILE_APPS_PACKS` |
| `[section:gtk]` | `PROFILE_APPS_DESKTOP_TOOLKIT == gtk` |
| `[section:qt]` | `PROFILE_APPS_DESKTOP_TOOLKIT == qt` |
| `[flatpak:section]` | Always, gated by `PROFILE_PACKAGES_FLATPAK` |
| `[special]` | Tracked in manifest; install logic in apps.sh |

**Profile-gated actions:**
| Profile key | Action |
|---|---|
| `kvm` | Install KVM stack + `usermod -aG libvirt` + enable libvirtd |
| `protonvpn` | Probe repo.protonvpn.com + install release RPM + proton-vpn-gtk-app |
| `firefox_wayland` | Append `MOZ_ENABLE_WAYLAND=1` to `/etc/environment` |

**Special-install apps** (repo probing or conditional logic that can't be data-driven):
- **ProtonVPN**: probes `repo.protonvpn.com/fedora-{ver}-stable/` for current and 2 previous Fedora versions. Gated by `PROFILE_APPS_PROTONVPN`.
- **Terraform**: conditional on HashiCorp repo availability. Repo URL uses `$releasever` which is replaced with a concrete version via `find_fedora_version`. Only installed when `devops` is in `PROFILE_APPS_PACKS`.

**Apply order:** repos -> bulk RPM install -> terraform (if devops pack + repo available) -> ProtonVPN (if `protonvpn`) -> Flatpaks (if `flatpak`) -> KVM post-setup (if `kvm`).

### audit

Read-only utility. Does not modify system state.

- `audit::check` always returns 0 (always has output to produce)
- `audit::preview` calls `audit::apply` (the action itself is read-only)
- Collects leaf packages via `dnf5 leaves`, cross-references with `~/.config/shell/.pkg-manifest` and `.flatpak-manifest`
- Writes report to `/var/tmp/pkg-audit-YYYYMMDD.txt`

---

## Profile system

### Files

Three files in `profiles/`:
- `default.conf` — checked into git, all 28 keys with sensible defaults
- `local.conf` — gitignored, per-machine overrides (only set what differs)
- `local.conf.example` — documented template with all keys commented out

`load_profile` parses both (default first, local overlays). Keys stored in `_CONFIG` as `"section.key"`. Every entry exported as `PROFILE_SECTION_KEY` (uppercased, dashes to underscores).

A missing or empty `local.conf` produces a working minimal system using only defaults.

### Profile schema

| Section | Key | Type | Default | Module | Controls |
|---|---|---|---|---|---|
| system | hostname | string | *(empty)* | system | hostnamectl set-hostname (skipped when empty) |
| system | keyboard_layout | string | *(empty)* | system | localectl set-x11-keymap (skipped when empty) |
| system | sway_spin | tri-state | auto | system, packages | Sway Spin mode: true/false/auto |
| system | firewalld | boolean | true | system | Enable firewalld service |
| system | bluetooth | boolean | true | system | Enable bluetooth service |
| system | tuned | boolean | true | system | Enable tuned service |
| packages | dnf_update | boolean | true | packages | Run dnf update at start |
| packages | rpm_fusion | boolean | true | packages | Enable RPM Fusion free + nonfree repos |
| packages | codec_swaps | boolean | true | packages | Cisco OpenH264 + ffmpeg/mesa freeworld swaps |
| packages | flatpak | boolean | true | packages, apps | Flathub remote + all flatpak installs |
| packages | cli_tools | boolean | true | packages | CLI utilities (bat, fzf, ripgrep, etc.) |
| packages | security | boolean | true | packages | pam-u2f, yubikey-manager |
| packages | rocm | boolean | false | packages | ROCm runtime (needs discrete AMD GPU) |
| theme | accent | string | green | theme | Color preset from colors/*.conf |
| theme | gtk_theme | string | Adwaita-dark | dotfiles | GTK theme name in settings.ini |
| theme | icon_theme | string | Tela | theme, dotfiles | Icon theme base name |
| theme | cursor_theme | string | Adwaita | dotfiles | Cursor theme |
| theme | tela_icons | boolean | true | theme | Install Tela icon theme via git clone |
| theme | sddm_theme | string | stock | theme | SDDM variant: stock / corners / none |
| shell | default_shell | string | bash | (informational) | Documented default shell |
| shell | docker_alias | boolean | true | shell-env | alias docker=podman + KIND provider |
| shell | qt_env | boolean | true | shell-env | QT_QPA_PLATFORMTHEME + QT_STYLE_OVERRIDE |
| shell | unset_ssh_askpass | boolean | true | shell-env | unset SSH_ASKPASS |
| apps | desktop_toolkit | string | qt | apps | Activate :gtk or :qt sections in apps.conf |
| apps | packs | list | base | apps | Space-separated pack names for apps.conf qualifiers |
| apps | firefox_wayland | boolean | true | apps | MOZ_ENABLE_WAYLAND=1 in /etc/environment |
| apps | kvm | boolean | false | apps | KVM stack + libvirt group |
| apps | protonvpn | boolean | false | apps | ProtonVPN special install |

### Packs

The `apps.packs` key is a space-separated list of pack names. Each name activates the matching qualifier in `apps.conf` sections. `base` (unqualified sections) is always included implicitly.

Example: `packs = base devops` activates `[section]` (always), `[section:devops]`, and the toolkit-qualified sections based on `desktop_toolkit`.

Toolkit qualifiers (`:gtk`, `:qt`) are not packs — they are driven by `apps.desktop_toolkit`.

Adding a new pack requires two steps:
1. Tag `apps.conf` sections with the new qualifier (e.g., `[tools:science]`)
2. Add the name to `packs` in `local.conf` (e.g., `packs = base devops science`)

No code changes needed.

### CLI flag deprecation

CLI flags are translated to `PROFILE_*` overrides by `_apply_cli_overrides` in `setup`, after `load_profile` and `validate_profile`. Each deprecated flag prints a warning suggesting the profile key instead.

| CLI Flag | Profile override | Notes |
|---|---|---|
| `--sway-spin` | `PROFILE_SYSTEM_SWAY_SPIN=true` | Deprecated |
| `--kde-spin` | `PROFILE_SYSTEM_SWAY_SPIN=false` | Deprecated |
| `--rocm` | `PROFILE_PACKAGES_ROCM=true` | Deprecated |
| `--devops` | Appends `devops` to `PROFILE_APPS_PACKS` | Deprecated |
| `--corners` | `PROFILE_THEME_SDDM_THEME=corners` | Deprecated |
| `--accent <name>` | `PROFILE_THEME_ACCENT=<name>` | **Permanent** — useful for one-off testing |

Modules never parse CLI flags directly. They read only `PROFILE_*` variables.

### Validation

`validate_profile` in `lib/config.sh` runs immediately after `load_profile`, before any module executes:

1. **Unknown key detection.** Every key in `_CONFIG` is checked against a hardcoded known-key registry. Unknown keys produce a clear error naming the offending key and abort.
2. **Boolean validation.** Keys typed as boolean must be `true` or `false` (plus `auto` for `sway_spin`). Values like `yes`, `1`, `on` are rejected with a message suggesting the correct format.
3. **Fail-fast.** All validation errors are collected and reported together, then the script aborts before any module runs.

### Non-optional base dependencies

These actions have no profile toggle because disabling them would break the bootstrap itself:

| Action | Why |
|---|---|
| `dnf-plugins-core` install | Required for `dnf config-manager` used by repo setup |
| Mode file persistence (`~/.config/shell/.bootstrap-mode`) | Internal runtime cache for Sway Spin detection |
| Package manifest recording (`~/.config/shell/.pkg-manifest`) | Required for audit module to function |
| `.bashrc` source line for bootstrap-env.sh | Required for shell-env settings to take effect |

Everything else is toggleable via the profile.

---

## Accent color system

### Preset format

Each `colors/*.conf` file defines one preset with 6 values:

```ini
name = green
primary = #88DD00
dim = #557700
dark = #2A3B00
bright = #8BE235
secondary = #ffaa00
ansi = 92
```

Adding a preset = adding a file. No code changes needed.

### Resolution

`PROFILE_THEME_ACCENT` (from profile) > `--accent` flag (one-off override) > `"green"` (hardcoded fallback).

`load_accent` reads the resolved preset into `ACCENT_NAME`, `ACCENT_PRIMARY`, `ACCENT_DIM`, `ACCENT_DARK`, `ACCENT_BRIGHT`, `ACCENT_SECONDARY`, `ACCENT_ANSI`.

### Target files

| File | Format | Notes |
|---|---|---|
| `sway/config` | hex (#RRGGBB) | Only if sway installed |
| `waybar/style.css` | hex | Only if sway installed |
| `kitty/kitty.conf` | hex | |
| `tmux/tmux.conf` | hex | |
| `dunst/dunstrc` | hex | |
| `sddm/theme.conf` | hex | |
| `gtk/settings.ini` | hex + Tela icon name | |
| `kde/kdeglobals` | hex + Tela icon name | |
| `fish/conf.d/02-colors.fish` | hex | |
| `swaylock/config` | bare (RRGGBB, no #) | |
| `bash/prompt.sh` | ANSI code (integer) | Separate sed, not apply_accent |

### Two-pass placeholder algorithm

The core problem: config files contain hex color values inline. When switching from green to orange, a naive `sed s/green_primary/orange_primary/` works — unless two presets share a color value, causing chain reactions (green->orange, then orange->blue catches the value just written).

The algorithm uses intermediate placeholders to prevent this:

**Pass 0 — Clean up leftover placeholders** from interrupted previous runs. Replace any `@@PRESET_ROLE@@` or `@@BARE_PRESET_ROLE@@` with target colors. This makes the algorithm crash-safe.

**Pass 1 — Colors to placeholders.** For every preset except the target, replace its color values with named placeholders (`@@GREEN_PRIMARY@@`, `@@BARE_GREEN_PRIMARY@@`). Case-insensitive matching (hex values may be upper or lower). Also replaces `Tela-{preset}` icon theme names.

**Pass 2 — Placeholders to target colors.** Replace all placeholders with the target preset's color values. Case-sensitive (placeholders are uppercase).

**Invariant:** After pass 1, no preset's colors appear literally in the file (they're all placeholders). Pass 2 then writes only the target colors. Chain reactions are impossible.

**Implementation improvement:** build all substitutions for each pass as a single sed expression string, then run one `sed -i` per file per pass. This reduces ~300 process spawns to ~30.

### Bash prompt

The bash prompt uses ANSI color codes (integers like `92`), not hex. It gets a dedicated `sed` that updates the `_GREEN="$(_pc XX)"` pattern in `prompt.sh`. This is outside `apply_accent` because ANSI codes are a different format entirely.

---

## Testing

Container-based smoke tests in `tests/`:

```bash
./tests/smoke.sh        # builds Podman image, runs tests
```

**What's tested:** profile loading, profile validation (unknown key rejection, boolean validation), color preset loading, accent resolution, link library, setup help/status output, theme --list, theme --audit, packs mechanism, shellcheck on all .sh files.

**What's NOT tested** (requires real system): package installation, hardware detection (GPU, keyboard), systemd services, SDDM deployment, GUI rendering, sudo operations.

**Adding a test:** add a `run_test "name" 'shell commands'` call to `tests/smoke.sh`. Tests run inside a Fedora container with bash, coreutils, grep, sed, shellcheck, pciutils.

---

## Runtime file manifest

Files created outside the repo during apply:

| Path | Created by | Purpose |
|---|---|---|
| `~/.config/shell/bootstrap-env.sh` | shell-env | Shell environment vars and aliases |
| `~/.config/shell/.bootstrap-mode` | system | Persisted Sway Spin mode (true/false) |
| `~/.config/shell/.pkg-manifest` | packages, apps | List of managed RPM packages |
| `~/.config/shell/.flatpak-manifest` | apps | List of managed Flatpak apps |
| `~/.config/shell/prompt.sh` | dotfiles (symlink) | Bash prompt |
| `~/.config/shell/completions.sh` | dotfiles (symlink) | Bash completions |
| `~/.config/sway/config.local` | dotfiles | Per-machine Sway overrides |
| `~/.config/fish/config.local.fish` | dotfiles | Per-machine Fish overrides |
| `~/.config/dunst/dunstrc.local` | dotfiles | Per-machine Dunst overrides |
| `~/.config/kitty/config.local` | dotfiles | Per-machine Kitty overrides |
| `~/.config/tmux/local.conf` | dotfiles | Per-machine tmux overrides |
| `~/.config/Yubico/` | packages | Yubikey config directory |
| `~/.local/share/icons/Tela-{accent}/` | theme | Accent-colored icon theme |
| `/etc/sddm.conf.d/theme.conf` | theme | SDDM active theme selector |
| `/usr/share/sddm/themes/corners/` | theme (sddm_theme=corners) | SDDM corners theme files |
| `/etc/yum.repos.d/amdgpu.repo` | packages (rocm=true) | AMD GPU repo |
| `/etc/yum.repos.d/rocm.repo` | packages (rocm=true) | ROCm repo |
| `/etc/yum.repos.d/brave-browser.repo` | apps | Brave browser repo |
| `/etc/yum.repos.d/hashicorp.repo` | apps (devops pack) | HashiCorp repo |
| `/etc/yum.repos.d/kubernetes.repo` | apps (devops pack) | Kubernetes repo |
| `/var/tmp/pkg-audit-YYYYMMDD.txt` | audit | Package audit report |

---

## Conventions

### Function naming

- `module::public` — exported contract functions (e.g., `theme::apply`)
- `_modulename_private` — module-internal helpers (e.g., `_theme_install_tela`)
- `lib_function` — library functions (e.g., `load_accent`, `link_file`, `pkg_install`)
- `_lib_internal` — library-internal helpers (e.g., `_parse_ini`)

### Package lists

One package per line, sorted alphabetically. This makes diffs clean and duplicates easy to spot.

### Error handling

`set -euo pipefail` is inherited from `setup`. All modules run under it.

- `return 0` + `warn` for non-fatal skips (missing optional file, network probe failed, feature not applicable)
- `return 1` for fatal errors (missing required preset, broken state that would propagate)
- Never call `exit` from a module — let the caller decide what to do
- Backups use timestamps (`*.bak.YYYYMMDDHHMMSS`) to prevent overwriting previous backups

### Idempotency patterns

| Pattern | Used for | How |
|---|---|---|
| `rpm -q` / `command -v` | Skip if already installed/present | Guard before install |
| `grep -qFx` before append | Prevent duplicate lines | .bashrc, manifests |
| `readlink` before symlink | Skip if already correct | `link_file` |
| `cmp -s` before write | Skip if content unchanged | bootstrap-env.sh, SDDM conf |
| Mode file persistence | Prevent detection flip-flop | `.bootstrap-mode` written once |
| Flatpak `--if-not-exists` | Idempotent remote add | Flathub setup |

### Logs

Use `$XDG_RUNTIME_DIR` (user-private, tmpfs), not `/tmp` (world-writable). Audit reports go to `/var/tmp` (survives reboot, appropriate for reports).

### No dead code

Don't comment out old configs or themes. Git history is the archive. Keep only the active configuration.
