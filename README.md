# systems

Fedora workstation bootstrap and dotfiles.

**Targets:** AMD GPU desktop, work laptop, personal laptop
**Stack:** Fedora 41+, Sway/Wayland, Waybar, Kanshi

## Repo structure

```
scripts/             Automation (run these)
  bootstrap.sh       Phase 1 — system packages, repos, env vars
  deploy.sh          Phase 2 — symlink configs into ~/.config/
  apps.sh            Phase 3 — user-facing applications
  lib/common.sh      Shared helpers (logging, preflight checks)

config/              Dotfiles (source of truth, deployed by scripts/deploy.sh)
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

## Phase 1 — Bootstrap (`scripts/bootstrap.sh`)

Installs and configures everything at the system level. Run once per machine as a regular user (not root).

```bash
bash scripts/bootstrap.sh
```

### Sway Spin variant

If starting from **Fedora Sway Spin** instead of base Fedora, pass the `--sway-spin` flag (or let the script auto-detect — it checks if `sway` is already installed):

```bash
bash scripts/bootstrap.sh --sway-spin
bash scripts/bootstrap.sh --base       # force base Fedora mode
bash scripts/bootstrap.sh              # auto-detect (persisted for re-runs)
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
- SDDM greeter: solid dark background (#222222) matching Sway
- GPU groups: adds user to `video` and `render` if a discrete AMD GPU (RDNA2+) is detected

**After running, reboot** to apply group changes and keyboard layout.

**Not handled by Phase 1:**

- Dotfile deployment (Phase 2)
- Yubikey PAM integration — register key first: `pamu2fcfg > ~/.config/Yubico/u2f_keys`
- ROCm/AI workloads (home desktop only — dedicated process)

---

## Phase 2 — Dotfiles (`scripts/deploy.sh`)

Symlinks all configs from `config/` into `~/.config/`. Safe to re-run — existing symlinks are updated, existing files are backed up with a timestamped `.bak` suffix.

```bash
bash scripts/deploy.sh
```

Then reload sway with `Super+Shift+C`, or restart it.

---

## Phase 3 — Application Stack (`scripts/apps.sh`)

Installs user-facing applications after Phase 1 and Phase 2. Run as a regular user.

```bash
bash scripts/apps.sh
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
| Podman | — | Already installed in Phase 1; script confirms |

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

**LACT** (`ilyaz/LACT` COPR) is the recommended GPU control tool for RDNA2+. Install manually if needed.
