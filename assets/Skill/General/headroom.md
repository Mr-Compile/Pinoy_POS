---
name: headroom
description: >
  Expert guide for installing, configuring, and using Headroom — the context
  compression layer for AI agents. Use this skill whenever the user mentions
  Headroom, token compression, context compression, reducing LLM token costs,
  headroom-ai, headroom proxy, headroom wrap, CCR reversible compression,
  Kompress-base, SmartCrusher, CodeCompressor, CacheAligner, cross-agent
  memory, headroom learn, or output token reduction. Also trigger when the user
  asks how to make AI agents cheaper, how to reduce context window usage, how
  to share memory between Claude/Codex/Gemini, or how to set up a drop-in
  compression proxy for any LLM client. Even if they just say "compress my
  prompts" or "save tokens with my agent" — use this skill.
---

# Headroom Skill

Headroom is a **local-first** context compression layer: it sits between your
agent/app and the LLM provider, compresses everything (tool outputs, RAG
chunks, logs, files, conversation history), and passes smaller prompts to the
model. Same answers, 60–95% fewer tokens.

## Quick Mental Model

```
Agent / App
  │  (tool outputs · logs · RAG · files · history)
  ▼
Headroom  (runs locally — data never leaves)
  │  CacheAligner → ContentRouter → CCR
  │    ├─ SmartCrusher   (JSON)
  │    ├─ CodeCompressor (AST)
  │    └─ Kompress-base  (text, HuggingFace)
  ▼
LLM Provider  (Anthropic · OpenAI · Bedrock · …)
```

---

## Installation

```bash
# Python (everything)
pip install "headroom-ai[all]"

# TypeScript / Node
npm install headroom-ai

# Docker
docker pull ghcr.io/chopratejas/headroom:latest
```

**Python 3.10+ required.** Granular extras: `[proxy]`, `[mcp]`, `[ml]`,
`[code]`, `[memory]`, `[relevance]`, `[image]`, `[agno]`, `[langchain]`,
`[evals]`, `[pytorch-mps]`.

Using pipx?
```bash
pipx install --python python3.13 "headroom-ai[all]"
```

### Updating

```bash
headroom update           # auto-detects pip/pipx/uv and upgrades in place
headroom update --check   # report latest version without upgrading
headroom update --pre     # include pre-releases
```

---

## Usage Modes

### 1. Wrap a coding agent (simplest)

```bash
headroom wrap claude         # Claude Code
headroom wrap codex          # OpenAI Codex
headroom wrap cursor         # Cursor (prints config to paste)
headroom wrap aider          # Aider
headroom wrap copilot        # GitHub Copilot CLI
headroom wrap opencode       # OpenCode
```

One command — Headroom starts the proxy and launches the agent with compression
transparently applied.

### 2. Drop-in proxy (zero code changes)

```bash
headroom proxy --port 8787
```

Point any OpenAI-compatible client at `http://localhost:8787`. Works with any
language, any framework.

```bash
headroom dashboard           # live savings dashboard (proxy must be running)
```

### 3. Inline library (Python)

```python
from headroom import compress

compressed = compress(messages, model="claude-opus-4-5")
# Pass compressed to your LLM call
```

### 4. TypeScript / Node

```typescript
import { compress } from "headroom-ai";

const compressed = await compress(messages, { model: "claude-opus-4-5" });
```

### 5. MCP server

```bash
headroom mcp install
```

Exposes `headroom_compress`, `headroom_retrieve`, `headroom_stats` to any MCP
client.

---

## Integration Reference

