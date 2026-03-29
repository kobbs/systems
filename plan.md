# Implementation plan

Implements `architecture.md` changes 1–17: profile as single source of truth, validation, CLI deprecation, packs, module::init phase, dedup, sed optimization, namespace prefixing, load_accent fix.

Each step is atomic. If you stop after any step, everything completed still works.

---

## Step 1 — Fix `load_accent` return code (bug 2)

**Files:** `lib/colors.sh`
**Does:** Change `return 0` to `return 1` on line 57 (green preset missing = fatal error).
**Depends on:** nothing
**Verify:**
```bash
bash -c 'source lib/config.sh; source lib/colors.sh; REPO_ROOT=.; COLOR_PRESETS=(); load_accent' 2>&1
# Must exit non-zero and print the error message
echo $?  # expect 1
```

---

## Step 2 — Fix `--accent` flag lookahead (bug 1)

**Files:** `modules/theme.sh` (function `_theme_parse_flags`, lines 440–462)
**Does:** Replace `_prev_arg` pattern with index-based lookahead. Error if `--accent` is the last argument.
**Depends on:** nothing
**Verify:**
```bash
# Source enough to define the function, then call it
bash -c '
  source lib/common.sh
  source lib/config.sh
  source lib/colors.sh
  REPO_ROOT=.
  source modules/theme.sh
  _theme_parse_flags --accent blue
  [[ "$_THEME_ACCENT_OVERRIDE" == "blue" ]] && echo "PASS: got blue"
'
bash -c '
  source lib/common.sh
  source lib/config.sh
  source lib/colors.sh
  REPO_ROOT=.
  source modules/theme.sh
  _theme_parse_flags --accent 2>&1
' && echo "FAIL: should have errored" || echo "PASS: errored on missing value"
```

---

## Step 3 — Deduplicate GPU detection into `lib/common.sh` (bug 3)

**Files:** `lib/common.sh`, `modules/system.sh`, `modules/packages.sh`
**Does:** Add `detect_gpu` in `lib/common.sh` setting `_HAS_DISCRETE_AMD_GPU`. Remove `_detect_gpu` from `system.sh`. Replace inline `lspci | grep` in `packages.sh` line 278 with a call to the shared function.
**Depends on:** nothing
**Verify:**
```bash
shellcheck lib/common.sh modules/system.sh modules/packages.sh
grep -n '_detect_gpu\|lspci.*AMD' modules/system.sh modules/packages.sh
# system.sh: should call detect_gpu (no underscore prefix)
# packages.sh: should call detect_gpu, no raw lspci grep
```

---

## Step 4 — Deduplicate mode detection into `lib/common.sh` (bug 4)

**Files:** `lib/common.sh`, `modules/system.sh`, `modules/packages.sh`
**Does:** Move mode detection to `detect_mode` in `lib/common.sh`. It reads `PROFILE_SYSTEM_SWAY_SPIN` (tri-state: true/false/auto). When `true`/`false`: use the profile value directly, ignore the mode file. When `auto`: detect via `rpm -q sway`, persist result to `~/.config/shell/.bootstrap-mode` as a cache for future `auto` runs. Remove `_detect_mode` from `system.sh` and `_read_mode` + flag parsing from `packages.sh`. Both modules call the shared function.
**Depends on:** step 3 (touching same files — avoid merge conflicts)
**Verify:**
```bash
shellcheck lib/common.sh modules/system.sh modules/packages.sh
grep -n '_detect_mode\|_read_mode\|--sway-spin\|--kde-spin' modules/system.sh modules/packages.sh
# No matches: modules no longer parse these flags or define mode functions
```

---

## Step 5 — Add `validate_profile` to `lib/config.sh` (change 16)

