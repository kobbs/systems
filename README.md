# systems

Fedora workstation bootstrap and dotfiles.

**Targets:** AMD GPU desktop, work laptop, personal laptop
**Stack:** Fedora 41+, Sway/Wayland, Waybar, Kanshi

---

## Phase 1 — Bootstrap (`fedora-bootstrap.sh`)

Installs and configures everything at the system level. Run once per machine as a regular user (not root).

```bash
bash fedora-bootstrap.sh
```

**What it does:**

- System update + RPM Fusion (free/nonfree) + multimedia codecs
- Flathub remote
- Sway/Wayland stack: sway, waybar, kanshi, swaylock, swayidle, mako, kitty, bemenu, grim, slurp, wl-clipboard, mate-polkit, pavucontrol, network-manager-applet, bluez, libnotify
- DevOps tooling: ansible, terraform, kubectl, helm, podman, kind, jq, yq
- Security: pam-u2f, yubikey-manager
- CLI utilities: git, curl, ripgrep, fzf, tmux, btop, fd-find, and more
- Shell env: `~/.config/shell/bootstrap-env.sh` sourced from `.bashrc` (sets `alias docker=podman`, `KIND_EXPERIMENTAL_PROVIDER=podman`)
- Keyboard layout: FR (system-wide)
- GPU groups: adds user to `video` and `render` if a discrete AMD GPU (RDNA2+) is detected

**After running, reboot** to apply group changes and keyboard layout.

**Not handled by Phase 1:**

- Dotfile deployment (Phase 2)
- Yubikey PAM integration — register key first: `pamu2fcfg > ~/.config/Yubico/u2f_keys`
- ROCm/AI workloads (home desktop only — dedicated process)

---

## Phase 2 — Dotfiles (`dotfiles-deploy.sh`)

Symlinks all configs from the repo into `~/.config/`. Safe to re-run — existing symlinks are updated, existing files are backed up with a `.bak` suffix.

```bash
bash dotfiles-deploy.sh
```

Then reload sway with `Super+Shift+C`, or restart it.

---

## Phase 3 — Application Stack (`apps-install.sh`)

Installs user-facing applications after Phase 1 and Phase 2. Run as a regular user.

```bash
bash apps-install.sh
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
| KeePassXC | RPM | Browser native messaging works RPM→RPM (Brave, Firefox) |
| virt-manager / KVM | RPM group | `Virtualization` group + libvirt service + libvirt group membership |
| Podman | — | Already installed in Phase 1; script confirms |

**After running:** log out and back in for `libvirt` group membership to take effect.

---

## Dotfiles overview

| Path | Purpose |
|---|---|
| `sway/config` | Sway compositor config — keybinds, layout, autostart, themes |
| `waybar/config` | Waybar modules and layout |
| `waybar/style.css` | Waybar stylesheet |
| `waybar/scripts/` | Custom waybar scripts (bandwidth, VPN status) |
| `kanshi/config` | Per-machine display profiles (matched by output name) |

### Kanshi display profiles

Kanshi matches connected outputs against named profiles. When no profile matches (e.g. on a KVM VM), it exits cleanly and Sway's `output * { scale 1 }` fallback takes over.

To add a profile for a new machine:

```bash
swaymsg -t get_outputs   # or: kanshi --debug
```

Then add a profile block to `kanshi/config`.

### Claude Code

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

### GPU control tools

`corectrl` is commented out in `sway/config`. It entered maintenance mode in May 2025 and has limited RDNA2+ support. Recommended modern alternative: **LACT** (`ilyaz/LACT` COPR). Install manually if needed.
