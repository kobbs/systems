# systems

Fedora workstation bootstrap and dotfiles.

**Targets:** AMD GPU desktop, work laptop, personal laptop
**Stack:** Fedora 41+, Sway/Wayland, Waybar, Kanshi

## Repo structure

```
scripts/             Automation (run these)
  env-sample         Default variables (hostname, accent) — copy to env to override
  bootstrap.sh       System packages, repos, env vars
  dotfiles.sh        Symlink configs into ~/.config/
  apps.sh            User-facing applications
  lib/common.sh      Shared helpers (logging, preflight, accent colors)

config/              Dotfiles (source of truth, deployed by scripts/dotfiles.sh)
  sway/              Sway compositor config
  waybar/            Waybar modules, styles, and scripts
  kanshi/            Per-machine display profiles
  gtk/               GTK 3/4 dark theme (single file, symlinked to both)
  qt5ct/             Qt5 theme settings
  qt6ct/             Qt6 theme settings
  kde/               KDE Frameworks color scheme (kdeglobals)
  bash/              Shell prompt
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
- CLI utilities: git, curl, ripgrep, fzf, tmux, btop, fd-find, and more
- Shell env: `~/.config/shell/bootstrap-env.sh` sourced from `.bashrc`
- Keyboard layout: FR (system-wide)
- SDDM greeter: sddm-theme-corners (dark, Qt5)
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

| App | Method | Reason |
|---|---|---|
| Firefox | RPM | Standard Fedora package; sets `MOZ_ENABLE_WAYLAND=1` in `/etc/environment` |
| Brave | RPM (vendor repo) | Vendor recommends RPM; Flatpak disables Chromium's internal sandbox |
| EasyEffects | Flatpak | RPM has PipeWire context failures on Fedora 41+ |
| Slack | Flatpak | Sandbox isolation for sensitive comms |
| Signal | Flatpak | No official Fedora RPM; Flathub is standard |
| Nextcloud | RPM | Integrates with system file manager and tray |
| ProtonVPN | RPM (vendor repo) | Flatpak has Wayland rendering failures; needs NetworkManager integration |
| KeePassXC | RPM | Browser native messaging works RPM-to-RPM (Brave, Firefox) |
| virt-manager / KVM | RPM group | `Virtualization` group + libvirt service + libvirt group membership |
| Podman | — | Already installed by bootstrap; script confirms |

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

**Migrating from the old npm-based install:** If you previously installed via npm, clean up the old setup:

```bash
# Remove the isolated npm environment
rm -rf ~/.local/share/claude-code

# Remove the PATH entry added to ~/.bashrc
# Edit ~/.bashrc and delete the line:
# export PATH="$HOME/.local/share/claude-code/node_modules/.bin:$PATH"

# nodejs/npm can be removed too if not needed for anything else
sudo dnf remove nodejs npm
```

---

## GPU control tools

**LACT** ([GitHub Releases](https://github.com/ilya-zlobintsev/LACT/releases)) is the recommended GPU control tool for RDNA2+. Install the RPM manually if needed.
