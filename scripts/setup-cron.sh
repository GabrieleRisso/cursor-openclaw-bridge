#!/usr/bin/env bash
# Setup OpenClaw cron jobs for system monitoring
# Uses OpenClaw's native cron system

set -e

PHONE="${1:-+393455049699}"

echo "Setting up OpenClaw cron jobs..."

# Battery/system check every 30 minutes (isolated, uses composer-1 for cheap)
openclaw cron add \
    --name "System Monitor" \
    --cron "*/30 * * * *" \
    --tz "Europe/Rome" \
    --session isolated \
    --model "cursor/composer-1" \
    --message "Quick system check. Run: python3 ~/.openclaw/scripts/battery_monitor.py --quick. If battery <20% or temp >80°C, alert via WhatsApp with compact message." \
    --deliver \
    --channel whatsapp \
    --to "$PHONE" \
    --post-prefix "🔋" 2>/dev/null || echo "System Monitor job may already exist"

# Daily summary at 8am (uses opus for quality)
openclaw cron add \
    --name "Daily Summary" \
    --cron "0 8 * * *" \
    --tz "Europe/Rome" \
    --session isolated \
    --model "cursor/claude-4.5-opus-high" \
    --message "Generate daily summary: battery status, token usage from logs, any alerts. Keep compact for WhatsApp." \
    --deliver \
    --channel whatsapp \
    --to "$PHONE" \
    --post-prefix "📊" 2>/dev/null || echo "Daily Summary job may already exist"

# Proxy health check every hour (cheap model)
openclaw cron add \
    --name "Proxy Health" \
    --cron "0 * * * *" \
    --tz "Europe/Rome" \
    --session isolated \
    --model "cursor/composer-1" \
    --message "Check cursor proxy health: curl -s http://127.0.0.1:3010/v1/models. If fails, try restart. Only alert if down >5 min." \
    --post-prefix "⚡" 2>/dev/null || echo "Proxy Health job may already exist"

echo ""
echo "Cron jobs configured. View with: openclaw cron list"
