#!/usr/bin/env bash
# Install the WARP DNS fallback watchdog (script + systemd service + timer).
# Run with sudo/root:  sudo ./install.sh
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root:  sudo $0" >&2
  exit 1
fi

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Safety: WARP must be able to rewrite resolv.conf, so it must NOT be immutable.
chattr -i /etc/resolv.conf 2>/dev/null || true

install -m 0755 "$SRC_DIR/warp-dns-fallback.sh"      /usr/local/sbin/warp-dns-fallback.sh
install -m 0644 "$SRC_DIR/warp-dns-fallback.service" /etc/systemd/system/warp-dns-fallback.service
install -m 0644 "$SRC_DIR/warp-dns-fallback.timer"   /etc/systemd/system/warp-dns-fallback.timer

systemctl daemon-reload
systemctl enable --now warp-dns-fallback.timer

echo "Installed. Timer status:"
systemctl status warp-dns-fallback.timer --no-pager | grep -E "Active|Trigger" || true
echo "Follow logs with:  journalctl -t warp-dns-fallback -f"
