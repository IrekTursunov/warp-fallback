# warp-fallback

A tiny, dependency-light **DNS fallback watchdog for Cloudflare WARP** on Linux.

When Cloudflare WARP is connected it manages `/etc/resolv.conf` and points the
system at its own local DNS stubs (`127.0.2.2`, `127.0.2.3`). Two things can then
break DNS:

1. **`warp-svc` crashes / disconnects** — the stubs go dead and there is no
   fallback nameserver.
2. **WARP stays "Connected / Healthy" but its DNS proxy silently drops normal
   system-resolver queries.** `dig` still gets answers, but `getaddrinfo()` —
   what `ping`, `curl`, browsers and every normal app use — times out with
   *"Temporary failure in name resolution"*. (Even WARP's own NTP client fails.)
   A `dig`-based health check completely misses this; only the real resolver
   path reveals it.

This watchdog handles both. It probes via the **actual system resolver**
(`getent`). On failure it first tries to **heal WARP itself** (a rate-limited
`warp-cli disconnect/connect`, which resets the stuck proxy — the real fix for
mode 2). If DNS is still broken, it temporarily appends public resolvers
(`1.1.1.1`, `8.8.8.8`) to `resolv.conf`, and removes them again once WARP
recovers.

## Why not just `chattr +i` a fallback into resolv.conf?

Because it **breaks WARP.** WARP must rewrite `resolv.conf` every time it
connects. If the file is immutable, `warp-svc` logs:

```
Delaying connection initiation while system DNS settings restoration completes
```

…and refuses to connect (it reports `Disconnected / Manual`). So locking the
file is a trap. This watchdog never uses `chattr` — it cooperates with WARP
instead of fighting it.

## How it works

`warp-dns-fallback.sh` runs on a systemd timer (every 20s):

1. Probe with the **real system resolver**: `getent ahostsv4 cloudflare.com`
   (this is exactly the path `ping`/`curl`/apps use — not `dig`).
2. **Healthy** → if a fallback block is present *and* WARP is genuinely back up,
   remove it. (It won't remove the fallback while WARP is still down, since the
   probe might be succeeding only *because* of that fallback.)
3. **Failing** →
   1. If WARP is supposed to be connected, **bounce it**
      (`warp-cli disconnect && connect`) to reset the DNS proxy, rate-limited by
      a 5-minute cooldown so it never loops. Re-probe; if DNS recovers, done.
   2. Otherwise append a clearly-marked fallback block:

      ```
      # warp-dns-fallback (added <timestamp>; WARP DNS unreachable)
      nameserver 1.1.1.1
      nameserver 8.8.8.8
      ```

It is **self-healing**: when WARP (re)connects it rewrites `resolv.conf` itself,
which also clears the block. The watchdog only ever edits its own marked lines,
so it never clobbers WARP's content.

## Requirements

- Linux with `systemd`
- `getent` and `logger` (present on essentially every Linux — `libc` + `util-linux`)
- Cloudflare WARP (`warp-cli` / `warp-svc`) using the default local stub `127.0.2.2`

## Install

```bash
git clone https://github.com/<you>/warp-fallback.git
cd warp-fallback
sudo ./install.sh
```

Watch it work:

```bash
journalctl -t warp-dns-fallback -f
```

## Test it

```bash
sudo systemctl stop warp-svc          # simulate a WARP failure
sudo /usr/local/sbin/warp-dns-fallback.sh
cat /etc/resolv.conf                  # fallback block appears
getent hosts example.com              # DNS still resolves

sudo systemctl start warp-svc         # restore WARP
warp-cli connect
sudo /usr/local/sbin/warp-dns-fallback.sh
cat /etc/resolv.conf                  # fallback block gone
```

Diagnosing the "proxy stuck" mode (2) by hand — the tell is `dig` working while
the system resolver hangs:

```bash
dig +short @127.0.2.2 example.com     # answers instantly
getent hosts example.com              # ...hangs / times out
warp-cli disconnect && warp-cli connect   # resets the proxy; fixed
```

## Uninstall

```bash
sudo ./uninstall.sh
```

## Files

| File | Installed to |
|------|--------------|
| `warp-dns-fallback.sh`      | `/usr/local/sbin/warp-dns-fallback.sh` |
| `warp-dns-fallback.service` | `/etc/systemd/system/warp-dns-fallback.service` |
| `warp-dns-fallback.timer`   | `/etc/systemd/system/warp-dns-fallback.timer` |

## Notes

- WARP in **DNS-over-HTTPS mode** secures DNS only (not a full tunnel), so
  `cdn-cgi/trace` shows `warp=off` even when connected — that is normal.
- Adjust the fallback resolvers or probe cadence by editing the variables at the
  top of `warp-dns-fallback.sh` and the timer interval in
  `warp-dns-fallback.timer`.

## License

MIT
