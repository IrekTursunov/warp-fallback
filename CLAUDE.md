# CLAUDE.md — warp-fallback

Guidance for Claude Code working in this repository.

## What this is

A DNS fallback watchdog for Cloudflare WARP on Linux. When `warp-svc` dies, its
local DNS stubs (`127.0.2.2`/`127.0.2.3`) go dead and DNS breaks. A systemd timer
runs `warp-dns-fallback.sh` every 20s; if WARP's stub doesn't answer, it appends
public resolvers (`1.1.1.1`/`8.8.8.8`) to `/etc/resolv.conf`, and removes them
once WARP recovers.

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
- Keep it dependency-light: POSIX-ish bash + `dig` + systemd only.

## Conventions

- 2-space indent in shell; small pure helper functions.
- Never commit secrets (`.gitignore` blocks `*.credentials.json` / `.env`).
