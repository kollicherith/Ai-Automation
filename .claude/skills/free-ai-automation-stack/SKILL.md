---
name: free-ai-automation-stack
description: Build a zero-cost, always-on AI automation server — Oracle Cloud Always Free VM running n8n in Docker behind HTTPS, wired to free LLM APIs, accessible from a phone browser. Use this skill whenever the user asks to self-host n8n, set up 24/7 automation for free, run AI agents or agentic workflows on their own server, get a free VPS, build an automation stack they can control from mobile, or connect free LLM APIs (Groq, Gemini, OpenRouter, Cerebras) to a workflow engine — even if they don't name the tools explicitly.
---

# Free 24/7 AI Automation Stack

Stand up a permanently-running automation server at no monthly cost, controllable from a phone.

**Final state:** `https://<name>.duckdns.org` serves an n8n instance on an Oracle Cloud Always Free ARM VM (up to 4 cores / 24 GB RAM), with valid TLS, unlimited workflow executions, free LLM API credentials wired in, and automated backups.

---

## Phase 0 — Confirm before building

Ask the user these and wait for answers. Do not guess.

1. **Oracle region** — pick the one nearest them (e.g. `eu-west-1` Dublin, `eu-frankfurt-1`, `ap-mumbai-1`). Region is permanent per tenancy.
2. **Subdomain name** for DuckDNS (e.g. `cherith-auto` → `cherith-auto.duckdns.org`).
3. **Public network or private network?**
   - **Option A (public):** reachable from any browser. Needs ports 80/443 open. Default.
   - **Option B (Tailscale):** no open ports, reachable only from their own devices. More secure, still free, but the phone needs the Tailscale app. Recommend this if they have no strong reason to expose it publicly.
4. **Which free LLM providers** they want wired in (see `references/free-llm-providers.md`).

### State the cost caveats plainly before starting

These are real and the user should hear them once, without hedging:

- **Oracle requires a payment card at signup** for identity verification. It is a temporary authorisation hold (roughly €1), automatically released, and nothing is charged while usage stays inside Always Free limits. **Virtual, prepaid and single-use cards are rejected.** There is no way around this — Oracle has not offered card-free signup for some time. If the user refuses to provide a card, stop and offer the fallback in `references/troubleshooting.md` §5.
- **ARM instances are frequently unavailable** — "Out of host capacity" is the single most common failure. Phase 1 includes a retry loop.
- **Idle instances can be reclaimed.** Oracle monitors CPU / network / memory over 7 days; instances below roughly 10–20% on all metrics may be reclaimed after warning emails. Real automation traffic usually clears this, but Phase 6 backups are the actual protection.
- **Free LLM tiers are rate-limited and most train on submitted prompts.** Fine for personal automation. Do not route client or commercial data through them.

---

## Phase 1 — Provision the VM

1. Sign up at `https://www.oracle.com/cloud/free/`. Choose the region from Phase 0. Complete card verification.
2. In the Console: **Compute → Instances → Create Instance**.
   - Image: **Ubuntu 24.04** (aarch64 build)
   - Shape: **VM.Standard.A1.Flex**, 4 OCPUs, 24 GB RAM
   - Boot volume: 100 GB (leaves headroom under the 200 GB free cap)
   - Networking: assign a **public IPv4**
   - Save the SSH private key it offers — without it there is no way in.
3. If creation fails with **"Out of host capacity"**, this is expected. Retry on a schedule rather than by hand:

```bash
# Requires OCI CLI configured: https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm
# Capture the exact launch JSON once from a failed console attempt, save as launch.json
while true; do
  oci compute instance launch --from-json file://launch.json && break
  echo "$(date): capacity unavailable, retrying in 5m"
  sleep 300
done
```

Capacity typically frees up within hours to a few days. If it never does, fall back to **2× VM.Standard.E2.1.Micro** (AMD, 1 GB RAM each) — n8n runs on one of these but needs the swap file in Phase 2 and will be slow.

4. Confirm SSH access:

```bash
chmod 600 ~/path/to/oracle_key
ssh -i ~/path/to/oracle_key ubuntu@<PUBLIC_IP>
```

---

## Phase 2 — Base system

Run everything below on the VM.

### 2.1 Update and add swap

```bash
sudo apt update && sudo apt upgrade -y
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

### 2.2 Open the firewall — BOTH layers

Oracle has two independent firewalls. Missing either one produces a site that silently never loads. This is the #1 cause of "I followed the guide and nothing works".

**Layer 1 — Cloud (Console):** Networking → Virtual Cloud Networks → your VCN → Subnet → Security List → Add Ingress Rules:

| Source | Protocol | Dest Port |
|---|---|---|
| 0.0.0.0/0 | TCP | 80 |
| 0.0.0.0/0 | TCP | 443 |

**Layer 2 — Instance (Ubuntu ships with restrictive iptables):**

```bash
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT
sudo netfilter-persistent save
```

Skip both if using Tailscale (Option B) — instead see `references/troubleshooting.md` §4.

### 2.3 Install Docker

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker ubuntu
newgrp docker
docker --version && docker compose version
```

---

## Phase 3 — Free domain and HTTPS

1. Register at `https://www.duckdns.org` (GitHub/Google login, no card). Create the subdomain from Phase 0, point it at the VM's public IP, and copy the DuckDNS token.
2. Keep the DNS record current in case the IP ever changes:

