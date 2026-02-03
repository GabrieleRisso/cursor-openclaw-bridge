#!/usr/bin/env bash
# Cursor Provider for OpenClaw
# Adds Cursor as a model provider with automatic model discovery

set -e

VERSION="2.1.0"
SCRIPTS_DIR="$HOME/.openclaw/scripts"
CONFIG="$HOME/.openclaw/openclaw.json"
PROXY_REPO="https://github.com/JiuZ-Chn/Cursor-To-OpenAI.git"
PROXY_DIR="$HOME/.openclaw/cursor-proxy"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[cursor]${NC} $1"; }
warn() { echo -e "${YELLOW}[cursor]${NC} $1"; }
error() { echo -e "${RED}[cursor]${NC} $1" >&2; }
info() { echo -e "${CYAN}[cursor]${NC} $1"; }

detect_platform() {
    case "$(uname -s)" in
        Linux*)   OS="linux" ;;
        Darwin*)  OS="macos" ;;
        MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
        *)        OS="unknown" ;;
    esac
    
    if [ "$OS" = "linux" ] && systemctl --user status &>/dev/null 2>&1; then
        SERVICE_MGR="systemd"
    elif [ "$OS" = "macos" ]; then
        SERVICE_MGR="launchd"
    else
        SERVICE_MGR="pm2"
    fi
}

check_deps() {
    log "Checking dependencies..."
    
    command -v node &>/dev/null || { error "Node.js 18+ required"; exit 1; }
    NODE_VER=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
    [ "$NODE_VER" -lt 18 ] && { error "Node.js 18+ required"; exit 1; }
    log "✓ Node.js $(node -v)"
    
    command -v python3 &>/dev/null || { error "Python 3 required"; exit 1; }
    log "✓ Python $(python3 --version | cut -d' ' -f2)"
    
    command -v jq &>/dev/null || { error "jq required"; exit 1; }
    log "✓ jq"
    
    command -v git &>/dev/null || { error "git required"; exit 1; }
    log "✓ git"
}

# Extract cookie from Cursor or prompt
get_cookie() {
    echo ""
    info "Cursor Authentication"
    
    # Try auto-extract from Cursor data
    for db in "$HOME/.cursor/User/globalStorage/state.vscdb" \
              "$HOME/.config/Cursor/User/globalStorage/state.vscdb" \
              "$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb"; do
        if [ -f "$db" ] && command -v sqlite3 &>/dev/null; then
            local token=$(sqlite3 "$db" "SELECT value FROM ItemTable WHERE key='cursorAuth/accessToken'" 2>/dev/null | tr -d '\n')
            if [ -n "$token" ] && [ "$token" != "null" ]; then
                CURSOR_COOKIE="$token"
                log "✓ Cookie auto-extracted"
                return 0
            fi
        fi
    done
    
    # Manual entry
    echo ""
    echo "To get your cookie:"
    echo "  1. Open Cursor IDE"
    echo "  2. Press F12 → Application → Cookies"
    echo "  3. Copy 'WorkosCursorSessionToken'"
    echo ""
    read -p "Paste cookie: " CURSOR_COOKIE
    [ -z "$CURSOR_COOKIE" ] && { error "Cookie required"; exit 1; }
    log "✓ Cookie received"
}

# Install proxy from upstream
install_proxy() {
    log "Installing proxy..."
    
    if [ -d "$PROXY_DIR/.git" ]; then
        cd "$PROXY_DIR" && git pull --quiet 2>/dev/null || true
    else
        rm -rf "$PROXY_DIR"
        git clone --depth 1 "$PROXY_REPO" "$PROXY_DIR"
    fi
    
    cd "$PROXY_DIR"
    npm install --silent 2>/dev/null
    
    # Patch version to match current Cursor
    local CURSOR_VER=$(ls -t /usr/share/applications/cursor*.desktop 2>/dev/null | head -1 | grep -oP '\d+\.\d+\.\d+' || echo "2.4.27")
    sed -i "s/cursorClientVersion = \"[^\"]*\"/cursorClientVersion = \"$CURSOR_VER\"/g" "$PROXY_DIR/src/routes/v1.js" 2>/dev/null || true
    
    # Add fallback for no-auth model listing
    if ! grep -q "Return static list if no auth" "$PROXY_DIR/src/routes/v1.js" 2>/dev/null; then
        sed -i '/router.get("\/models"/,/try{/ {
            /try{/a\
    let bearerToken = req.headers.authorization?.replace('\''Bearer '\'', '\'''\'') || process.env.CURSOR_COOKIE || '\'''\'';\
    if (!bearerToken) {\
      return res.json({object: "list", data: [\
        {id: "composer-1", object: "model", owned_by: "cursor"},\
        {id: "claude-4.5-opus-high", object: "model", owned_by: "cursor"},\
        {id: "claude-4.5-sonnet", object: "model", owned_by: "cursor"},\
        {id: "gpt-5.2", object: "model", owned_by: "cursor"},\
        {id: "gemini-3-pro", object: "model", owned_by: "cursor"}\
      ]});\
    }
        }' "$PROXY_DIR/src/routes/v1.js" 2>/dev/null || true
    fi
    
    log "✓ Proxy installed"
}

