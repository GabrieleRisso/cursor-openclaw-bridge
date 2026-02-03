# Cursor Provider for OpenClaw

Add Cursor as a model provider in OpenClaw - access Claude 4.5, GPT-5.2, and Gemini through your $20/month Cursor subscription.

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/GabrieleRisso/cursor-openclaw-bridge/main/install.sh | bash
```

The installer will:
1. Let you select your preferred model
2. Guide you through authentication
3. Configure OpenClaw automatically
4. Start the provider service

## Available Models

| Alias | Model | Use Case |
|-------|-------|----------|
| `fast` | cursor/composer-1 | Quick tasks, unlimited |
| `opus` | cursor/claude-4.5-opus-high | Best quality |
| `sonnet` | cursor/claude-4.5-sonnet | Balanced |
| `haiku` | cursor/claude-4.5-haiku | Fast |
| `gpt` | cursor/gpt-5.2 | OpenAI |
| `codex` | cursor/gpt-5.2-codex | Code |
| `gemini` | cursor/gemini-3-pro | Google AI |

## Usage

Switch models via WhatsApp or chat:
```
/model opus
/model fast
/model gpt
```

## Platform Support

- **Linux**: systemd service
- **macOS**: launchd service  
- **Windows**: pm2 process

## Configuration

The installer adds Cursor as a provider in `~/.openclaw/openclaw.json`:

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

## Files

| Path | Description |
|------|-------------|
| `~/.openclaw/providers/cursor/` | Provider installation |
| `~/.openclaw/providers/cursor/.env` | Authentication |
| `~/.config/systemd/user/cursor-provider.service` | Service (Linux) |

## Service Management

```bash
# Linux
systemctl --user status cursor-provider
systemctl --user restart cursor-provider

# macOS
launchctl list | grep cursor

# pm2
pm2 status cursor-provider
```

## Troubleshooting

**Provider not responding:**
```bash
curl http://127.0.0.1:3010/health
systemctl --user restart cursor-provider
```

**Re-authenticate:**
```bash
~/.openclaw/scripts/cursor-login.sh
systemctl --user restart cursor-provider
```

## License

MIT