```bash
mkdir -p ~/duckdns
cat > ~/duckdns/duck.sh <<'EOF'
echo url="https://www.duckdns.org/update?domains=SUBDOMAIN&token=TOKEN&ip=" | curl -k -o ~/duckdns/duck.log -K -
EOF
# replace SUBDOMAIN and TOKEN above
chmod 700 ~/duckdns/duck.sh
(crontab -l 2>/dev/null; echo "*/5 * * * * ~/duckdns/duck.sh >/dev/null 2>&1") | crontab -
```

3. Confirm it resolves before continuing — Let's Encrypt will fail otherwise:

```bash
dig +short <SUBDOMAIN>.duckdns.org
```

---

## Phase 4 — Deploy n8n

```bash
mkdir -p ~/n8n && cd ~/n8n
```

**`.env`** — generate a real encryption key; losing it makes every stored credential unreadable:

```bash
cat > .env <<EOF
DOMAIN=<SUBDOMAIN>.duckdns.org
N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
GENERIC_TIMEZONE=Europe/Dublin
EOF
chmod 600 .env
```

**`Caddyfile`** (substitute the real domain — Caddy does not read `.env`):

```
<SUBDOMAIN>.duckdns.org {
    reverse_proxy n8n:5678
}
```

**`docker-compose.yml`**:

```yaml
services:
  caddy:
    image: caddy:2
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      - n8n

  n8n:
    image: docker.n8n.io/n8nio/n8n
    restart: unless-stopped
    environment:
      - N8N_HOST=${DOMAIN}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://${DOMAIN}/
      - N8N_EDITOR_BASE_URL=https://${DOMAIN}/
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - N8N_PROXY_HOPS=1
      - N8N_RUNNERS_ENABLED=true
      - GENERIC_TIMEZONE=${GENERIC_TIMEZONE}
      - TZ=${GENERIC_TIMEZONE}
    volumes:
      - n8n_data:/home/node/.n8n
      - ./files:/files
    expose:
      - "5678"

volumes:
  n8n_data:
  caddy_data:
  caddy_config:
```

Launch and watch the certificate issue:

```bash
mkdir -p files
docker compose up -d
docker compose logs -f caddy   # look for "certificate obtained successfully"
```

Open `https://<SUBDOMAIN>.duckdns.org` and create the owner account immediately — an un-owned n8n reachable on the public internet is claimable by anyone who finds it. Use a strong unique password.

n8n Community Edition is free with unlimited executions. No licence key, no execution cap.

---

## Phase 5 — Wire in free LLM APIs

Full provider table, limits and base URLs: **`references/free-llm-providers.md`**. Read it before configuring credentials.

Fastest useful default — **Groq** (no card, ~30 req/min, ~14,400 req/day, OpenAI-compatible):

1. Key from `https://console.groq.com/keys`
2. In n8n: **Credentials → New → OpenAI**
   - API Key: the Groq key
   - Base URL: `https://api.groq.com/openai/v1`
3. In any OpenAI/AI Agent node, type the model name manually (e.g. `llama-3.3-70b-versatile`) — the dropdown will not list Groq's models.

Add **Google Gemini** alongside it via n8n's native Google Gemini credential (key from `https://aistudio.google.com/apikey`) for long-context work. Two providers means one can be a fallback when the other rate-limits.

**Agent workflows:** use the **AI Agent** node with a chat model, a memory node, and tool nodes attached. Multi-agent is built by chaining AI Agent nodes, or by one agent calling sub-workflows as tools — not by any separate "swarm" product.

---

## Phase 6 — Backups and resilience

Backups matter more here than on a paid host, because reclamation and account issues are both real.

```bash
mkdir -p ~/backups
cat > ~/backup-n8n.sh <<'EOF'
#!/bin/bash
set -e
cd ~/n8n
STAMP=$(date +%F)
docker compose exec -T n8n n8n export:workflow --all --output=/files/workflows-$STAMP.json
docker compose exec -T n8n n8n export:credentials --all --output=/files/credentials-$STAMP.json
tar czf ~/backups/n8n-$STAMP.tar.gz -C ~/n8n files .env Caddyfile docker-compose.yml
find ~/backups -name 'n8n-*.tar.gz' -mtime +14 -delete
EOF
chmod +x ~/backup-n8n.sh
(crontab -l 2>/dev/null; echo "0 3 * * * ~/backup-n8n.sh >> ~/backups/backup.log 2>&1") | crontab -
```

Exported credentials are decrypted — treat that tarball as a secret. Copy it off the VM regularly (`scp`, rclone to a free cloud tier, or a **private** git repo). A backup that only exists on the machine you might lose is not a backup.

---

## Phase 7 — Verify

Walk the user through each. Do not report success until all pass.

- [ ] `https://<domain>` loads with a valid padlock, no warning
- [ ] Owner account created, login works
- [ ] A Schedule-triggered workflow fires on its own with the browser closed
- [ ] A Webhook node's production URL responds from outside the network (test from mobile data, not home wifi)
- [ ] An AI Agent node returns a completion from the free provider
- [ ] `docker compose ps` shows both containers `Up`
- [ ] Reboot test: `sudo reboot`, wait 2 min, site returns by itself
- [ ] Site loads on the phone; add to home screen for an app-like icon
- [ ] Backup script produces a tarball on a manual run

---

## Ongoing

```bash
cd ~/n8n
docker compose pull && docker compose up -d   # update n8n
docker compose logs -f n8n                    # tail logs
docker compose restart                        # restart
```

If anything fails, go to `references/troubleshooting.md` before improvising — the common failures have specific known causes.
