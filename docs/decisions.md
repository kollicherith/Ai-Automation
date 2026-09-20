# Decisions and handover

Everything agreed or flagged while building this, written down because the
session it was said in is ephemeral and this repo isn't. If you come back to
this in three months, or hand it to someone else, start here.

Last updated: 2026-09-20. Status: **nothing provisioned yet.** All code is
written and validated; Phase 1 hasn't started.

---

## Phase 0 — the four answers

| Question | Answer | Why it matters |
|---|---|---|
| Oracle region | **eu-west-1 (Dublin)** | Permanent per tenancy. Cannot be changed later without a new account. |
| Name | **ck-automation** | Chosen as a DuckDNS subdomain, now used as the Tailscale machine name — see below. |
| Access | **Tailscale (private)** | No ports open to the internet. Reshapes Phases 3–4 entirely. |
| LLM providers | **Groq + Gemini + Cerebras** | Groq is the default workhorse; the other two are fallbacks of different shapes. |

### The name changed meaning

`ck-automation` was answered as a DuckDNS subdomain. The Tailscale path doesn't
use DuckDNS, so it became the tailnet machine name instead
(`tailscale up --hostname=ck-automation`), giving
`ck-automation.<tailnet>.ts.net`. Without pinning it, the address would have been
whatever Oracle named the instance. The DuckDNS scripts remain in the repo,
unused, for a switch to public mode.

---

## The three caveats, stated once

**Oracle requires a payment card at signup.** A ~€1 authorisation hold, released
automatically, nothing charged while usage stays inside Always Free limits.
Virtual, prepaid and single-use cards are rejected, as are PIN-required debit
cards. There is no card-free Oracle path — don't go looking for one. If a card
is genuinely impossible, an old laptop or Raspberry Pi at home is the best
fallback and runs this exact Docker stack unchanged (troubleshooting §5).

**ARM capacity is scarce.** "Out of host capacity" is the expected outcome, not
an error. `stack/scripts/launch-retry.sh` retries on a schedule. Hours to a few
days is normal. **Never open a second Oracle account to work around it** — that
violates the terms and gets both banned.

**Free LLM tiers cap requests, not cost.** ~30 requests/minute on Groq is one
every two seconds; an agent loop making five calls per run caps out near six runs
a minute. Design for batching and schedules, not tight loops. Most free tiers
train on submitted prompts — keep other people's data off them.

---

## Choices made, and why

**2 OCPU / 12 GB over 4 / 24 on the first attempt.** The skill specifies 4/24.
Smaller shapes clear the capacity queue far more often, n8n nowhere near needs
24 GB, and A1.Flex scales up later without a rebuild. The only thing 24 GB buys
is headroom for local Ollama, which runs at a few tokens/sec on ARM CPU anyway.

**Tailscale over public, with eyes open.** Two costs, both real:

- The phone needs the Tailscale app, on and connected. The browser alone won't
  reach it. "Phone access is just the browser" stops being true.
- **Inbound webhooks don't work from outside the tailnet.** No external service
  can call an n8n webhook only your devices can see. Phase 7's "webhook responds
  from mobile data" check is impossible as written and was replaced. The fix,
  when needed, exposes *only* the webhook path:
  `tailscale funnel --bg --set-path /webhook http://localhost:5678/webhook`.
  Outbound calls and schedule triggers are unaffected.

**The n8n image is pinned to `2.40.3`.** The skill's snippet has no tag, which
means `latest`. n8n 3.x is already in nightly builds; an unattended
`docker compose pull` would have jumped a major version. Override with
`N8N_VERSION` in `.env`. Bump deliberately, read the release notes, and know
that patch bumps within 2.40.x are the safe ones.

**Firewall rules insert above the first REJECT, not at position 6.** The skill
hardcodes position 6. Ubuntu on OCI ships a catch-all REJECT in INPUT, and an
ACCEPT landing below it never matches — which presents as a site that silently
never loads, the single most common failure in this build. `bootstrap.sh` finds
the REJECT and inserts above it. (Public mode only; unused on this build.)

**`deploy.sh` refuses to regenerate `N8N_ENCRYPTION_KEY`.** Regenerating it makes
every stored credential permanently unreadable. Re-running deploy is safe.

**Execution pruning and log caps on by default.** `EXECUTIONS_DATA_PRUNE`,
`EXECUTIONS_DATA_MAX_AGE=168`, `N8N_LOG_LEVEL=warn`, and per-container log caps.
Unbounded SQLite growth is the usual cause of an instance that gets slow after a
few weeks; the skill leaves this to troubleshooting §8.

**Backups are encrypted, and the restore path exists.** The archive contains
decrypted credentials *and* the encryption key. It's now `age`-encrypted so it
can safely leave the VM, and `restore.sh` was written because an encrypted
backup with no tested restore path is a trap, not a safeguard.

---

## Still open

- **Nothing is provisioned.** Oracle signup hasn't happened. Everything below
  Phase 1 is untested against a real VM by definition.
- **SSH is still open to the world** on the default security list. Closing it is
  described in `security.md` and deliberately not automated — getting it wrong
  locks you out permanently.
- **No off-VM backup destination chosen.** `BACKUP_REMOTE` supports an rclone
  remote; no remote is configured yet.
- **Starter workflows not built.** Offered and not yet taken up: importable
  workflows including the Groq→Gemini failover pattern, which double as the real
  traffic that keeps Oracle's idle-reclamation watchdog off you.
- **Branch not promoted.** The repo was empty; `claude/oracle-always-free-n8n-wqmbh7`
  is the only branch. No PR opened, nothing promoted to `main`.

---

## What Claude can and can't do here

Can: write and validate everything in this repo, reason about the design, work
through failures with you.

Can't: click through Oracle signup, DuckDNS or Tailscale login, enter card
details, or reach your VM. It runs in an ephemeral cloud container with no route
to your machine, and shouldn't hold your SSH key.

**Don't paste API keys into the chat.** Groq, Gemini and Cerebras keys go
straight into the n8n credentials UI. Nothing in this repo needs to see them, and
a key in a transcript is a key you have to rotate.