**Files:** `lib/config.sh`
**Does:** Add `validate_profile` function: known-key registry (28 keys), unknown key rejection, boolean type checking (`true`/`false`, plus `auto` for `sway_spin`). Fail-fast with clear error messages. Does NOT wire it into `setup` yet — function exists but isn't called.
**Depends on:** nothing
**Verify:**
```bash
bash -c '
  source lib/config.sh
  load_profile profiles
  validate_profile
  echo "PASS: valid profile accepted"
'
bash -c '
  source lib/config.sh
  _CONFIG=(); _parse_ini profiles/default.conf
  _CONFIG["system.typo_key"]="oops"
  validate_profile 2>&1
' && echo "FAIL" || echo "PASS: unknown key rejected"
bash -c '
  source lib/config.sh
  _CONFIG=(); _parse_ini profiles/default.conf
  _CONFIG["system.firewalld"]="yes"
  validate_profile 2>&1
' && echo "FAIL" || echo "PASS: bad boolean rejected"
```

---

## Step 6 — Add `_apply_cli_overrides` to `setup` and wire validation (changes 14, 16)

**Files:** `setup`
**Does:** After `load_profile` (line 16), add `validate_profile` call. Add `_apply_cli_overrides "$@"` function that translates deprecated flags (`--rocm`, `--devops`, `--sway-spin`, `--kde-spin`, `--corners`) to `PROFILE_*` overrides with deprecation warnings, and handles `--accent` as a permanent override. Update `usage()` to show new flag status. Remove per-module flag documentation from usage.
**Depends on:** step 5 (validate_profile must exist)
**Verify:**
```bash
bash -n setup  # syntax check
./setup help 2>&1 | grep -q "Deprecated"  # deprecation section in usage
# On a real system (or skip in container):
./setup status 2>&1  # still works — validation passes with current default.conf
```

---

## Step 7 — Add `module::init` phase to `run_module` (change 5)

**Files:** `setup`
**Does:** Modify `run_module` and `run_all_modules` to call `${module}::init "${args[@]}"` once before dispatching to check/preview/apply. No module changes yet — this step adds init support to the dispatcher. Modules that don't define `::init` won't break because we guard with `declare -F`.
**Depends on:** step 6 (setup was just modified — sequential to avoid conflicts)
**Verify:**
```bash
bash -n setup
# Existing modules don't define ::init yet, so run_module should still work:
./setup status 2>&1 | grep -q "Profile:"
```

---

## Step 8 — Namespace-prefix module internal functions (change 8)

**Files:** `modules/system.sh`, `modules/packages.sh`, `modules/shell-env.sh`, `modules/dotfiles.sh`, `modules/theme.sh`, `modules/apps.sh`
**Does:** Rename all internal helpers to use `_modulename_` prefix. E.g. `_detect_gpu` → `_system_detect_gpu` (already done in step 3 if moved to lib), `_build_pkg_list` → `_packages_build_pkg_list`, `_generate_env_content` → `_shellenv_generate_env_content`, `_condition_met` → `_dotfiles_condition_met`, `_theme_parse_flags` (already prefixed), `_apps_parse_flags` → `_apps_parse_flags` (already prefixed), etc. Update all call sites within each module.
**Depends on:** steps 3, 4 (some functions already moved to lib)
**Verify:**
```bash
shellcheck modules/*.sh
# Check no unprefixed private functions remain:
grep -nE '^_(detect|build|generate|read|check|condition|ensure|flatpak|get_all|pkg_line|install_tela|install_sddm|apply_sddm|set_sddm|load_apps)' modules/*.sh
# Should return nothing (all renamed)
```

---

## Step 9 — Refactor `system.sh`: add `::init`, read profile keys (changes 5, 17)

