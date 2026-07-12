# CLAUDE.md — warp-fallback

Guidance for Claude Code working in this repository.

## What this is

A DNS fallback watchdog for Cloudflare WARP on Linux. A systemd timer runs
`warp-dns-fallback.sh` every 20s. It probes via the **real system resolver**
(`getent`, not `dig`) and handles two failure modes:

1. `warp-svc` down → stubs `127.0.2.2`/`127.0.2.3` dead.
2. WARP "Connected/Healthy" but its DNS proxy drops normal `getaddrinfo()`
   queries (dig works, `ping`/`curl` fail). A dig probe misses this.

On failure it first bounces WARP (`warp-cli disconnect/connect`, 5-min cooldown)
to reset the proxy, then falls back to appending `1.1.1.1`/`8.8.8.8` if that
doesn't recover DNS. Removes the fallback once WARP is genuinely back up.

## Files

| File | Role | Installed to |
|------|------|--------------|
| `warp-dns-fallback.sh`      | probe + edit resolv.conf | `/usr/local/sbin/` |
| `warp-dns-fallback.service` | oneshot unit             | `/etc/systemd/system/` |
| `warp-dns-fallback.timer`   | 20s cadence              | `/etc/systemd/system/` |
| `install.sh` / `uninstall.sh` | deploy / remove        | — |

## Hard rules

- **Never `chattr +i /etc/resolv.conf`.** WARP must rewrite that file on every
  connect; locking it makes `warp-svc` refuse to connect
  ("Delaying connection initiation while system DNS settings restoration
  completes"). The whole point of this project is to cooperate with WARP, not
  lock the file.
- The script must only touch its own marked block (`# warp-dns-fallback …`) and
  never clobber WARP's own lines.
- Detection MUST use the system resolver (`getent`), never `dig` — `dig` keeps
  succeeding during the proxy-stuck failure mode and would hide the outage.
- `warp-cli` runs as root from the timer, so it needs `--accept-tos` (a bare
  root `warp-cli connect` prompts for the TOS and fails).
- Keep it dependency-light: bash + coreutils/util-linux + `warp-cli` + systemd.

## Conventions

- 2-space indent in shell; small pure helper functions.
- Never commit secrets (`.gitignore` blocks `*.credentials.json` / `.env`).
