# Upstream Integration - 2026-10-20

Source: [vincentng295/xray_vless_ws_server](https://github.com/vincentng295/xray_vless_ws_server),
through commit [`7503b16`](https://github.com/vincentng295/xray_vless_ws_server/commit/7503b16fbd36d9341ad0b7cbe207a2f1f666a7ad) (2026-10-17).
Fork baseline: `6abc0ab`; common ancestor: `2302bde`.

## Plan and Compatibility Policy

1. Inspect all 22 upstream-only commits, not just the seven published after the fork's latest commit.
2. Adapt features to Quick / Named / Direct modes rather than replace the launchers.
3. Keep No TLS port 80, `/vless`, country labels, Termux detection, systemd and process-health fixes.
4. Keep existing `.env` settings and raw-link consumers working; make new behavior configurable.
5. Validate configuration, links, logger authentication and launcher persistence before release.

This is a curated integration, not a merge commit. The upstream commits remain separate in
Git history; future updates must use this checkpoint and the decisions below to avoid
reapplying or undoing fork-specific behavior. No automatic deployment is performed.

## Change Accounting

| Upstream commit | Change | Integration decision |
| --- | --- | --- |
| `7503b16` | New client addresses | Add TikTok, VNPT and MobiFone presets alongside the two old presets. Existing `.env` is not overwritten. |
| `cf8e18f` | WARP IPv6-only mode | Add `ENABLE_WARP=ip6only`, IPv4 endpoint bootstrap and IPv6 destination routing. Keep IPv4 direct. |
| `fc1213e` | Routing-only sniffing | Enable `routeOnly` and HTTP/TLS/QUIC sniffing on generated inbounds. |
| `34491bd` | Correct ECH parameter | Encode `actual-host+DoH-URL`, including dynamically discovered Quick Tunnel hostnames. |
| `079818b` | ECH off by default | Keep `DNSECH` empty; omit the parameter entirely when disabled. |
| `3d8e186` | Base64 subscription output | Always add `frp_info.base64`; keep raw `frp_info.config` by default. `FRP_INFO_FORMAT=base64` selects upstream-compatible output. Both launchers decode either format. |
| `2da87d7` | DNS ECH support | Add optional client-side ECH URL parameter; does not enable ECH on a server or guarantee client support. |
| `5af74e4` | xHTTP auto mode | Default to `auto` for new installations; retain explicit old values. Update both menus. |
| `83198ec` | Remove No TLS | Intentionally retain the fork's port 80 / `PORT_MODE` options. Direct mode still exports TLS links only, as before. |
| `03a7c2c` | Replace default destination addresses | Include new defaults but preserve old addresses and user-defined values. Do not hardcode dynamically resolved MobiFone IPs. |
| `8c0f225` | Require supplied TLS certificates | Require PEM certificate/key files when TLS listener is enabled. Validate their key pair before launching. No self-signed auto-generation. |
| `ccfc756` | Public-IP diagnostic | Best-effort global IP lookup warning in Direct mode only; do not reject NAT or private-network tunnel hosts. |
| `7220c84` | IPv6 listeners | Parse bracketed addresses, support IPv6 demux sockets and bracket Cloudflared origin URLs. |
| `c7714ae` | Independent TLS listener | Add optional `TLS_PORT`, `TLS_PEM`, `TLS_KEY`. Serves the first transport, like upstream, independently of plaintext listeners. |
| `d4b2507` | Correct plaintext port 443 example | Remove misleading plaintext `PORT=...:443` documentation. Port numbers alone do not enable TLS. |
| `b0b35cb` | Logger password support | Use localhost by default; protect both UI and logs with `PASSWORD`. Support Basic Auth and upstream query-password authentication. Also render logs as text to prevent HTML injection. |
| `b29f07c` | Direct wgcf binaries | Use upstream author's v0.3.6 binary assets; remove archive extraction and `zstandard`. Preserve Android/Termux detection. |
| `6727b7a` | Xray executable permissions | Already covered more broadly by the fork's non-Windows chmod and Termux runnable-binary checks; retain them. |
| `cd3ec3a` | Cloudflared 2026.8.2 | Update pinned version for future installs; do not replace an installed running binary automatically. |
| `bc27fef` | Cloudflared on Android/Termux | Keep PATH/package-manager installation and add Android-aware downloader behavior. |
| `6af8ad6` | Wireshark comparison | Include both captures with corrected QUIC/ECH explanation. QUIC Initial encryption is not confidentiality against passive observers. |
| `0a4e625` | Optional Cloudflared; remove Workers | Direct mode already skips Cloudflared. Retain explicit modes and the fork's `_worker.js`. Do not restore deleted GitHub Workflows or add workflow-only GitPython. |

## Using the New Options

- Open menu **7** in `bash run.sh` or `run-windows.bat` for WARP, ECH, TLS, logger and output format. Restart after saving. Existing mode setup menus preserve these options.
- Select address preset **4** for MobiFone, **5** for VNPT, **6** for all new upstream addresses, or **7** for old and new together. These are client destinations, not TLS SNI. Carrier billing/availability must be tested separately; preset names are not a guarantee.
- Quick Tunnel remains WebSocket-only in the menus. Named and Direct retain dual transport support.
- ECH requires client support and appropriate DNS HTTPS/ECH records for the actual tunnel hostname. An HTTPS DoH URL alone cannot provide those records.
- `TLS_PORT=0.0.0.0:443` requires an existing `TLS_PEM` fullchain and matching unencrypted `TLS_KEY`. For Cloudflare Full (strict), use a certificate valid for your origin hostname and choose a single transport. TLS serves only the first listed transport; choose `TRANSPORT=xhttp` if that should be xHTTP. Other transport links need the plaintext origin. `PORT` remains plaintext and independent.
- Additional TLS listeners do not change client destination addresses/ports in exported CDN links. For direct-to-origin testing on another TLS port, configure that address/port explicitly in the client. Renew certificates externally and restart Xray.
- `ENABLE_WARP=ip6only` routes IPv6 destinations through WARP, not "devices with IPv6". It is not an IPv6-only inbound firewall.
- Logger URL: `http://127.0.0.1:9999`. Remote example: `ssh -L 9999:127.0.0.1:9999 user@vps`. Prefer Basic Auth over query passwords; URL passwords may appear in browser history. Never expose its plain HTTP listener publicly without a protected tunnel/reverse proxy.
- `DEBUG_MODE=true` also prints live logger output to the console. The fork's detailed Xray logs remain available in the local logger.
- View either subscription format: `python runtime_config.py --show-links frp_info.config`.
- To update existing downloaded binaries, stop the server first, then run `python download-cloudflared.py` or `python download-wgcf.py` using the project's Python environment. Termux continues to use `pkg` for Cloudflared.

## Validation

```sh
python -m pip install -r requirements.txt
python -m py_compile main.py runtime_config.py logging_site.py
bash -n run.sh
bash -n install.sh
```

The test suites are local-only (`/test/` and `/tests/` are excluded by `.gitignore`)
and are not distributed with the repository. Their checks do not modify a VPS.

Validation completed on Windows on 2026-10-20: 41 Python tests passed, including the
optional real-core tests with Xray v26.7.11 (WS, four xHTTP modes, IPv6, TLS and WARP
configuration checks). Bash syntax and both launcher suites passed. Runtime tests for
Quick/Named/Direct use mocked processes; no live Cloudflare connector, carrier billing,
WARP registration, Linux/Termux host or existing VPS was modified/tested end-to-end.
