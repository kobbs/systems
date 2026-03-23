# systems

Fedora workstation bootstrap and dotfiles.

**Stack:** Fedora 43, Sway/Wayland, Waybar, Kanshi

## Repo structure

```
scripts/             Automation (run these)
  env-sample         Default variables (hostname, accent) — copy to env to override
  bootstrap.sh       System packages, repos, env vars
  dotfiles.sh        Symlink configs into ~/.config/
  apps.sh            User-facing applications
  lib/common.sh      Shared helpers (logging, preflight, accent colors)

config/              Dotfiles (source of truth, deployed by scripts/dotfiles.sh)
  sway/              Sway compositor
  waybar/            Waybar modules, styles, and scripts
  kanshi/            Per-machine display profiles
  kitty/             Kitty terminal
  tmux/              tmux
  dunst/             Dunst notification daemon
  swaylock/          Swaylock screen locker
  sddm/             SDDM greeter theme
  gtk/               GTK 3/4 dark theme (single file, symlinked to both)
  qt5ct/ qt6ct/      Qt theme settings
  kde/               KDE Frameworks color scheme (kdeglobals)
  bash/              Shell prompt

documentation/       Reference cheatsheets (Sway, Fedora/DNF, ROCm, Claude Code)
```

---

## Bootstrap (`scripts/bootstrap.sh`)

Installs and configures everything at the system level. Run once per machine as a regular user (not root).

```bash
bash scripts/bootstrap.sh start
```

### Sway Spin variant

If starting from **Fedora Sway Spin** instead of KDE Spin, pass the `--sway-spin` flag (or let the script auto-detect — it checks if `sway` is already installed):

```bash
bash scripts/bootstrap.sh start --sway-spin
bash scripts/bootstrap.sh start --kde-spin    # force KDE Spin mode
bash scripts/bootstrap.sh start               # auto-detect (persisted for re-runs)
```

The detected mode is saved to `~/.config/shell/.bootstrap-mode` so re-runs use the same mode even after sway is installed.

In Sway Spin mode the script skips packages the spin already ships (sway, waybar, kanshi, mako, grim, slurp, etc.) and drops the `unset SSH_ASKPASS` workaround (no ksshaskpass on the Sway Spin).

**What it does** (full variant):

- System update + RPM Fusion (free/nonfree) + multimedia codecs
- Flathub remote
- Sway/Wayland stack: sway, waybar, kanshi, swaylock, swayidle, mako, kitty, bemenu, grim, slurp, wl-clipboard, mate-polkit, pavucontrol, network-manager-applet, bluez, libnotify
- DevOps tooling: ansible, terraform, kubectl, helm, podman, kind, jq, yq
- Security: pam-u2f, yubikey-manager
- CLI utilities: git, curl, ripgrep, fzf, tmux, btop, bat, fd-find, vim, htop, wget
- Theming: plasma-integration, Qt5/Qt6 platform theme, Tela icon theme (accent-colored)
- Performance: tuned + tuned-ppd (power profile daemon)
- Firewall: firewalld enabled with default zone
- Shell env: `~/.config/shell/bootstrap-env.sh` sourced from `.bashrc`
- Keyboard layout: FR (system-wide)
- SDDM greeter: sddm-theme-corners (dark, Qt6)
- GPU groups: adds user to `video` and `render` if a discrete AMD GPU (RDNA2+) is detected

**After running, reboot** to apply group changes and keyboard layout.

**Not handled by bootstrap:**

- Dotfile deployment (`scripts/dotfiles.sh`)
- Yubikey PAM integration — register key first: `pamu2fcfg > ~/.config/Yubico/u2f_keys`
- ROCm/AI workloads (home desktop only — dedicated process)

---

## Dotfiles (`scripts/dotfiles.sh`)

Symlinks all configs from `config/` into `~/.config/`. Safe to re-run — existing symlinks are updated, existing files are backed up with a timestamped `.bak` suffix.

```bash
bash scripts/dotfiles.sh start
```

Then reload sway with `Super+Shift+C`, or restart it.

### Accent color

The accent color is controlled by the `ACCENT` variable. Copy the sample env and set your preference:

```bash
cp scripts/env-sample scripts/env
# Edit scripts/env → ACCENT="orange"   (presets: green, orange, blue)
bash scripts/dotfiles.sh start
```

This propagates the accent to sway borders, waybar, kitty, tmux, dunst, swaylock, SDDM, and the bash prompt. The `scripts/env` file is gitignored — your color choice stays local.

---

## Application Stack (`scripts/apps.sh`)

Installs user-facing applications. Run after bootstrap and dotfiles. Run as a regular user.

```bash
bash scripts/apps.sh start
```

**What it installs:**

| App | Method |
|---|---|
| Firefox | RPM |
| Brave | RPM (vendor repo) |
| EasyEffects | Flatpak |
| Slack | Flatpak |
| Signal | Flatpak |
| Nextcloud | RPM |
| ProtonVPN | RPM (vendor repo) |
| KeePassXC | RPM |
| Mesa / AMD acceleration | RPM (libva-utils, mesa-vdpau-drivers-freeworld, mesa-vulkan-drivers) |
| virt-manager / KVM | RPM (`@virtualization` group) |

Optional desktop utilities (mutually exclusive flags):
- `--gtk-apps` — Thunar, Evince, GNOME Calculator, Loupe, File Roller, Celluloid
- `--qt-apps` — Dolphin, Okular, KCalc, Gwenview, Ark, Haruna

**After running:** log out and back in for `libvirt` group membership to take effect.

---

## Kanshi display profiles

Kanshi matches connected outputs against named profiles. When no profile matches (e.g. on a KVM VM), it exits cleanly and Sway's `output * { scale 1 }` fallback takes over.

To add a profile for a new machine:

```bash
swaymsg -t get_outputs   # or: kanshi --debug
```

Then add a profile block to `config/kanshi/config`.

---

## Claude Code

Claude Code has no RPM or Flatpak package. Use the official native installer (no Node.js or npm required):

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

This installs a self-contained binary to `~/.claude/` and adds it to your PATH. Updates happen automatically in the background.

On first run, `claude` will open a browser window to authenticate with your Anthropic account.

---

## GPU control tools

**LACT** ([GitHub Releases](https://github.com/ilya-zlobintsev/LACT/releases)) is the recommended GPU control tool for RDNA2+. Install the RPM manually if needed.
