#!/usr/bin/env bash
# warp-dns-fallback: keep DNS working when Cloudflare WARP's DNS misbehaves.
#
# Two failure modes are handled:
#   1. warp-svc down / stub unreachable  -> system resolver gets no answer.
#   2. WARP connected but its DNS proxy silently drops normal system-resolver
#      queries (glibc getaddrinfo times out even though `dig` still works).
#
# Detection therefore uses the REAL system resolver path (getent), not `dig` --
# a dig-based probe keeps succeeding during mode 2 and would miss the outage.
#
# On failure the watchdog first tries to heal WARP itself (disconnect/connect,
# which resets the proxy and fixes mode 2), rate-limited by a cooldown. If DNS
# still fails, it appends public resolvers (1.1.1.1/8.8.8.8) to resolv.conf as a
# last-resort fallback, and removes them again once WARP DNS recovers.
#
# It never makes resolv.conf immutable -- WARP must be able to rewrite it.
set -u

RESOLV=/etc/resolv.conf
MARK='# warp-dns-fallback'
FALLBACK1=1.1.1.1
FALLBACK2=8.8.8.8
PROBE_HOST=cloudflare.com          # any stable name; resolved via the OS resolver
COOLDOWN=300                        # min seconds between WARP auto-bounces
STATE_DIR=/run/warp-dns-fallback
LAST_BOUNCE="$STATE_DIR/last-bounce"

# Real system-resolver probe: this is exactly what ping/curl/apps use.
resolver_ok() {
  timeout 5 getent ahostsv4 "$PROBE_HOST" >/dev/null 2>&1
}

warp_should_be_up() {
  systemctl is-active --quiet warp-svc && \
    warp-cli --accept-tos status 2>/dev/null | grep -q "Connected"
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

# Reset WARP's DNS proxy, respecting a cooldown so we never bounce in a loop.
try_bounce_warp() {
  warp_should_be_up || return 1
  mkdir -p "$STATE_DIR"
  local now last
  now=$(date +%s)
  last=$(cat "$LAST_BOUNCE" 2>/dev/null || echo 0)
  if (( now - last < COOLDOWN )); then
    return 1
  fi
  echo "$now" > "$LAST_BOUNCE"
  logger -t warp-dns-fallback "System DNS failing while WARP connected: bouncing WARP to reset its DNS proxy"
  warp-cli --accept-tos disconnect >/dev/null 2>&1
  sleep 2
  warp-cli --accept-tos connect >/dev/null 2>&1
  # give WARP a few seconds to re-establish before re-probing
  for _ in 1 2 3 4 5 6; do
    sleep 2
    resolver_ok && return 0
  done
  return 1
}

if resolver_ok; then
  # Only clear the fallback once WARP itself is back up -- otherwise resolver_ok
  # may be true *because of* our fallback, and removing it would break DNS again.
  if has_block && warp_should_be_up; then
    remove_block
  fi
  exit 0
fi

# System DNS is failing. First try to heal WARP (fixes the proxy-stuck case).
if try_bounce_warp && resolver_ok; then
  has_block && remove_block          # WARP healed; drop any stale fallback
  exit 0
fi

# Still broken (WARP down, or bounce on cooldown/ineffective): use public DNS.
has_block || add_block
exit 0
