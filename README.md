# warp-fallback

A tiny, dependency-light **DNS fallback watchdog for Cloudflare WARP** on Linux.

When Cloudflare WARP is connected it manages `/etc/resolv.conf` and points the
system at its own local DNS stubs (`127.0.2.2`, `127.0.2.3`). If the `warp-svc`
daemon crashes or disconnects, those stubs go dead and **all DNS resolution
breaks** — there is no fallback nameserver.

This watchdog fixes that: while WARP DNS is unreachable it temporarily appends
public resolvers (`1.1.1.1`, `8.8.8.8`) to `resolv.conf`, and removes them again
as soon as WARP recovers.

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

1. Probe WARP's stub `127.0.2.2` with `dig` for an A record.
2. **Healthy** → ensure no fallback block is present (remove ours if WARP has
   recovered).
3. **Down** → append a clearly-marked block:

   ```
   # warp-dns-fallback (added <timestamp>; WARP DNS unreachable)
   nameserver 1.1.1.1
   nameserver 8.8.8.8
   ```

It is **self-healing**: when WARP reconnects it rewrites `resolv.conf` itself,
which also clears the block. The watchdog only edits its own marked lines, so it
never clobbers WARP's content.

## Requirements

- Linux with `systemd`
- `dig` (Debian/Ubuntu: `dnsutils`; Fedora: `bind-utils`)
- Cloudflare WARP (`warp-svc`) using the default local stub `127.0.2.2`

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
