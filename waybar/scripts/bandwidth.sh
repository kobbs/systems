#!/bin/bash

IF=$(ip route | awk '/default/ {print $5; exit}')
if [ -z "$IF" ]; then
  echo " No net"
  exit 0
fi

RX_PREV=$(cat /sys/class/net/$IF/statistics/rx_bytes)
TX_PREV=$(cat /sys/class/net/$IF/statistics/tx_bytes)
sleep 1
RX=$(cat /sys/class/net/$IF/statistics/rx_bytes)
TX=$(cat /sys/class/net/$IF/statistics/tx_bytes)

echo " $(( (RX - RX_PREV) / 1024 ))KB/s  $(( (TX - TX_PREV) / 1024 ))KB/s"

