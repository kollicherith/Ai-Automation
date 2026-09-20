# Free 24/7 AI Automation Stack

A permanently-running n8n automation server at no monthly cost. Oracle Cloud
Always Free ARM VM → Docker → n8n Community Edition behind HTTPS, free LLM APIs
wired in, nightly backups.

**This build:** region `eu-west-1` (Dublin), private access over Tailscale,
Groq + Gemini + Cerebras wired in as LLM providers.

**Final state:** `https://ck-automation.<tailnet>.ts.net` serving n8n with a
valid certificate, unlimited workflow executions, and no monthly bill —
reachable from your own devices only, with nothing open to the internet.

**Start here if you're picking this up cold:**
[docs/decisions.md](docs/decisions.md) — every choice made and why, what's still
open, and what's been deliberately left undone.

The build instructions live in the skill at
[`.claude/skills/free-ai-automation-stack/`](.claude/skills/free-ai-automation-stack/).
Hand it to Claude Code and it works through the phases. This repo holds the
scripts and config those phases use, so the parts that can be automated are one
command each.

## Three things worth knowing before you start

**Oracle wants a card at signup.** It is a ~€1 verification hold, refunded, and
nothing is charged while you stay inside Always Free limits. Prepaid and virtual
cards get rejected, and there is no way round it. If that is a dealbreaker, the
fallbacks are in [troubleshooting §5](.claude/skills/free-ai-automation-stack/references/troubleshooting.md)
— an old laptop at home is genuinely the best one, and runs this same stack
unchanged.

**ARM capacity is scarce.** "Out of host capacity" is normal, not a mistake.
`stack/scripts/launch-retry.sh` is the retry loop. Hours to a few days is typical;
a 2 OCPU / 12 GB shape succeeds far more often and is ample for n8n.

**Free LLM tiers cap requests, not cost.** Groq gives roughly 30 requests a
minute — enough for real automation, not enough for anything tight-looped. Most
free tiers also train on what you send, so keep other people's data off them.
Setup for your three is in [docs/llm-credentials.md](docs/llm-credentials.md);
the wider comparison is in
[free-llm-providers.md](.claude/skills/free-ai-automation-stack/references/free-llm-providers.md).

## Phases

| Phase | What | Where |
|---|---|---|
| 0 | Decide region, access mode, LLM providers | done — see above |
| 1 | Provision the Oracle VM | browser, then `scripts/launch-retry.sh` if capacity fails |
| 2 | Swap, Docker (no ports opened) | `scripts/bootstrap.sh --tailscale` |
| 3 | Join the tailnet, enable HTTPS | `scripts/tailscale-up.sh` |
| 4 | Deploy n8n, publish over `tailscale serve` | `scripts/deploy.sh --tailscale` |
| 5 | Wire in Groq, Gemini and Cerebras credentials | n8n UI — [docs/llm-credentials.md](docs/llm-credentials.md) |
| 6 | Nightly encrypted backups | `scripts/backup-n8n.sh` |
| 7 | Verify | `scripts/verify.sh` |
| — | Hardening (any time after Phase 2) | `scripts/harden.sh` — see [docs/security.md](docs/security.md) |

Claude stops and waits for you at the browser steps: Oracle signup, the
Tailscale login URL, and the three API keys. Everything else is scripted.

## Usage — private mode (this build)

On the VM, after SSH works:

```bash
git clone https://github.com/kollicherith/Ai-Automation.git ~/Ai-Automation
cd ~/Ai-Automation/stack

bash scripts/bootstrap.sh --tailscale     # swap + docker, firewall left shut
newgrp docker                             # or log out and back in
bash scripts/tailscale-up.sh ck-automation # prints the login URL, then your .ts.net name
bash scripts/deploy.sh --tailscale <name>.ts.net Europe/Dublin
bash scripts/harden.sh --tailscale        # SSH, fail2ban, auto-updates, backup key

cp scripts/backup-n8n.sh ~/backup-n8n.sh && chmod +x ~/backup-n8n.sh
(crontab -l 2>/dev/null; echo "0 3 * * * ~/backup-n8n.sh >> ~/backups/backup.log 2>&1") | crontab -

bash scripts/verify.sh <name>.ts.net
```

Install the Tailscale app on your phone, sign in to the same account, and open
`https://<name>.ts.net`. **Create the owner account immediately** — leaving n8n
unclaimed is a bad habit even on a private tailnet.

### What Tailscale costs you

Two real trade-offs, both fixable, neither a surprise you should hit in week two:

- **Your phone needs the Tailscale app**, on and connected. The browser alone
  will not reach it. Free tier covers 3 users and 100 devices.
