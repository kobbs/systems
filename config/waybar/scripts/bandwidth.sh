#!/bin/bash
set -euo pipefail

# Use XDG_RUNTIME_DIR (user-private, chmod 700, managed by systemd-logind).
# /tmp is world-writable and a fixed path there is a symlink-attack target.
STATE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/waybar_bw_prev"

IF=$(ip route | awk '/default/ {print $5; exit}')

if [ -z "$IF" ]; then
  echo " No net"
  exit 0
fi

RX_FILE="/sys/class/net/${IF}/statistics/rx_bytes"
TX_FILE="/sys/class/net/${IF}/statistics/tx_bytes"

if [[ ! -r "$RX_FILE" || ! -r "$TX_FILE" ]]; then
  echo " --"
  exit 0
fi

RX=$(< "$RX_FILE")
TX=$(< "$TX_FILE")
NOW=$(date +%s%N)   # nanoseconds for accurate elapsed time

if [ -f "$STATE" ]; then
  read -r PREV_RX PREV_TX PREV_TIME < "$STATE"
  ELAPSED=$(( (NOW - PREV_TIME) / 1000000000 ))   # ns → s
  [ "$ELAPSED" -lt 1 ] && ELAPSED=1               # guard against sub-second calls
  RX_RATE=$(( (RX - PREV_RX) / ELAPSED ))
  TX_RATE=$(( (TX - PREV_TX) / ELAPSED ))
else
  RX_RATE=0; TX_RATE=0
fi

echo "$RX $TX $NOW" > "$STATE"

KB=1024
MB=$(( 1024 * KB ))
GB=$(( 1024 * MB ))

# Pure-bash integer arithmetic for KB/s and MB/s (common cases).
# bc is only used for GB/s (rare), and only when available.
fmt() {
  local b=$1
  if (( b >= GB )); then
    if command -v bc &>/dev/null; then
      printf "%.1fGB/s" "$(echo "scale=1; $b/$GB" | bc)"
    else
      printf "%d.%dGB/s" "$(( b / GB ))" "$(( (b % GB) * 10 / GB ))"
    fi
  elif (( b >= MB )); then
    printf "%d.%dMB/s" "$(( b / MB ))" "$(( (b % MB) * 10 / MB ))"
  else
    printf "%dKB/s" "$(( b / KB ))"
  fi
}

echo " $(fmt "$RX_RATE")  $(fmt "$TX_RATE")"
