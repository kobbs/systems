# Sway — practical cheatsheet

Day-to-day reference for Sway on Wayland. Config lives in `config/sway/config`.

## Display management

```bash
# List connected outputs (connector names, modes, current config)
swaymsg -t get_outputs

# Change resolution and refresh rate on the fly
swaymsg output DP-3 mode 2560x1440@165Hz

# Change scale (1 = native, 2 = HiDPI)
swaymsg output DP-3 scale 1.5

# Reposition an output
swaymsg output DP-3 position 0 0

# Disable / enable an output
swaymsg output DP-3 disable
swaymsg output DP-3 enable

# GUI display configurator
wdisplays
```

### Kanshi (persistent profiles)

Kanshi auto-switches output profiles when monitors change. Config: `config/kanshi/config`.

```bash
# Current profile (desktop): DP-3 @ 2560x1440@165Hz
# Add new profiles in config/kanshi/config, then:
swaymsg reload   # or restart kanshi

# Debug profile matching
kanshi --debug
```

## Keyboard layout

The config sets French AZERTY globally: `input * { xkb_layout fr }`.

```bash
# List all input devices
swaymsg -t get_inputs

# Check current layout for a device
swaymsg -t get_inputs | jq '.[] | select(.type=="keyboard") | {name, xkb_active_layout_name}'

# Change layout on the fly (does not persist — edit sway config for that)
swaymsg input type:keyboard xkb_layout us
swaymsg input type:keyboard xkb_layout fr

# Toggle between two layouts
swaymsg input type:keyboard xkb_layout "fr,us"
swaymsg input type:keyboard xkb_switch_layout next
```

## Window & workspace keybindings

`$mod` = Super, `$mod2` = Alt. Workspace 1-10 keys are AZERTY top row.

### Essentials

| Action | Keybinding |
|---|---|
| Terminal (kitty) | `$mod+Return` |
| Launcher (bemenu) | `$mod+d` |
| Kill focused window | `$mod+Shift+A` |
| Fullscreen toggle | `$mod+f` |
| Float toggle | `$mod+Shift+Space` |
| Focus float/tiled | `$mod+Space` |
| Focus parent | `$mod+a` |
| Focus child | `$mod+q` |
| Sticky toggle | `$mod+Shift+s` |

### Focus & move

| Action | Keys (vim) | Keys (arrows) |
|---|---|---|
| Focus left | `$mod+j` | `$mod+Left` |
| Focus down | `$mod+k` | `$mod+Down` |
| Focus up | `$mod+l` | `$mod+Up` |
| Focus right | `$mod+m` | `$mod+Right` |
| Move left | `$mod+Shift+j` | `$mod+Shift+Left` |
| Move down | `$mod+Shift+k` | `$mod+Shift+Down` |
| Move up | `$mod+Shift+l` | `$mod+Shift+Up` |
| Move right | `$mod+Shift+M` | `$mod+Shift+Right` |

### Layout

| Action | Keybinding |
|---|---|
| Stacking | `$mod+s` |
| Tabbed | `$mod+z` |
| Toggle split | `$mod+e` |
| Split horizontal | `$mod+h` |
| Split vertical | `$mod+v` |
| Layout toggle | `$mod+x` |

### Workspaces (AZERTY)

1-10 use the AZERTY top row: `& é " ' ( - è _ ç à`

| Workspace | Switch | Move window to |
|---|---|---|
| 1 | `$mod+&` | `$mod+Shift+&` |
| 2 | `$mod+é` | `$mod+Shift+é` |
| 3 | `$mod+"` | `$mod+Shift+"` |
| 4 | `$mod+'` | `$mod+Shift+'` |
| 5 | `$mod+(` | `$mod+Shift+(` |
| 6 | `$mod+-` | `$mod+Shift+-` |
| 7 | `$mod+è` | `$mod+Shift+è` |
| 8 | `$mod+_` | `$mod+Shift+_` |
| 9 | `$mod+ç` | `$mod+Shift+ç` |
| 10 | `$mod+à` | `$mod+Shift+à` |
| 11-20 | `$mod+Alt+1`..`0` | `$mod+Alt+Shift+1`..`0` |

Navigate adjacent workspaces: `Ctrl+$mod+Left` / `Ctrl+$mod+Right`

### Resize mode

Enter with `$mod+r`, exit with `Return` or `Escape`.

| Action | Key |
|---|---|
| Shrink width | `Left` |
| Grow height | `Up` |
| Shrink height | `Down` |
| Grow width | `Right` |

## Screenshots

```bash
# Full screen to file
grim ~/screenshot.png

# Specific output
grim -o DP-3 ~/screenshot.png

# Select region to file
grim -g "$(slurp)" ~/screenshot.png

# Region to clipboard
grim -g "$(slurp)" - | wl-copy

# Full screen to clipboard
grim - | wl-copy
```

## Clipboard

```bash
# Copy text
echo "hello" | wl-copy

# Copy file contents
wl-copy < file.txt

# Copy an image
wl-copy -t image/png < image.png

# Paste
wl-paste

# Paste to file
wl-paste > output.txt

# List clipboard MIME types
wl-paste --list-types

# Clear clipboard
wl-copy --clear
```

## Notifications (dunst)

```bash
# Close top notification
dunstctl close

# Close all notifications
dunstctl close-all

# Show last notification from history
dunstctl history-pop

# Toggle do-not-disturb
dunstctl set-paused toggle

# Check if paused
dunstctl is-paused
```

## Session

```bash
# Reload sway config
swaymsg reload            # or: $mod+Shift+c

# Restart sway in-place
swaymsg restart           # or: $mod+Shift+r

# Exit sway (prompts via swaynag)
# $mod+Shift+e

# Exit sway immediately (no prompt)
swaymsg exit

# Lock screen (if swaylock is installed)
swaylock -c 000000
```

## Useful swaymsg queries

```bash
# Full window tree (find app_id, window titles, geometry)
swaymsg -t get_tree

# Connected outputs
swaymsg -t get_outputs

# Input devices (keyboards, mice, touchpads)
swaymsg -t get_inputs

# Active workspaces
swaymsg -t get_workspaces

# Current binding modes
swaymsg -t get_binding_modes

# Sway version
swaymsg -t get_version

# Pretty-print with jq
swaymsg -t get_tree | jq '.'
swaymsg -t get_workspaces | jq '.[] | {name, focused, output}'
```

## Troubleshooting

```bash
# Confirm you're running Wayland
echo $XDG_SESSION_TYPE       # should print "wayland"
echo $WAYLAND_DISPLAY        # should print "wayland-1" or similar

# Check sway is running
pgrep -x sway

# Sway log (systemd journal)
journalctl --user -u sway -b

# Key env vars for theming (set by bootstrap-env.sh)
echo $QT_QPA_PLATFORMTHEME   # should be "kde"
echo $QT_STYLE_OVERRIDE      # should be "Breeze"
echo $XDG_CURRENT_DESKTOP    # should be "sway"

# Verify GTK dark theme
gsettings get org.gnome.desktop.interface color-scheme

# Test if a key name is correct (press key, see event)
wev

# Monitor sway IPC events in real time
swaymsg -t subscribe '["window", "workspace"]' -m
```
