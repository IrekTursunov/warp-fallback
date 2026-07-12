#!/usr/bin/env bash
# Remove the WARP DNS fallback watchdog.  Run with sudo/root:  sudo ./uninstall.sh
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root:  sudo $0" >&2
  exit 1
fi

systemctl disable --now warp-dns-fallback.timer 2>/dev/null || true
rm -f /etc/systemd/system/warp-dns-fallback.timer
rm -f /etc/systemd/system/warp-dns-fallback.service
rm -f /usr/local/sbin/warp-dns-fallback.sh
systemctl daemon-reload

# Drop any fallback block the watchdog may have left behind.
sed -i '\#^# warp-dns-fallback#,$d' /etc/resolv.conf 2>/dev/null || true

echo "Uninstalled."
