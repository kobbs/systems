#!/bin/bash
set -euo pipefail

# Use glob directly instead of parsing ls output (fragile and wrong for paths
# with spaces or special chars).
HWMON=""
for f in /sys/class/drm/card*/device/hwmon/hwmon*/temp1_input; do
  [[ -r "$f" ]] && HWMON="$f" && break
done

BUSY=""
for f in /sys/class/drm/card*/device/gpu_busy_percent; do
  [[ -r "$f" ]] && BUSY="$f" && break
done

if [[ -z "$HWMON" ]]; then
  echo " GPU N/A"
  exit 0
fi

TEMP=$(( $(< "$HWMON") / 1000 ))
LOAD="?"
[[ -n "$BUSY" ]] && LOAD=$(< "$BUSY")
echo " ${TEMP}°C ${LOAD}%"