**Files:** `modules/system.sh`
**Does:** Add `system::init` that calls `detect_gpu` and `detect_mode` once (from lib). Remove init calls from `check`, `preview`, `apply`. Gate firewalld/bluetooth/tuned on `PROFILE_SYSTEM_FIREWALLD`, `PROFILE_SYSTEM_BLUETOOTH`, `PROFILE_SYSTEM_TUNED` in all three contract functions (check, preview, apply). Mode reads `PROFILE_SYSTEM_SWAY_SPIN` via the shared `detect_mode`.
**Depends on:** steps 3, 4, 7, 8
**Risk:** If `PROFILE_SYSTEM_FIREWALLD=false`, firewalld won't be enabled on next `--apply`. This is intentional (the whole point). No rollback needed — services stay in their current state.
**Verify:**
```bash
shellcheck modules/system.sh
# Grep confirms no direct flag parsing or unconditional service enables:
grep -n 'systemctl enable.*firewalld\|systemctl enable.*bluetooth\|systemctl enable.*tuned' modules/system.sh
# Each match should be inside an if-block checking PROFILE_SYSTEM_*
grep -n '\-\-sway-spin\|\-\-kde-spin' modules/system.sh
# No matches
```

---

## Step 10 — Refactor `packages.sh`: add `::init`, read profile keys (changes 5, 17)

**Files:** `modules/packages.sh`
**Does:** Add `packages::init`. Remove `_packages_parse_flags`. Read `PROFILE_PACKAGES_*` keys for all toggles: `dnf_update`, `rpm_fusion`, `codec_swaps`, `flatpak`, `cli_tools`, `security`, `rocm`. Read `PROFILE_SYSTEM_SWAY_SPIN` via `detect_mode`. Gate each action in `check`, `preview`, `apply` behind its boolean. `_packages_build_pkg_list` takes no args — reads module-level cached vars set by init.
**Depends on:** steps 4, 7, 8, 9 (system.sh done first since packages depends on system)
**Verify:**
```bash
shellcheck modules/packages.sh
grep -n '\-\-rocm\|\-\-sway-spin\|\-\-kde-spin' modules/packages.sh  # no matches
grep -c 'PROFILE_PACKAGES' modules/packages.sh  # should be >= 7 (one per toggle)
```

---

## Step 11 — Refactor `shell-env.sh`: add `::init`, conditional env generation (changes 5, 17)

**Files:** `modules/shell-env.sh`
**Does:** Add `shell-env::init` (reads `PROFILE_SHELL_DOCKER_ALIAS`, `PROFILE_SHELL_QT_ENV`, `PROFILE_SHELL_UNSET_SSH_ASKPASS`). Make `_shellenv_generate_env_content` conditional — only emit blocks where the corresponding profile key is `true`. If all three are false, emit only the header comment. Note: `firefox_wayland` is NOT in this module — it lives in `[apps]` and is applied by `apps.sh`.
**Depends on:** steps 7, 8
**Verify:**
```bash
shellcheck modules/shell-env.sh
# Test conditional generation:
bash -c '
  source lib/common.sh
  source lib/config.sh
  load_profile profiles   # defaults: all true
  source modules/shell-env.sh
  _shellenv_generate_env_content | grep -c "alias docker=podman"
'  # expect 1
bash -c '
  source lib/common.sh
  source lib/config.sh
  load_profile profiles
  export PROFILE_SHELL_DOCKER_ALIAS=false
  source modules/shell-env.sh
  _shellenv_generate_env_content | grep -c "alias docker=podman"
'  # expect 0
```

---

## Step 12 — Refactor `theme.sh`: add `::init`, read profile keys for tela + sddm (changes 5, 17)

**Files:** `modules/theme.sh`
**Does:** Add `theme::init`. Parse `--accent` (permanent), `--list`, `--audit` in init. Read `PROFILE_THEME_TELA_ICONS` and `PROFILE_THEME_SDDM_THEME` (stock/corners/none). Remove `--corners` handling. Gate Tela install on `tela_icons`. Replace `_THEME_CORNERS` boolean with `_THEME_SDDM_VARIANT` string from profile. `_theme_apply_sddm` uses variant: `stock`/`corners`/`none`. Remove redundant `load_all_presets`/`load_accent` calls from check/preview/apply (moved to init).
**Depends on:** steps 2, 7, 8
**Verify:**
```bash
shellcheck modules/theme.sh
grep -n '\-\-corners' modules/theme.sh  # no matches
grep -n 'PROFILE_THEME_TELA_ICONS\|PROFILE_THEME_SDDM_THEME' modules/theme.sh  # should have matches
```

