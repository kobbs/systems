# systems

Fedora workstation bootstrap and dotfiles.

**Stack:** Fedora 43, Sway/Wayland, Waybar, Kanshi

## Repo structure

```
setup                   Single entry point (executable)

modules/                Independent, composable modules
  system.sh             Hostname, keyboard, GPU groups, firewall, services
  packages.sh           System packages, repos, codecs
  shell-env.sh          Shell environment (bootstrap-env.sh)
  dotfiles.sh           Symlink configs into ~/.config/
  theme.sh              Accent colors, icon theme, SDDM
  apps.sh               User-facing applications
  audit.sh              Package manifest audit (read-only)

lib/                    Shared library
  common.sh             Logging, preflight, pkg_install, find_fedora_version
  config.sh             INI profile parser
  colors.sh             Color presets + apply_accent
  links.sh              Symlink helpers (link_file, check_link)

profiles/               Machine configuration (declarative)
  default.conf          Base settings (checked in)
  local.conf            Per-machine overrides (gitignored)

colors/                 Color preset definitions
  green.conf            Green accent preset
  orange.conf           Orange accent preset
  blue.conf             Blue accent preset

config/                 Dotfiles (source of truth)
  sway/                 Sway compositor
  waybar/               Waybar modules, styles, and scripts
  kanshi/               Per-machine display profiles
  kitty/                Kitty terminal
  tmux/                 tmux
  dunst/                Dunst notification daemon
  swaylock/             Swaylock screen locker
  sddm/                SDDM greeter theme
  gtk/                  GTK 3/4 dark theme (single file → both gtk-3.0 and gtk-4.0)
  qt5ct/ qt6ct/         Qt theme settings
  kde/                  KDE Frameworks color scheme (kdeglobals)
  bash/                 Shell prompt + completions
  fish/                 Fish shell (optional)

tests/                  Container-based smoke tests (Podman)
documentation/          Reference cheatsheets
specs/                  Architecture and design documents
```

---

## Quick start

```bash
# 1. Preview all changes (dry-run, no modifications)
./setup install

# 2. Apply everything
./setup install --apply

# 3. Reboot to apply group changes and keyboard layout
```

## Individual modules

```bash
./setup system --apply          # Hostname, keyboard, GPU groups, firewall
./setup packages --apply        # System packages and repos
./setup shell-env --apply       # Shell environment (bootstrap-env.sh)
./setup dotfiles --apply        # Symlink config files
./setup theme --apply           # Accent colors, icon theme, SDDM
./setup apps --apply            # User applications
./setup audit                   # Package audit (always read-only)
```

All commands preview changes by default. Pass `--apply` to execute.

---

## Profile system

Machine-specific settings are defined in `profiles/`. Copy the sample to get started:

```bash
cp profiles/local.conf.sample profiles/local.conf
# Edit profiles/local.conf
```

`local.conf` overrides `default.conf`. Example:

```ini
[system]
hostname = workstation

[theme]
accent = orange
```

---

## Accent color

Three presets: **green**, **orange**, **blue**. Adding a new preset is as simple as creating a file in `colors/`:

```bash
# List available presets
./setup theme --list

# Change accent color
# Edit profiles/local.conf → accent = orange
./setup theme --apply

# Check for color drift
./setup theme --audit
```

The accent color propagates to: sway borders, waybar, kitty, tmux, dunst, swaylock, SDDM, bash prompt, fish shell, and the Tela icon theme.

---

## Module flags

```bash
./setup packages --rocm         # Include ROCm stack for AMD GPU compute
./setup packages --sway-spin    # Force Sway Spin mode (skip pre-installed packages)
./setup apps --devops            # Include DevOps tooling (Terraform, Ansible, Helm, kubectl)
./setup theme --corners          # Use sddm-theme-corners instead of stock SDDM theme
./setup theme --accent blue      # Override accent color for this run
```

---

## Utilities

```bash
./setup status                  # Show current system state
./setup diff                    # Show differences between repo and deployed state
./setup audit                   # Package manifest audit
```

---

## Sway Spin variant

The system auto-detects whether Sway is pre-installed (Sway Spin) and skips redundant packages. The detected mode is persisted to `~/.config/shell/.bootstrap-mode` so re-runs are consistent.

Override with `./setup packages --sway-spin` or `./setup packages --kde-spin`.

---

## Kanshi display profiles

Kanshi matches connected outputs against named profiles. To add a profile for a new machine:

```bash
swaymsg -t get_outputs
# Then edit config/kanshi/config
```

---

## Testing

```bash
bash tests/smoke.sh    # Runs container-based smoke tests via Podman
```

---

## Claude Code

Install via the official native installer:

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

---

## GPU control tools

**LACT** ([GitHub Releases](https://github.com/ilya-zlobintsev/LACT/releases)) is the recommended GPU control tool for RDNA2+.
