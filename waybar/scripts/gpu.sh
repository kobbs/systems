#!/bin/bash
HWMON=$(ls /sys/class/drm/card*/device/hwmon/hwmon*/temp1_input 2>/dev/null | head -1)
BUSY=$(ls /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null | head -1)

if [ -z "$HWMON" ]; then
  echo "GPU N/A"
  exit 0
fi

TEMP=$(( $(cat "$HWMON") / 1000 ))
LOAD=$(cat "$BUSY" 2>/dev/null || echo "?")
echo " ${TEMP}°C ${LOAD}%"
