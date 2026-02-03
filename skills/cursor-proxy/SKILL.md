---
name: cursor
description: Cursor IDE provider - access Claude, GPT, Gemini via $20/month subscription
user-invocable: true
metadata: {"openclaw": {"emoji": "⚡", "requires": {"bins": ["node", "curl"]}, "homepage": "https://github.com/GabrieleRisso/cursor-openclaw-bridge"}}
---

# Cursor Provider

Access Claude 4.5, GPT-5.2, and Gemini via your Cursor IDE subscription.

## Setup

```bash
curl -fsSL https://raw.githubusercontent.com/GabrieleRisso/cursor-openclaw-bridge/main/install.sh | bash
```

## Models

| Alias | Model | Best For |
|-------|-------|----------|
| `fast` | composer-1 | Quick tasks (unlimited) |
| `opus` | claude-4.5-opus-high | Complex reasoning |
| `sonnet` | claude-4.5-sonnet | Balanced |
| `haiku` | claude-4.5-haiku | Fast responses |
| `gpt` | gpt-5.2 | OpenAI tasks |
| `codex` | gpt-5.2-codex | Code generation |
| `gemini` | gemini-3-pro | Google AI |

## Commands

- `/model list` - Show available models
- `/model <alias>` - Switch model (e.g., `/model opus`)
- `/cursor` - Provider status

## Status

```bash
curl http://127.0.0.1:3010/health
systemctl --user status cursor-provider
```

## Refresh Cookie

```bash
~/.openclaw/scripts/cursor-login.sh
systemctl --user restart cursor-provider
```
