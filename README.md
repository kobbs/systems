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

## Phase 2 — Dotfiles (manual for now)

Symlink the configs into place. Replace `<repo>` with the path where this repo is cloned.

```bash
mkdir -p ~/.config/sway ~/.config/waybar ~/.config/kanshi

ln -s <repo>/sway/config       ~/.config/sway/config
ln -s <repo>/waybar/config     ~/.config/waybar/config
ln -s <repo>/waybar/style.css  ~/.config/waybar/style.css
ln -s <repo>/waybar/scripts    ~/.config/waybar/scripts
ln -s <repo>/kanshi/config     ~/.config/kanshi/config

chmod +x ~/.config/waybar/scripts/*.sh
```

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

### GPU control tools

`corectrl` is commented out in `sway/config`. It entered maintenance mode in May 2025 and has limited RDNA2+ support. Recommended modern alternative: **LACT** (`ilyaz/LACT` COPR). Install manually if needed.
