# Phase 5 — wiring Groq, Gemini and Cerebras into n8n

Three providers, no card for any of them. Groq is the workhorse, Gemini handles
long documents, Cerebras absorbs high-volume short prompts. Between them you
have two independent fallbacks when one rate-limits.

Rate limits on free tiers change often — confirm against each provider's own
docs before building anything that depends on the numbers below.

## Groq — the default

Key: https://console.groq.com/keys

In n8n: **Credentials → New → OpenAI**

| Field | Value |
|---|---|
| API Key | your Groq key |
| Base URL | `https://api.groq.com/openai/v1` |

Name it `Groq` so it's obvious in node dropdowns. In any OpenAI or AI Agent
node, **type the model name manually** — the dropdown lists OpenAI's models, not
Groq's:

```
llama-3.3-70b-versatile
```

Roughly 30 requests/minute, ~14,400/day.

## Google Gemini — long context

Key: https://aistudio.google.com/apikey

In n8n: **Credentials → New → Google Gemini (PaLM) API**. Native node, no base
URL to set. Low requests-per-minute but very long context, so use it where the
input is a big document rather than where the call count is high.

## Cerebras — high throughput, short prompts

Key: https://cloud.cerebras.ai

In n8n: **Credentials → New → OpenAI** again, second credential.

| Field | Value |
|---|---|
| API Key | your Cerebras key |
| Base URL | `https://api.cerebras.ai/v1` |

~1M tokens/day, but **8K context cap** — it will fail outright on long inputs,
so never make it the fallback for a Gemini long-document workflow. Model name is
typed manually, e.g. `llama3.1-8b`.

## The failover pattern

Put two providers behind one workflow so a rate-limit doesn't stop the line:

1. AI Agent node → Groq credential
2. On that node: **On Error → Continue (using error output)**
3. Error branch → second AI Agent node → Gemini (or Cerebras) credential
4. Merge both branches

Pick the fallback by shape, not preference: long input → Gemini; lots of short
calls → Cerebras.

For heavier fan-out, add a **Loop Over Items** node with batch size 1 and a short
**Wait** node between iterations. Slower, but it stays inside the per-minute
limit instead of getting throttled and failing.

## Two things to hold onto

**Rate limits are the constraint, not price.** 30 requests/minute is one every
two seconds. An agent loop making five model calls per run caps out near six
runs a minute. Design workflows to batch and to run on a schedule, not in tight
loops.

**Free tiers are usually funded by your prompts.** Most of these providers
reserve the right to train on free-tier submissions. Keep personal data, client
data and anything commercially sensitive off them. If work ever involves someone
else's data, that is the moment to move to a paid tier — that is partly what the
money buys.

## When rate limits still bite

The 24 GB ARM instance has room for a local model with no limits and no data
leaving the machine:

```bash
curl -fsSL https://ollama.com/install.sh | sh
ollama pull qwen2.5:7b
```

Point n8n at `http://host.docker.internal:11434/v1` — `extra_hosts` is already
set in both compose files, so no edit is needed.

CPU-only inference on ARM runs at a few tokens per second. Usable for overnight
batch jobs, useless for anything a person is waiting on. Overflow tier beneath
the hosted APIs, not the primary.