| Setup                  | How to hook in                                                   |
|------------------------|------------------------------------------------------------------|
| Python app             | `compress(messages, model=…)`                                    |
| TypeScript app         | `await compress(messages, { model })`                            |
| Anthropic SDK          | `withHeadroom(new Anthropic())`                                  |
| OpenAI SDK             | `withHeadroom(new OpenAI())`                                     |
| Vercel AI SDK          | `wrapLanguageModel({ model, middleware: headroomMiddleware() })`  |
| LiteLLM                | `litellm.callbacks = [HeadroomCallback()]`                       |
| LangChain              | `HeadroomChatModel(your_llm)`                                    |
| Agno                   | `HeadroomAgnoModel(your_model)`                                  |
| ASGI apps              | `app.add_middleware(CompressionMiddleware)`                       |
| Multi-agent            | `SharedContext().put / .get`                                     |
| MCP clients            | `headroom mcp install`                                           |

---

## Key Features

### CCR — Reversible Compression

Headroom stores originals locally. If the LLM needs the full original, it calls
`headroom_retrieve`. Compression is never lossy without a way back.

Configure TTL and storage path via `HEADROOM_CCR_TTL` and `HEADROOM_CCR_PATH`.

### Cross-Agent Memory

```python
from headroom.memory import SharedContext

ctx = SharedContext()
ctx.put("key", value)           # store from any agent
result = ctx.get("key")         # retrieve from any agent
```

Works across Claude, Codex, Gemini. Auto-deduplicates. Persists across
sessions.

### Output Token Reduction

Reduces what the model **writes back** (not just what you send). Useful on
Opus-class models where output costs 5× input.

```bash
export HEADROOM_OUTPUT_SHAPER=1
headroom proxy --port 8787
```

Adds verbosity steering and effort routing. Measure savings:

```bash
headroom output-savings
# Reduction: 31.7%  (95% CI 27.7% … 35.7%)   [estimated]
```

For measured (vs. estimated) savings, use a holdout control group:

```bash
export HEADROOM_OUTPUT_HOLDOUT=0.1
```

Learn the right terseness automatically from past sessions:

```bash
headroom learn --verbosity            # preview (dry run)
headroom learn --verbosity --apply    # save and apply
```

### `headroom learn` — Failure Mining

Mines failed agent sessions and writes corrections to `CLAUDE.md` /
`AGENTS.md` / `GEMINI.md`.

```bash
headroom learn
```

---

## Performance Benchmarks

| Workload                  | Before | After  | Savings |
|---------------------------|-------:|-------:|--------:|
| Code search (100 results) | 17,765 |  1,408 | **92%** |
| SRE incident debugging    | 65,694 |  5,118 | **92%** |
| GitHub issue triage       | 54,174 | 14,761 | **73%** |
| Codebase exploration      | 78,502 | 41,254 | **47%** |

Accuracy is preserved: GSM8K ±0.000, TruthfulQA +0.030, SQuAD v2 97% at 19%
compression, BFCL tools 97% at 32% compression.

Reproduce: `python -m headroom.evals suite --tier 1`

---

## GitHub Copilot CLI Integration

```bash
headroom copilot-auth login
headroom wrap copilot --subscription -- --model gpt-4o
```

For GitHub Enterprise Server:

```bash
export GITHUB_COPILOT_ENTERPRISE_DOMAIN=ghe.example.com
headroom wrap copilot --subscription
```

---

## Troubleshooting

See `references/troubleshooting.md` for:
- Corporate / SSL-inspection environments (`CERTIFICATE_VERIFY_FAILED`)
- "Basic Constraints of CA cert not marked critical" (Python 3.13 + OpenSSL 3.x)
- Rust / maturin build failures
- ONNX Runtime download issues (`cdn.pyke.io`)
- HuggingFace model download issues

---

## When to Skip Headroom

- You only use a single provider's native compaction and don't need cross-agent
  memory.
- You work in a sandboxed environment where local processes can't run.

---

## Links

- Docs: https://headroom-docs.vercel.app/docs
- PyPI: https://pypi.org/project/headroom-ai/
- npm: https://www.npmjs.com/package/headroom-ai
- Model: https://huggingface.co/chopratejas/kompress-v2-base
- Discord: https://discord.gg/yRmaUNpsPJ
- llms.txt: https://headroom-docs.vercel.app/llms.txt
