#!/bin/bash
set -euo pipefail

# Check if proton0 exists and has an IP assigned
if timeout 2 ip -4 a show dev proton0 2>/dev/null | grep -q 'inet '; then
    echo " VPN"
else
    echo " No VPN"
fi
