#!/usr/bin/env bash
# warp-dns-fallback: temporarily add public DNS to /etc/resolv.conf ONLY while
# Cloudflare WARP's local DNS stub is unreachable (e.g. warp-svc crashed).
#
# WARP owns /etc/resolv.conf and rewrites it on connect. This watchdog never
# locks the file (no chattr) — it only appends a clearly-marked fallback block
# when WARP DNS is down, and removes that block once WARP DNS recovers. WARP
# rewriting the file on reconnect also naturally clears the block. Self-healing.
set -u

RESOLV=/etc/resolv.conf
MARK='# warp-dns-fallback'
STUB=127.0.2.2
FALLBACK1=1.1.1.1
FALLBACK2=8.8.8.8

# Healthy = WARP's stub answers an A query within the timeout.
probe_ok() {
  dig +time=2 +tries=1 +short @"$STUB" cloudflare.com 2>/dev/null \
    | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'
}

has_block() { grep -qF "$MARK" "$RESOLV" 2>/dev/null; }

add_block() {
  {
    echo "$MARK (added $(date -Is); WARP DNS unreachable)"
    echo "nameserver $FALLBACK1"
    echo "nameserver $FALLBACK2"
  } >> "$RESOLV"
  logger -t warp-dns-fallback "WARP DNS down: appended $FALLBACK1/$FALLBACK2 fallback to $RESOLV"
}

# Delete from the marker line to end of file, preserving WARP's own content.
remove_block() {
  sed -i "\#^${MARK}#,\$d" "$RESOLV"
  logger -t warp-dns-fallback "WARP DNS recovered: removed fallback block from $RESOLV"
}

if probe_ok; then
  has_block && remove_block
else
  has_block || add_block
fi

exit 0
