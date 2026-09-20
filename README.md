# Free 24/7 AI Automation Stack

A permanently-running n8n automation server at no monthly cost, reachable from a
phone browser. Oracle Cloud Always Free ARM VM → Docker → n8n Community Edition
behind Caddy with real HTTPS on a free DuckDNS domain, free LLM APIs wired in,
nightly backups.

**Final state:** `https://<name>.duckdns.org` serving n8n with a valid padlock,
unlimited workflow executions, and no monthly bill.

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
See [free-llm-providers.md](.claude/skills/free-ai-automation-stack/references/free-llm-providers.md).

## Phases

| Phase | What | Where |
|---|---|---|
| 0 | Decide region, subdomain, public vs Tailscale, LLM providers | you + Claude |
| 1 | Provision the Oracle VM | browser, then `scripts/launch-retry.sh` if capacity fails |
| 2 | Swap, firewall (both layers), Docker | `scripts/bootstrap.sh` |
| 3 | DuckDNS domain + auto-refresh | browser, then `scripts/duckdns-setup.sh` |
| 4 | Deploy n8n + Caddy, get the certificate | `scripts/deploy.sh` |
| 5 | Wire in free LLM credentials | n8n UI |
| 6 | Nightly backups | `scripts/backup-n8n.sh` |
| 7 | Verify | `scripts/verify.sh` |

Claude stops and waits for you at the browser steps: Oracle signup, DuckDNS
registration, API keys. Everything else is scripted.

## Usage

On the VM, after SSH works:

```bash
git clone https://github.com/kollicherith/Ai-Automation.git ~/Ai-Automation
cd ~/Ai-Automation/stack

bash scripts/bootstrap.sh                       # --tailscale to skip opening ports
newgrp docker                                   # or log out and back in
bash scripts/duckdns-setup.sh <subdomain> <token>
bash scripts/deploy.sh <subdomain>.duckdns.org Europe/Dublin

cp scripts/backup-n8n.sh ~/backup-n8n.sh && chmod +x ~/backup-n8n.sh
(crontab -l 2>/dev/null; echo "0 3 * * * ~/backup-n8n.sh >> ~/backups/backup.log 2>&1") | crontab -

bash scripts/verify.sh <subdomain>.duckdns.org
```

Then open `https://<subdomain>.duckdns.org` and **create the owner account
immediately** — an unclaimed n8n on the public internet belongs to whoever finds
it first.

## What the scripts assume

- `bootstrap.sh` only does layer 2 of the firewall. **Layer 1 is the OCI Console
  Security List and no script can do it for you** — missing it is the single most
  common cause of "I followed the guide and nothing loads". The script prints the
  exact path to click.
- `deploy.sh` never regenerates `N8N_ENCRYPTION_KEY` if `.env` already exists.
  Back that key up. Without it, every stored credential is permanently
  unreadable after a rebuild.
- `backup-n8n.sh` produces a tarball containing **decrypted** credentials and the
  encryption key. Copy it off the VM (`scp`, rclone to a free cloud tier, or a
  private repo). A backup that only exists on the machine you might lose is not
  a backup.
- Never `docker compose down -v`. The `-v` deletes the named volumes, and your
  workflows with them.

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