---

## Step 13 — Refactor `apps.sh`: packs mechanism, profile-gated KVM/ProtonVPN/Firefox (changes 15, 17)

**Files:** `modules/apps.sh`
**Does:** Add `apps::init`. Remove `_apps_parse_flags`. Read `PROFILE_APPS_PACKS` (space-separated list), `PROFILE_APPS_DESKTOP_TOOLKIT`, `PROFILE_APPS_KVM`, `PROFILE_APPS_PROTONVPN`, `PROFILE_APPS_FIREFOX_WAYLAND`. Replace hardcoded `devops` qualifier check with generic packs lookup. Gate KVM post-install on `PROFILE_APPS_KVM`. Gate ProtonVPN on `PROFILE_APPS_PROTONVPN`. Gate Firefox Wayland env on `PROFILE_APPS_FIREFOX_WAYLAND`. Gate Flatpak sections on `PROFILE_PACKAGES_FLATPAK`.
**Depends on:** steps 7, 8
**Verify:**
```bash
shellcheck modules/apps.sh
grep -n '\-\-devops' modules/apps.sh  # no matches
grep -n 'PROFILE_APPS_PACKS\|PROFILE_APPS_KVM\|PROFILE_APPS_PROTONVPN\|PROFILE_APPS_FIREFOX_WAYLAND' modules/apps.sh  # should have matches
# Packs mechanism test:
bash -c '
  source lib/common.sh
  source lib/config.sh
  load_profile profiles
  export PROFILE_APPS_PACKS="base devops"
  source modules/apps.sh
  apps::init
  _apps_get_all_rpm_targets | grep -q kubectl && echo "PASS: devops pack active"
'
```

---

## Step 14 — Give `load_all_presets` its own parser (change 6)

**Files:** `lib/colors.sh`
**Does:** Replace `_parse_ini` usage in `load_all_presets` with a dedicated 10-line `key = value` parser. Remove the `_saved_config` save/restore dance. Color files have no sections — they don't need `_parse_ini`. The `_CONFIG` array is no longer touched.
**Depends on:** step 12 (theme.sh no longer calls `load_all_presets` redundantly)
**Verify:**
```bash
bash -c '
  source lib/config.sh
  source lib/colors.sh
  REPO_ROOT=.
  load_profile profiles
  load_all_presets
  [[ "${COLOR_PRESETS[green]}" == *"#88DD00"* ]] && echo "PASS: presets loaded"
  [[ "$(profile_get system hostname)" != "" ]] && echo "PASS: _CONFIG not clobbered"
'
```

---

## Step 15 — Optimize `apply_accent` sed calls (change 7)

**Files:** `lib/colors.sh`
**Does:** Refactor `apply_accent` to build a single sed expression per pass (accumulate `-e` args), then run one `sed -i` invocation per file per pass. Same 3-pass algorithm, ~30 sed calls instead of ~300.
**Depends on:** step 14 (colors.sh already modified)
**Verify:**
```bash
# Create a test file and run apply_accent on it:
bash -c '
  source lib/config.sh
  source lib/colors.sh
  REPO_ROOT=.
  load_all_presets
  export PROFILE_THEME_ACCENT=orange
  load_accent
  cp config/kitty/kitty.conf /tmp/test-accent.conf
  apply_accent /tmp/test-accent.conf
  grep -qi "#ff8800" /tmp/test-accent.conf && echo "PASS: orange primary applied"
  rm /tmp/test-accent.conf
'
```

---

## Step 16 — Add `dotfiles::init` stub (change 5 completeness)

**Files:** `modules/dotfiles.sh`
**Does:** Add empty `dotfiles::init` (no-op) and `audit::init` (no-op) so all modules have the init function. This makes `run_module` init dispatch uniform — no need for `declare -F` guards.
**Depends on:** step 7
**Verify:**
```bash
shellcheck modules/dotfiles.sh modules/audit.sh
bash -c 'source lib/common.sh; source lib/config.sh; source lib/colors.sh; source lib/links.sh; REPO_ROOT=.; source modules/dotfiles.sh; dotfiles::init && echo "PASS"'
```

