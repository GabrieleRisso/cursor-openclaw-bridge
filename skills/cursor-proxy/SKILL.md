---
name: cursor-proxy
description: Route OpenClaw through Cursor IDE subscription - access Claude, GPT, Gemini via $20/month flat rate
user-invocable: true
metadata: {"openclaw": {"emoji": "⚡", "requires": {"bins": ["node", "curl"]}, "primaryEnv": "CURSOR_COOKIE", "homepage": "https://github.com/GabrieleRisso/cursor-openclaw-bridge", "install": [{"id": "npm", "kind": "node", "package": "cursor-to-openai", "global": true, "bins": ["cursor-proxy"], "label": "Install Cursor Proxy (npm)"}]}}
---

# Cursor Proxy

Route OpenClaw AI requests through your Cursor IDE subscription ($20/month unlimited).

## Setup

1. Run the installer:
```bash
curl -fsSL https://raw.githubusercontent.com/GabrieleRisso/cursor-openclaw-bridge/main/install.sh | bash
```

2. Login to Cursor:
```bash
~/.openclaw/scripts/cursor-login.sh
```

3. Start the proxy:
```bash
systemctl --user start cursor-proxy
```

## Commands

- `/cursor` - Show proxy status and available models
- `/cursor models` - List all models with aliases
- `/cursor switch <alias>` - Change primary model

## Available Models

| Alias | Model | Use Case |
|-------|-------|----------|
| `fast` | composer-1 | Quick, unlimited |
| `opus` | claude-4.5-opus-high | Best quality |
| `sonnet` | claude-4.5-sonnet | Balanced |
| `gpt` | gpt-5.2 | OpenAI |
| `gemini` | gemini-3-pro | Google |

## Status Check

```bash
curl -s http://127.0.0.1:3010/v1/models | head -5
systemctl --user is-active cursor-proxy
```

## Switch Model

Use `/model <alias>` or:

```bash
jq '.agents.defaults.model.primary = "cursor/MODEL"' ~/.openclaw/openclaw.json > /tmp/oc.json && mv /tmp/oc.json ~/.openclaw/openclaw.json
systemctl --user restart openclaw-gateway
```

## Troubleshooting

- **Proxy down**: `systemctl --user restart cursor-proxy`
- **Auth error**: Re-run `~/.openclaw/scripts/cursor-login.sh`
- **Logs**: `journalctl --user -u cursor-proxy -f`

## Configuration

The skill adds a `cursor` provider to `~/.openclaw/openclaw.json`:

```json
{
  "models": {
    "providers": {
      "cursor": {
        "baseUrl": "http://127.0.0.1:3010/v1",
        "apiKey": "${CURSOR_COOKIE}",
        "api": "openai-completions"
      }
    }
  }
}
```

## Files

- Proxy: `~/.openclaw/cursor-proxy/`
- Service: `~/.config/systemd/user/cursor-proxy.service`
- Cookie: `~/.openclaw/cursor-proxy/.env`
