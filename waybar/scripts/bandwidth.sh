#!/bin/bash
STATE=/tmp/waybar_bw_prev
IF=$(ip route | awk '/default/ {print $5; exit}')

if [ -z "$IF" ]; then
  echo " No net"
  exit 0
fi

RX=$(cat /sys/class/net/$IF/statistics/rx_bytes)
TX=$(cat /sys/class/net/$IF/statistics/tx_bytes)
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

fmt() {
  local b=$1
  if   (( b >= 1073741824 )); then printf "%.1fGB/s" "$(echo "scale=1; $b/1073741824" | bc)"
  elif (( b >= 1048576    )); then printf "%.1fMB/s" "$(echo "scale=1; $b/1048576"    | bc)"
  else printf "%dKB/s" "$(( b / 1024 ))"
  fi
}

echo " $(fmt $RX_RATE)  $(fmt $TX_RATE)"