---

## Step 17 — Update smoke tests for new profile system

**Files:** `tests/smoke.sh`, `tests/.containerignore` (new)
**Does:** Create `tests/.containerignore` (or `.containerignore` at repo root) excluding `profiles/local.conf` so tests run against pure defaults. Add tests for: (a) `validate_profile` accepts valid profile, (b) `validate_profile` rejects unknown key, (c) `validate_profile` rejects bad boolean, (d) packs mechanism activates correct sections, (e) existing tests still pass. Update `profile-load` test assertion to match new default hostname (empty string, not `fedora`).
**Depends on:** steps 5, 6, 13 (validation and packs must exist)
**Verify:**
```bash
# If podman is available:
./tests/smoke.sh
# Otherwise, syntax check:
bash -n tests/smoke.sh
grep -q 'local.conf' .containerignore  # containerignore excludes local.conf
```

---

## Step 18 — Update `setup` usage text and `CLAUDE.md` module contract

**Files:** `setup` (usage function), `CLAUDE.md`
**Does:** Final cleanup. Ensure `usage()` documents the new profile-driven workflow. Update `CLAUDE.md` module contract section to mention `::init`. No behavior change — documentation only.
**Depends on:** all prior steps
**Verify:**
```bash
./setup help 2>&1 | head -30   # should show updated usage with deprecated flags section
shellcheck setup
```

---

## Summary

| Step | What | Files |
|------|-------|-------|
| 1 | Fix load_accent return code | lib/colors.sh |
| 2 | Fix --accent flag lookahead | modules/theme.sh |
| 3 | Deduplicate GPU detection | lib/common.sh, modules/system.sh, modules/packages.sh |
| 4 | Deduplicate mode detection | lib/common.sh, modules/system.sh, modules/packages.sh |
| 5 | Add validate_profile | lib/config.sh |
| 6 | Wire validation + CLI overrides into setup | setup |
| 7 | Add module::init to dispatcher | setup |
| 8 | Namespace-prefix module functions | modules/*.sh |
| 9 | system.sh: init + profile gates | modules/system.sh |
| 10 | packages.sh: init + profile gates | modules/packages.sh |
| 11 | shell-env.sh: init + conditional gen | modules/shell-env.sh |
| 12 | theme.sh: init + profile gates | modules/theme.sh |
| 13 | apps.sh: packs + profile gates | modules/apps.sh |
| 14 | Standalone color preset parser | lib/colors.sh |
| 15 | Optimize apply_accent sed calls | lib/colors.sh |
| 16 | Init stubs for dotfiles + audit | modules/dotfiles.sh, modules/audit.sh |
| 17 | Smoke tests for new profile system | tests/smoke.sh |
| 18 | Usage text + CLAUDE.md update | setup, CLAUDE.md |

---

## Resolved decisions

1. **Mode file behavior:** `detect_mode` uses the mode file (`~/.config/shell/.bootstrap-mode`) as a runtime cache only when `sway_spin = auto`. When profile explicitly sets `true`/`false`, the mode file is ignored. Reflected in step 4.

2. **Test isolation:** `profiles/local.conf` is excluded from container builds via `.containerignore`. Tests run against pure defaults. Reflected in step 17.

3. **`firefox_wayland` location:** Moved from `[shell]` to `[apps]` section. Applied by `apps.sh`, read as `PROFILE_APPS_FIREFOX_WAYLAND`. Reflected in step 13. Requires updating `default.conf`, `local.conf.example`, `architecture.md`, and the known-key registry in `validate_profile` (step 5).

4. **`[special]` section in `apps.conf`:** Deferred to a separate task. Not part of this plan.

5. **`kvm` and `protonvpn` defaults:** Both default to `false`. A blank `local.conf` produces a minimal system without KVM or ProtonVPN. Requires updating `default.conf`.
