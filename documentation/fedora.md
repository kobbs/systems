# Fedora / DNF — practical cheatsheet

Quick reference for Fedora package management, system config, and service management.

## Package management (dnf5)

Fedora 41+ ships dnf5. All commands below use dnf5 syntax.

> Read-only commands (`search`, `info`, `list`, `repolist`) work without `sudo` on a
> default Fedora install. If a third-party repo file has restrictive permissions you'll
> get "Permission denied" — either fix the file permissions
> (`sudo chmod 644 /etc/yum.repos.d/<file>.repo`) or run the command with `sudo`.

```bash
dnf search <keyword>                # search packages by name/summary
dnf info <package>                  # show package details (version, repo, description)
sudo dnf install <package>          # install a package
sudo dnf install -y <package>       # install without confirmation
sudo dnf remove <package>           # remove a package (keeps dependencies)
sudo dnf autoremove                 # remove unused dependencies
```

### Listing packages

```bash
dnf list --installed                # all installed packages
dnf list --installed 'mesa*'        # filter installed by glob
dnf list --upgrades                 # packages with updates available (shows versions)
dnf repoquery <package> --info      # detailed info from repo (including all available versions)
```

### History and rollback

```bash
dnf history list                    # show transaction history
dnf history info <id>               # details of a specific transaction
sudo dnf history undo <id>          # undo a transaction
sudo dnf downgrade <package>        # downgrade to previous version
```

### Package swap

Replace one package with another (resolves conflicts automatically):

```bash
sudo dnf swap ffmpeg-free ffmpeg --allowerasing -y
sudo dnf swap mesa-va-drivers mesa-va-drivers-freeworld --allowerasing -y
```

## System updates

```bash
sudo dnf upgrade                    # upgrade all packages (interactive)
sudo dnf upgrade -y                 # upgrade all, no confirmation
sudo dnf upgrade --refresh          # force metadata refresh before upgrading
dnf check-update                    # preview what will update (exit code 100 = updates available)
```

### Excluding packages

```bash
sudo dnf upgrade --exclude=kernel*                # skip kernel for this run
sudo dnf upgrade --exclude=mesa* --exclude=rocm*  # multiple excludes
```

Persistent excludes go in `/etc/dnf/dnf.conf`:

```ini
[main]
excludepkgs=kernel*
```

## Repository management

```bash
dnf repolist                        # list enabled repos
dnf repolist --all                  # list all repos (enabled + disabled)
dnf repoinfo <repo-id>             # show repo details
```

### Enable / disable repos

```bash
sudo dnf config-manager setopt <repo-id>.enabled=1    # enable
sudo dnf config-manager setopt <repo-id>.enabled=0    # disable
```

### Add third-party repos

From a `.repo` file URL (pattern used in bootstrap.sh):

```bash
sudo dnf config-manager addrepo --from-repofile=https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
```

From an RPM (e.g. RPM Fusion):

```bash
FEDORA_VERSION=$(rpm -E %fedora)
sudo dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm"
```

Manual repo file (e.g. Kubernetes):

```bash
cat <<'EOF' | sudo tee /etc/yum.repos.d/kubernetes.repo > /dev/null
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.34/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.34/rpm/repodata/repomd.xml.key
EOF
```

## GRUB & kernel parameters

### View current kernel args

```bash
cat /proc/cmdline                              # running kernel's boot args
sudo grubby --info=ALL                         # all installed kernels + their args
sudo grubby --info=DEFAULT                     # default kernel details
```

### Add/remove kernel parameters with grubby (preferred on Fedora)

`grubby` modifies per-kernel BLS entries directly — no `grub2-mkconfig` needed.

```bash
# Add a parameter to all kernels
sudo grubby --update-kernel=ALL --args="amdgpu.ppfeaturemask=0xffffffff"

# Add to default kernel only
sudo grubby --update-kernel=DEFAULT --args="iommu=pt"

# Remove a parameter from all kernels
sudo grubby --update-kernel=ALL --remove-args="quiet"
```

Common parameters:

| Parameter | Purpose |
|---|---|
| `amdgpu.ppfeaturemask=0xffffffff` | Unlock AMD GPU power management controls |
| `iommu=pt` | IOMMU passthrough (better GPU/VFIO performance) |
| `quiet` | Suppress boot messages (remove for debug) |
| `rd.driver.blacklist=nouveau` | Blacklist nouveau (for AMD-only systems) |

### Manual GRUB config (fallback)

Edit `/etc/default/grub`, then regenerate:

