# Cursor-OpenClaw Bridge

Route your OpenClaw AI through Cursor IDE subscription ($20/month unlimited access to Claude, GPT, Gemini).

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐     ┌────────────┐
│  WhatsApp   │────▶│   OpenClaw   │────▶│ Cursor Proxy │────▶│ Cursor API │
│  Terminal   │     │   Gateway    │     │   :3010      │     │ (Claude+)  │
└─────────────┘     └──────────────┘     └──────────────┘     └────────────┘
```

## Features

- **Flat rate**: $20/month Cursor subscription vs per-token API costs
- **Multiple models**: Claude 4.5, GPT-5.2, Gemini 3 via single subscription
- **Auto-failover**: Falls back to Anthropic API if proxy unavailable
- **Cross-platform**: Linux (systemd), macOS (launchd), Windows (pm2)
- **ClawHub ready**: Install as OpenClaw skill

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/GabrieleRisso/cursor-openclaw-bridge/main/install.sh | bash
```

Or via ClawHub:

```bash
clawhub install cursor-proxy
```

## Setup

1. **Install the proxy**:
   ```bash
   ./install.sh
   ```

2. **Login to Cursor** (get session cookie):
   ```bash
   ~/.openclaw/scripts/cursor-login.sh
   ```

3. **Start the proxy**:
   ```bash
   systemctl --user start cursor-proxy
   ```

4. **Restart OpenClaw**:
   ```bash
   systemctl --user restart openclaw-gateway
   ```

## Available Models

| Alias | Model | Use Case |
|-------|-------|----------|
| `fast` | cursor/composer-1 | Quick tasks, unlimited |
| `opus` | cursor/claude-4.5-opus-high | Best quality |
| `sonnet` | cursor/claude-4.5-sonnet | Balanced |
| `gpt` | cursor/gpt-5.2 | OpenAI alternative |
| `gemini` | cursor/gemini-3-pro | Google AI |

Switch models via WhatsApp: `/model opus`

## Cron Jobs (Optional)

Set up automated monitoring:

```bash
./scripts/setup-cron.sh +1234567890
```

Creates:
- **System Monitor**: Every 30min, alerts on low battery/high temp
- **Daily Summary**: 8am daily status report
- **Proxy Health**: Hourly health check

## Configuration

The installer adds to `~/.openclaw/openclaw.json`:

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

| Path | Description |
|------|-------------|
| `~/.openclaw/cursor-proxy/` | Proxy installation |
| `~/.openclaw/cursor-proxy/.env` | Session cookie |
| `~/.openclaw/scripts/cursor-login.sh` | Login script |
| `~/.config/systemd/user/cursor-proxy.service` | Service file |

## Commands

| Command | Description |
|---------|-------------|
| `/cursor` | Show status |
| `/model list` | List models |
| `/model <alias>` | Switch model |

## Troubleshooting

**Proxy not responding:**
```bash
systemctl --user restart cursor-proxy
journalctl --user -u cursor-proxy -f
```

**Cookie expired:**
```bash
~/.openclaw/scripts/cursor-login.sh
systemctl --user restart cursor-proxy
```

**Test proxy:**
```bash
curl http://127.0.0.1:3010/v1/models
```

## Disclaimer

⚠️ Using Cursor's internal API may violate their ToS. For personal/educational use only.

## License

MIT - See [LICENSE](LICENSE)

## Contributing

PRs welcome! This skill is designed for integration into official OpenClaw/ClawHub.

## Credits

- [JiuZ-Chn/Cursor-To-OpenAI](https://github.com/JiuZ-Chn/Cursor-To-OpenAI) - Base proxy
- [OpenClaw](https://openclaw.ai) - AI agent framework
