# Troubleshooting

1. Site unreachable / hangs
2. Certificate won't issue
3. Out of host capacity
4. Tailscale (private access, no open ports)
5. No card / card rejected — fallbacks
6. Idle reclamation warnings
7. n8n-specific errors
8. Memory and performance

---

## 1. Site unreachable / connection hangs

Almost always the firewall, and almost always because only one of the two layers was opened.

Diagnose from the VM outward:

```bash
curl -I localhost:5678              # n8n itself alive?
docker compose ps                   # both containers Up?
sudo iptables -L INPUT -n --line-numbers | head -20   # 80/443 ACCEPT present?
```

If `curl localhost` works but the public URL hangs, the traffic is being dropped by a firewall, not by n8n.

- Check the **Security List / NSG** in the OCI Console has ingress on TCP 80 and 443 from `0.0.0.0/0`. Confirm you edited the security list attached to *this instance's subnet*, not another VCN.
- Check instance iptables. If the rules from Phase 2.2 are missing, re-add and `sudo netfilter-persistent save`.
- Rules inserted at position 6 must land *above* the catch-all REJECT. Verify with the line-numbered listing; if the REJECT is above your ACCEPT rules, delete and re-insert lower.

A rule that exists but wasn't saved disappears on reboot. Always run `netfilter-persistent save`.

## 2. Certificate won't issue

Caddy logs show ACME failure.

- **DNS not propagated.** `dig +short <domain>` must return the VM's public IP. Wait and retry.
- **Port 80 blocked.** The HTTP-01 challenge needs port 80 inbound, not just 443. Both layers again.
- **Rate limited.** Let's Encrypt allows 5 failures per account/hostname per hour. If hit, wait an hour — repeated retries extend the block.
- **Domain mismatch.** The domain in `Caddyfile` must match exactly, no `https://`, no trailing slash.

```bash
docker compose logs caddy | grep -i -E "error|challenge|obtain"
```

## 3. Out of host capacity

Not a mistake — Always Free ARM demand exceeds supply in most regions.

- Retry the launch loop in SKILL.md Phase 1. Capacity is released in bursts, often at odd hours UTC.
- Try a different **availability domain** within the region if the region has more than one.
- Request a smaller shape: 2 OCPU / 12 GB frequently succeeds where 4/24 fails, and is ample for n8n.
- Fall back to `VM.Standard.E2.1.Micro` (AMD). 1 GB RAM: keep the 4 GB swap, and set `NODE_OPTIONS=--max-old-space-size=512` in the n8n environment block.
- Do not open a second Oracle account to work around it. Multiple accounts are against the terms and get both banned.

## 4. Tailscale — private access without opening ports

Better security posture; the trade-off is the phone needs the Tailscale app to reach it.

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

Then skip the DuckDNS and Caddy pieces. Use Tailscale's own HTTPS:

```bash
sudo tailscale cert <machine>.<tailnet>.ts.net
sudo tailscale serve --bg 5678
```

Change the compose file to publish n8n on `127.0.0.1:5678:5678` and set `N8N_HOST` to the `.ts.net` name. Install Tailscale on the phone, sign in to the same account, browse to the `.ts.net` address.

Tailscale's free tier covers 3 users and 100 devices — comfortably enough.

## 5. No card, or card rejected

Oracle rejects virtual, prepaid and single-use cards, and PIN-required debit cards. A standard Visa/Mastercard debit card without PIN requirement usually works.

If a card genuinely isn't possible, there is no 24/7 free VM equivalent. Honest options, all with real trade-offs:

- **Old laptop or Raspberry Pi at home.** Genuinely free, fully yours, runs the same Docker stack unchanged. Needs to stay powered on; use Tailscale (§4) rather than opening ports on a home router. This is the best fallback.
- **Google Cloud `e2-micro` free tier** — free in certain US regions, but also requires a card.
- **Render / Railway free tiers** — no card for basic use, but containers sleep on inactivity, which defeats 24/7 scheduling.
- **n8n Cloud free tier** — capped at a low monthly execution count. Fine only for testing.

Do not tell the user a card-free Oracle path exists. It does not.

## 6. Idle reclamation warnings

Oracle emails before reclaiming. If one arrives:

- Confirm real workloads are running — scheduled workflows that actually do work, not empty triggers.
- Check metrics in the Console (Compute → Instance → Metrics) against the 7-day window.
- Make sure backups are current and off-machine. That is the only reliable protection; rebuilding from a backup takes about 30 minutes with this skill.

## 7. n8n errors

- **"Command failed: X" on the Docker socket** — the user isn't in the docker group. `newgrp docker` or log out and back in.
- **Webhook URL shows `localhost` or the wrong host** — `WEBHOOK_URL` and `N8N_EDITOR_BASE_URL` are unset or wrong. Fix `.env`, then `docker compose up -d --force-recreate`.
- **"Secure cookie" login failure** — the site is being served over plain HTTP. Fix the certificate rather than setting `N8N_SECURE_COOKIE=false`; disabling it sends the session cookie in clear.
- **Credentials unreadable after a rebuild** — `N8N_ENCRYPTION_KEY` changed. Restore the original key from `.env` in the backup. Without it, stored credentials are unrecoverable and must be re-entered.
- **Workflows vanish after `docker compose down -v`** — `-v` deletes named volumes. Never use it here.

## 8. Memory and performance

```bash
free -h
docker stats --no-stream
```

- Cap n8n's log volume: `N8N_LOG_LEVEL=warn`.
- Prune execution history: `EXECUTIONS_DATA_PRUNE=true`, `EXECUTIONS_DATA_MAX_AGE=168` (hours). The default SQLite database grows without bound otherwise and is the usual cause of a slow instance after a few weeks.
- On 24 GB there is room to add a local model via Ollama (`ollama run qwen2.5:7b`) for tasks where rate limits bite. CPU-only inference is slow — acceptable for background jobs, not for anything interactive.