```bash
sudo vim /etc/default/grub                     # edit GRUB_CMDLINE_LINUX
sudo grub2-mkconfig -o /boot/grub2/grub.cfg    # regenerate (BIOS)
sudo grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg  # regenerate (UEFI)
```

### Set default kernel

```bash
sudo grubby --set-default /boot/vmlinuz-<version>   # set a specific kernel as default
sudo grubby --default-kernel                          # show current default
```

## Flatpak

```bash
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo  # user-only
```

### Install / update / remove

```bash
flatpak install flathub <app-id>               # install (system-wide)
flatpak install --user flathub <app-id>         # install (user)
flatpak install --user -y flathub <app-id>      # install, no confirmation
flatpak update                                  # update all flatpaks
flatpak uninstall <app-id>                      # remove
flatpak uninstall --unused                      # remove unused runtimes
```

### List and run

```bash
flatpak list                                    # all installed flatpaks
flatpak list --app                              # apps only (no runtimes)
flatpak remotes                                 # list configured remotes
flatpak run <app-id>                            # run an app
flatpak info <app-id>                           # show app details
```

Common app IDs used in this repo:

| App | Flatpak ID |
|---|---|
| EasyEffects | `com.github.wwmm.easyeffects` |
| Slack | `com.slack.Slack` |
| Signal | `org.signal.Signal` |

## RPM queries

```bash
rpm -qa                             # list all installed packages
rpm -qa | grep <pattern>            # search installed packages
rpm -q <package>                    # check if a package is installed (exit code 0 = yes)
rpm -qi <package>                   # info about an installed package
rpm -ql <package>                   # list files owned by a package
rpm -qf /path/to/file              # which package owns this file
rpm -qR <package>                   # list dependencies of an installed package
rpm -q --changelog <package>        # show package changelog
rpm -E %fedora                      # expand RPM macro (e.g. Fedora version number)
```

## systemd essentials

### Service management

```bash
sudo systemctl start <service>      # start now
sudo systemctl stop <service>       # stop now
sudo systemctl restart <service>    # restart
sudo systemctl enable <service>     # start on boot
sudo systemctl enable --now <service>  # enable + start immediately
sudo systemctl disable <service>    # don't start on boot
systemctl status <service>          # show status (no sudo needed)
systemctl is-enabled <service>      # check if enabled
systemctl is-active <service>       # check if running
```

### Listing services

```bash
systemctl list-units --type=service              # running services
systemctl list-units --type=service --state=failed  # failed services
systemctl list-unit-files --type=service         # all service files + state
```

### Journal logs

```bash
journalctl -u <service>                          # logs for a service
journalctl -u <service> -f                       # follow (tail) logs
journalctl -u <service> --since "1 hour ago"     # time-filtered
journalctl -b                                    # all logs from current boot
journalctl -b -1                                 # logs from previous boot
journalctl -p err                                # only errors and above
journalctl --disk-usage                           # how much space journals use
sudo journalctl --vacuum-size=500M               # trim journals to 500 MB
```

## WiFi (nmcli)

`NetworkManager` is a default Fedora package. The tray GUI (`network-manager-applet`) is installed by bootstrap.sh.

```bash
nmcli device wifi list                          # scan for networks
nmcli device wifi connect <SSID> password <pw>  # connect to a network
nmcli connection show                           # list saved connections
nmcli connection show <name>                    # details of a connection
nmcli connection up <name>                      # activate a saved connection
nmcli connection down <name>                    # disconnect
nmcli connection delete <name>                  # forget a saved network
nmcli device status                             # show device states
nmcli radio wifi off                            # disable WiFi radio
nmcli radio wifi on                             # enable WiFi radio
```

## Bluetooth (bluetoothctl)

`bluez` (provides `bluetoothctl`) is installed via `SWAY_COMMON_PKGS` in bootstrap.sh. Enable the service first:

```bash
sudo systemctl enable --now bluetooth
```

```bash
bluetoothctl power on                           # turn adapter on
bluetoothctl power off                          # turn adapter off
bluetoothctl scan on                            # discover nearby devices
bluetoothctl devices                            # list discovered devices
bluetoothctl pair <MAC>                         # pair with a device
bluetoothctl trust <MAC>                        # trust (auto-connect on boot)
bluetoothctl connect <MAC>                      # connect to a paired device
bluetoothctl disconnect <MAC>                   # disconnect
bluetoothctl remove <MAC>                       # unpair and forget a device
bluetoothctl info <MAC>                         # show device details
```