# Create model sync script
create_model_sync() {
    mkdir -p "$SCRIPTS_DIR"
    
    cat > "$SCRIPTS_DIR/cursor_model_sync.py" << 'SYNCEOF'
#!/usr/bin/env python3
"""Auto-sync Cursor models to OpenClaw config."""
import json, subprocess, re
from pathlib import Path
from datetime import datetime

CONFIG = Path.home() / ".openclaw" / "openclaw.json"
PROXY = "http://127.0.0.1:3010/v1/models"

RULES = {
    "reasoning": ["thinking", "opus.*high", "opus", "xhigh", "max"],
    "context": {"claude": 200000, "gpt-5.2": 272000, "gpt-5.1": 200000, "gpt-5-mini": 128000, 
                "gemini": 1000000, "composer": 128000, "default": 128000},
    "tokens": {"opus": 16384, "sonnet": 8192, "haiku": 4096, "default": 8192},
    "aliases": {
        "composer-1": "fast", "default": "auto",
        "claude-4.5-opus-high": "opus", "claude-4.5-opus-high-thinking": "opus-think",
        "claude-4.5-sonnet": "sonnet", "claude-4.5-sonnet-thinking": "sonnet-think",
        "claude-4.5-haiku": "haiku", "claude-4.5-haiku-thinking": "haiku-think",
        "claude-4-sonnet": "claude4", "claude-4-sonnet-thinking": "claude4-think",
        "gpt-5.2": "gpt", "gpt-5.2-high": "gpt-hi", "gpt-5.2-codex": "codex",
        "gpt-5-mini": "mini", "gpt-5.1-codex-max": "max",
        "gemini-3-pro": "gemini", "gemini-3-flash": "flash",
        "grok-code-fast-1": "grok", "kimi-k2-instruct": "kimi"
    }
}

def infer(m):
    ml = m.lower()
    reasoning = any(re.search(p, ml) for p in RULES["reasoning"])
    ctx = next((v for k,v in RULES["context"].items() if k in ml), RULES["context"]["default"])
    tok = next((v for k,v in RULES["tokens"].items() if k in ml), RULES["tokens"]["default"])
    return {"id": m, "name": m.replace("-", " ").title(), "reasoning": reasoning,
            "input": ["text"], "cost": {"input": 0, "output": 0},
            "contextWindow": ctx, "maxTokens": tok}

def fetch():
    try:
        r = subprocess.run(["curl", "-s", PROXY], capture_output=True, text=True, timeout=10)
        return [m["id"] for m in json.loads(r.stdout).get("data", [])] if r.returncode == 0 else []
    except: return []

def sync():
    models = fetch()
    if not models or not CONFIG.exists(): return print("No models or config")
    
    cfg = json.loads(CONFIG.read_text())
    cfg.setdefault("models", {}).setdefault("providers", {}).setdefault("cursor", {})
    cfg["models"]["providers"]["cursor"]["models"] = [infer(m) for m in models if m != "default"]
    cfg["models"]["providers"]["cursor"]["baseUrl"] = "http://127.0.0.1:3010/v1"
    cfg["models"]["providers"]["cursor"]["api"] = "openai-completions"
    
    cfg.setdefault("agents", {}).setdefault("defaults", {}).setdefault("models", {})
    for m in models:
        if m in RULES["aliases"]:
            cfg["agents"]["defaults"]["models"][f"cursor/{m}"] = {"alias": RULES["aliases"][m]}
    
    CONFIG.write_text(json.dumps(cfg, indent=2))
    print(f"Synced {len(models)} models")

if __name__ == "__main__": sync()
SYNCEOF

    chmod +x "$SCRIPTS_DIR/cursor_model_sync.py"
    log "✓ Model sync script created"
}