- **Inbound webhooks don't work from outside your tailnet.** GitHub, Stripe, a
  form service — none of them can call an n8n webhook that only your devices can
  see. If you need that, expose *only* the webhook path and leave the editor
  private:

  ```bash
  sudo tailscale funnel --bg --set-path /webhook http://localhost:5678/webhook
  ```

  Funnel is free and still opens no ports on the VM. Do not funnel the whole
  service — that publishes the editor UI too.

Outbound calls (an HTTP Request node, an LLM API, sending mail) are unaffected.
Schedule triggers are unaffected.

## Usage — public mode (if you switch later)

Everything for the DuckDNS + Caddy path is still here. `scripts/bootstrap.sh`
without `--tailscale` opens the instance firewall, `scripts/duckdns-setup.sh`
registers the DNS refresh, and `scripts/deploy.sh <subdomain>.duckdns.org`
deploys behind Caddy. You would need the OCI Console ingress rules as well —
see the note below.

## What the scripts assume

- **In public mode, `bootstrap.sh` only does layer 2 of the firewall. Layer 1 is
  the OCI Console Security List and no script can do it for you** — missing it is
  the single most common cause of "I followed the guide and nothing loads". The
  script prints the exact path to click. In Tailscale mode this does not apply:
  leave both layers shut.
- `tailscale-up.sh` fails loudly if HTTPS Certificates aren't enabled for your
  tailnet (admin console → Settings → Features). That is the Tailscale equivalent
  of the two-firewall trap — the raw error is not obvious, so the script
  translates it.
- `deploy.sh` never regenerates `N8N_ENCRYPTION_KEY` if `.env` already exists.
  Back that key up. Without it, every stored credential is permanently
  unreadable after a rebuild.
- `backup-n8n.sh` produces a tarball containing **decrypted** credentials and the
  encryption key. Copy it off the VM (`scp`, rclone to a free cloud tier, or a
  private repo). A backup that only exists on the machine you might lose is not
  a backup.
- Never `docker compose down -v`. The `-v` deletes the named volumes, and your
  workflows with them.
- The n8n image is **pinned to 2.40.3**. `docker compose pull` alone will not
  move you off it — bump `N8N_VERSION` in `.env` deliberately. Untagged meant
  `latest`, and n8n 3.x is already in nightly builds.
- Backups are `age`-encrypted and the script refuses to upload an unencrypted
  one. Restore with `scripts/restore.sh`. The private key is printed once by
  `harden.sh` — put it in your password manager then, not later.

## Security

Threat model, what's covered, and the residual risks are in
[docs/security.md](docs/security.md). The short version: nothing is open to the
internet except SSH, Code nodes can't read the encryption key out of the
environment, backups are encrypted before they leave the VM, and a pre-commit
hook blocks secrets from reaching git.

Install the hook once per clone — git doesn't copy hooks:

```bash
bash stack/scripts/install-git-hooks.sh
bash stack/scripts/test-git-hooks.sh   # 17 cases, both directions
```

## Differences from the skill's inline snippets

The scripts are the skill's commands made idempotent and re-runnable, plus:

- **Firewall insert position.** The skill inserts iptables rules at position 6.
  `bootstrap.sh` finds the first `REJECT`/`DROP` in the INPUT chain and inserts
  above it, because an ACCEPT rule landing below the catch-all never matches.
- **Execution-data pruning on by default.** `EXECUTIONS_DATA_PRUNE=true`,
  `EXECUTIONS_DATA_MAX_AGE=168`, `N8N_LOG_LEVEL=warn` are in `docker-compose.yml`
  rather than left to troubleshooting §8. Unbounded SQLite growth is the usual
  cause of an instance that gets slow after a few weeks.
- **`extra_hosts: host.docker.internal`** is set from the start, so adding Ollama
  later needs no compose edit. It is a no-op until Ollama exists.
- **A second compose file for private mode.** `docker-compose.tailscale.yml`
  drops Caddy and publishes n8n on `127.0.0.1:5678` only, so the sole route in is
  `tailscale serve`. `verify.sh` asserts it is not listening on `0.0.0.0`.
- **Backup cleans up its own exports** from `./files` after tarring them, so they
  do not accumulate in the n8n files volume.

## Ongoing

```bash
cd ~/n8n
docker compose pull && docker compose up -d   # update n8n
docker compose logs -f n8n                    # tail logs
docker compose restart
```

When something breaks, read
[troubleshooting.md](.claude/skills/free-ai-automation-stack/references/troubleshooting.md)
before improvising. The common failures have specific known causes.
