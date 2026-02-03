# Cursor Provider for OpenClaw

Use your Cursor Pro subscription as an AI provider in OpenClaw. Access all available models through a unified OpenAI-compatible API.

## Features

- **Automatic Model Discovery** - Syncs all available models from your subscription
- **Smart Metadata** - Infers reasoning capability, context windows, and speed tiers
- **Model Aliases** - Quick shortcuts like `/model opus`, `/model fast`
- **Cross-Platform** - Linux (systemd), macOS (launchd), Windows (pm2)
- **Auto-Updates** - Daily sync catches new models automatically

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/GabrieleRisso/cursor-openclaw-bridge/main/install.sh | bash
```

## Requirements

- Cursor Pro/Pro+/Ultra subscription (cursor.com/pricing)
- Node.js 18+
- Python 3
- jq

## Available Models

Models are discovered automatically from your subscription. Common aliases:

| Alias | Model | Description |
|-------|-------|-------------|
| `fast` | composer-1 | Unlimited, quick tasks |
| `opus` | claude-4.5-opus-high | Best quality |
| `sonnet` | claude-4.5-sonnet | Balanced |
| `haiku` | claude-4.5-haiku | Fast |
| `gpt` | gpt-5.2 | OpenAI |
| `codex` | gpt-5.2-codex | Code generation |
| `gemini` | gemini-3-pro | Google AI |
| `flash` | gemini-3-flash | Fast Gemini |

## Usage

Switch models via chat:
```
/model opus     # Use Claude 4.5 Opus
/model fast     # Use Composer-1 (unlimited)
/model gpt      # Use GPT-5.2
```

## Model Sync

Models sync automatically daily. Manual sync:
```bash
python3 ~/.openclaw/scripts/cursor_model_sync.py
```

## Service Management

```bash
# Linux
systemctl --user status cursor-provider
systemctl --user restart cursor-provider

# macOS
launchctl list | grep cursor

# Check logs
journalctl --user -u cursor-provider -f
```

## Configuration

Provider settings in `~/.openclaw/openclaw.json`:
```json
{
  "models": {
    "providers": {
      "cursor": {
        "baseUrl": "http://127.0.0.1:3010/v1",
        "api": "openai-completions"
      }
    }
  }
}
```

## Troubleshooting

**Proxy not responding:**
```bash
curl http://127.0.0.1:3010/v1/models
systemctl --user restart cursor-provider
```

**Update cookie:**
```bash
# Edit and restart
nano ~/.openclaw/cursor-proxy/.env
systemctl --user restart cursor-provider
```

**Version mismatch error:**
The installer auto-patches the client version. If issues persist, check your Cursor version and update manually in `~/.openclaw/cursor-proxy/src/routes/v1.js`.

## Files

| Path | Description |
|------|-------------|
| `~/.openclaw/cursor-proxy/` | Proxy installation |
| `~/.openclaw/cursor-proxy/.env` | Authentication |
| `~/.openclaw/scripts/cursor_model_sync.py` | Model sync script |

## License

MIT - See LICENSE file

---

*This is an independent project. Requires a valid Cursor subscription.*
