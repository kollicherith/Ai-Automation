# Free LLM providers

Rate limits on free tiers change often. Treat the numbers below as a starting point and confirm against the provider's own docs before building anything that depends on them.

## Comparison

| Provider | Card? | Rough free limit | Base URL | Best for |
|---|---|---|---|---|
| **Groq** | No | ~30 req/min, ~14,400 req/day | `https://api.groq.com/openai/v1` | Default. Fast open-weight models, generous daily cap |
| **Google AI Studio (Gemini)** | No | Per-project tier, low RPM, high context | native n8n node | Frontier-quality model, long documents |
| **Cerebras** | No | ~1M tokens/day, 8K context cap | `https://api.cerebras.ai/v1` | Very high throughput, short prompts |
| **OpenRouter** | No | 20 req/min; 50/day, rising to 1,000/day after any lifetime credit purchase | `https://openrouter.ai/api/v1` | One key across many models, failover |
| **Cloudflare Workers AI** | No | ~10,000 neurons/day | Workers binding or REST | Edge inference, small tasks |
| **Mistral La Plateforme** | No | High monthly token allowance | `https://api.mistral.ai/v1` | European hosting, solid general models |
| **GitHub Models** | No | Low monthly chat allowance | Azure AI inference endpoint | Trying frontier models occasionally |
| **NVIDIA NIM** | No | ~40 req/min | `https://integrate.api.nvidia.com/v1` | Wide model catalogue |

All of the above except Gemini and Cloudflare are OpenAI-SDK compatible — in n8n, use the **OpenAI** credential with the base URL swapped, and type the model name manually rather than picking from the dropdown.

## Two things to be clear with the user about

**Rate limits are the real constraint, not price.** 30 requests per minute is one every two seconds. An agent loop that makes five model calls per run caps out around six runs a minute. Design workflows to batch work and to run on a schedule rather than in tight loops.

**Free tiers are usually funded by your prompts.** Most providers reserve the right to train on free-tier submissions. Keep personal data, client data and anything commercially sensitive off them. If the work ever involves someone else's data, that is the point to move to a paid tier — that is partly what the money buys.

## Resilience pattern

Put two providers behind one workflow so a rate-limit doesn't stop the line:

1. AI Agent node → Groq credential
2. **On Error → Continue (using error output)**
3. Error branch → second AI Agent node → Gemini credential
4. Merge both branches

For heavier fan-out, add a **Loop Over Items** node with a batch size of 1 and a short **Wait** node between iterations. Slower, but it stays inside the per-minute limits instead of getting throttled and failing.

## Local fallback

On the 24 GB ARM instance, Ollama gives unmetered inference with no rate limit and no data leaving the machine:

```bash
curl -fsSL https://ollama.com/install.sh | sh
ollama pull qwen2.5:7b
```

Point n8n at `http://host.docker.internal:11434/v1` (add `extra_hosts: ["host.docker.internal:host-gateway"]` to the n8n service in `docker-compose.yml`).

CPU-only inference on ARM runs at a few tokens per second. That is usable for overnight batch jobs and useless for anything a person is waiting on. Use it as the overflow tier beneath the hosted free APIs, not as the primary.