# Save config
save_config() {
    mkdir -p "$PROXY_DIR"
    echo "CURSOR_COOKIE=$CURSOR_COOKIE" > "$PROXY_DIR/.env"
    chmod 600 "$PROXY_DIR/.env"
    
    # Update OpenClaw config with basic provider
    if [ -f "$CONFIG" ]; then
        jq --arg cookie "$CURSOR_COOKIE" '
            .models.mode = "merge" |
            .models.providers.cursor.baseUrl = "http://127.0.0.1:3010/v1" |
            .models.providers.cursor.apiKey = $cookie |
            .models.providers.cursor.api = "openai-completions"
        ' "$CONFIG" > /tmp/oc.json && mv /tmp/oc.json "$CONFIG"
        log "✓ Config updated"
    fi
}

# Setup systemd service
setup_systemd() {
    mkdir -p "$HOME/.config/systemd/user"
    cat > "$HOME/.config/systemd/user/cursor-provider.service" << EOF
[Unit]
Description=Cursor Provider
After=network.target

[Service]
Type=simple
WorkingDirectory=$PROXY_DIR
EnvironmentFile=$PROXY_DIR/.env
ExecStart=$(which node) $PROXY_DIR/src/app.js
Restart=always
RestartSec=5
Environment=PORT=3010

[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable cursor-provider 2>/dev/null || true
    log "✓ Systemd service configured"
}

# Setup launchd service
setup_launchd() {
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$HOME/Library/LaunchAgents/com.cursor-provider.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.cursor-provider</string>
    <key>ProgramArguments</key>
    <array>
        <string>$(which node)</string>
        <string>$PROXY_DIR/src/app.js</string>
    </array>
    <key>WorkingDirectory</key><string>$PROXY_DIR</string>
    <key>EnvironmentVariables</key>
    <dict><key>PORT</key><string>3010</string></dict>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
</dict>
</plist>
EOF
    log "✓ Launchd service configured"
}

# Setup pm2
setup_pm2() {
    command -v pm2 &>/dev/null || npm install -g pm2 --silent
    cat > "$PROXY_DIR/ecosystem.config.js" << EOF
module.exports = {
  apps: [{
    name: 'cursor-provider',
    script: 'src/app.js',
    cwd: '$PROXY_DIR',
    env: { PORT: 3010 },
    autorestart: true
  }]
};
EOF
    log "✓ PM2 config created"
}

# Start service
start_service() {
    case "$SERVICE_MGR" in
        systemd)
            systemctl --user start cursor-provider
            log "✓ Service started"
            ;;
        launchd)
            launchctl load "$HOME/Library/LaunchAgents/com.cursor-provider.plist" 2>/dev/null || true
            log "✓ Service started"
            ;;
        pm2)
            cd "$PROXY_DIR" && pm2 start ecosystem.config.js 2>/dev/null || true
            pm2 save 2>/dev/null || true
            log "✓ Service started"
            ;;
    esac
}

# Run model sync
run_sync() {
    sleep 3  # Wait for proxy to start
    if curl -s http://127.0.0.1:3010/v1/models | grep -q 'object'; then
        python3 "$SCRIPTS_DIR/cursor_model_sync.py"
        log "✓ Models synced"
    else
        warn "Proxy not ready, run manually: python3 $SCRIPTS_DIR/cursor_model_sync.py"
    fi
}

# Print summary
print_summary() {
    echo ""
    echo "=========================================="
    echo "  Cursor Provider Installed"
    echo "=========================================="
    echo ""
    echo "  Endpoint: http://127.0.0.1:3010/v1"
    echo ""
    echo "  Commands:"
    echo "    /model opus    - Claude 4.5 Opus"
    echo "    /model fast    - Composer (unlimited)"
    echo "    /model gpt     - GPT-5.2"
    echo "    /model gemini  - Gemini 3 Pro"
    echo ""
    echo "  Re-sync models:"
    echo "    python3 ~/.openclaw/scripts/cursor_model_sync.py"
    echo ""
    echo "  Restart:"
    case "$SERVICE_MGR" in
        systemd) echo "    systemctl --user restart cursor-provider" ;;
        launchd) echo "    launchctl kickstart -k gui/\$(id -u)/com.cursor-provider" ;;
        pm2)     echo "    pm2 restart cursor-provider" ;;
    esac
    echo ""
}

main() {
    echo ""
    echo "=========================================="
    echo "  Cursor Provider v$VERSION"
    echo "=========================================="
    echo ""
    
    detect_platform
    log "Platform: $OS ($SERVICE_MGR)"
    
    check_deps
    get_cookie
    install_proxy
    create_model_sync
    save_config
    
    case "$SERVICE_MGR" in
        systemd) setup_systemd ;;
        launchd) setup_launchd ;;
        pm2)     setup_pm2 ;;
    esac
    
    start_service
    run_sync
    print_summary
}

main "$@"
