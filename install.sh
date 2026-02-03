#!/usr/bin/env bash
# Cursor-OpenClaw Bridge Installer
# Installs the Cursor proxy and configures OpenClaw
# Cross-platform: Linux (systemd), macOS (launchd), Windows (pm2)

set -e

VERSION="1.0.0"
PROXY_REPO="https://github.com/JiuZ-Chn/Cursor-To-OpenAI.git"
INSTALL_DIR="$HOME/.openclaw/cursor-proxy"
SCRIPTS_DIR="$HOME/.openclaw/scripts"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[cursor-proxy]${NC} $1"; }
warn() { echo -e "${YELLOW}[cursor-proxy]${NC} $1"; }
error() { echo -e "${RED}[cursor-proxy]${NC} $1" >&2; }

# Detect OS and service manager
detect_platform() {
    case "$(uname -s)" in
        Linux*)   OS="linux" ;;
        Darwin*)  OS="macos" ;;
        MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
        *)        OS="unknown" ;;
    esac

    if [ "$OS" = "linux" ]; then
        if systemctl --user status &>/dev/null 2>&1; then
            SERVICE_MGR="systemd"
        else
            SERVICE_MGR="pm2"
        fi
    elif [ "$OS" = "macos" ]; then
        SERVICE_MGR="launchd"
    else
        SERVICE_MGR="pm2"
    fi
}

# Check dependencies
check_deps() {
    log "Checking dependencies..."
    
    if ! command -v node &>/dev/null; then
        error "Node.js not found. Install Node.js 18+ first."
        exit 1
    fi
    
    NODE_VER=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
    [ "$NODE_VER" -lt 18 ] && { error "Node.js 18+ required"; exit 1; }
    log "✓ Node.js $(node -v)"
    
    if ! command -v git &>/dev/null; then
        error "git not found"
        exit 1
    fi
    log "✓ git"
    
    if command -v openclaw &>/dev/null; then
        log "✓ OpenClaw $(openclaw --version 2>/dev/null | head -1 || echo 'installed')"
    else
        warn "OpenClaw not found (optional for standalone mode)"
    fi
}

# Install proxy
install_proxy() {
    log "Installing Cursor-To-OpenAI proxy..."
    
    mkdir -p "$INSTALL_DIR"
    
    if [ -d "$INSTALL_DIR/.git" ]; then
        log "Updating existing installation..."
        cd "$INSTALL_DIR" && git pull --quiet
    else
        log "Cloning proxy repository..."
        git clone --depth 1 "$PROXY_REPO" "$INSTALL_DIR"
    fi
    
    cd "$INSTALL_DIR"
    npm install --silent 2>/dev/null
    
    log "✓ Proxy installed to $INSTALL_DIR"
}

# Create login script
create_login_script() {
    mkdir -p "$SCRIPTS_DIR"
    
    cat > "$SCRIPTS_DIR/cursor-login.sh" << 'LOGINEOF'
#!/usr/bin/env bash
# Cursor Login Script - Extract session cookie

set -e

echo "=========================================="
echo "  Cursor Login"
echo "=========================================="
echo ""
echo "1. Open Cursor IDE and sign in"
echo "2. Open DevTools (F12) → Application → Cookies"
echo "3. Find 'WorkosCursorSessionToken' cookie"
echo "4. Copy the full value"
echo ""
read -p "Paste cookie value: " COOKIE

if [ -z "$COOKIE" ]; then
    echo "Error: No cookie provided"
    exit 1
fi

# Save to env file
mkdir -p ~/.openclaw/cursor-proxy
echo "CURSOR_COOKIE=$COOKIE" > ~/.openclaw/cursor-proxy/.env
chmod 600 ~/.openclaw/cursor-proxy/.env

# Update OpenClaw config if jq available
if command -v jq &>/dev/null && [ -f ~/.openclaw/openclaw.json ]; then
    jq --arg cookie "$COOKIE" '
        .models.providers.cursor.apiKey = $cookie
    ' ~/.openclaw/openclaw.json > /tmp/oc.json && mv /tmp/oc.json ~/.openclaw/openclaw.json
    echo "✓ Updated OpenClaw config"
fi

echo ""
echo "✓ Cookie saved to ~/.openclaw/cursor-proxy/.env"
echo ""
echo "Next: Start the proxy"
echo "  systemctl --user restart cursor-proxy"
LOGINEOF

    chmod +x "$SCRIPTS_DIR/cursor-login.sh"
    log "✓ Login script: $SCRIPTS_DIR/cursor-login.sh"
}

# Setup systemd service (Linux)
setup_systemd() {
    local SERVICE_DIR="$HOME/.config/systemd/user"
    mkdir -p "$SERVICE_DIR"
    
    cat > "$SERVICE_DIR/cursor-proxy.service" << EOF
[Unit]
Description=Cursor-To-OpenAI Proxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
EnvironmentFile=$HOME/.openclaw/cursor-proxy/.env
ExecStart=$(which node) $INSTALL_DIR/src/app.js
Restart=always
RestartSec=10
Environment=NODE_ENV=production
Environment=PORT=3010

[Install]
WantedBy=default.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable cursor-proxy.service 2>/dev/null || true
    log "✓ Systemd service configured"
}

# Setup launchd (macOS)
setup_launchd() {
    local PLIST_DIR="$HOME/Library/LaunchAgents"
    mkdir -p "$PLIST_DIR"
    
    cat > "$PLIST_DIR/com.cursor-proxy.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.cursor-proxy</string>
    <key>ProgramArguments</key>
    <array>
        <string>$(which node)</string>
        <string>$INSTALL_DIR/src/app.js</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$INSTALL_DIR</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PORT</key>
        <string>3010</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/.openclaw/cursor-proxy/proxy.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/.openclaw/cursor-proxy/proxy-error.log</string>
</dict>
</plist>
EOF

    log "✓ Launchd service configured"
}

# Setup pm2 (cross-platform fallback)
setup_pm2() {
    if ! command -v pm2 &>/dev/null; then
        log "Installing pm2..."
        npm install -g pm2 --silent
    fi
    
    cat > "$INSTALL_DIR/ecosystem.config.js" << EOF
module.exports = {
  apps: [{
    name: 'cursor-proxy',
    script: 'src/app.js',
    cwd: '$INSTALL_DIR',
    env: { NODE_ENV: 'production', PORT: 3010 },
    autorestart: true,
    max_memory_restart: '200M'
  }]
};
EOF

    log "✓ PM2 config created"
}

# Configure OpenClaw
configure_openclaw() {
    if ! command -v jq &>/dev/null; then
        warn "jq not found - manual OpenClaw config required"
        return
    fi
    
    local CONFIG="$HOME/.openclaw/openclaw.json"
    [ ! -f "$CONFIG" ] && return
    
    log "Configuring OpenClaw..."
    
    # Add cursor provider if not exists
    if ! jq -e '.models.providers.cursor' "$CONFIG" &>/dev/null; then
        jq '
            .models.mode = "merge" |
            .models.providers.cursor = {
                "baseUrl": "http://127.0.0.1:3010/v1",
                "apiKey": "",
                "api": "openai-completions",
                "models": [
                    {"id": "composer-1", "name": "Composer-1 (Fast)", "reasoning": false, "input": ["text"], "cost": {"input": 0, "output": 0}, "contextWindow": 128000, "maxTokens": 8192},
                    {"id": "claude-4.5-opus-high", "name": "Claude 4.5 Opus", "reasoning": true, "input": ["text"], "cost": {"input": 0, "output": 0}, "contextWindow": 200000, "maxTokens": 8192},
                    {"id": "claude-4.5-sonnet", "name": "Claude 4.5 Sonnet", "reasoning": false, "input": ["text"], "cost": {"input": 0, "output": 0}, "contextWindow": 200000, "maxTokens": 8192},
                    {"id": "gpt-5.2", "name": "GPT-5.2", "reasoning": false, "input": ["text"], "cost": {"input": 0, "output": 0}, "contextWindow": 272000, "maxTokens": 8192},
                    {"id": "gemini-3-pro", "name": "Gemini 3 Pro", "reasoning": false, "input": ["text"], "cost": {"input": 0, "output": 0}, "contextWindow": 200000, "maxTokens": 8192}
                ]
            } |
            .agents.defaults.models["cursor/composer-1"] = {"alias": "fast"} |
            .agents.defaults.models["cursor/claude-4.5-opus-high"] = {"alias": "opus"} |
            .agents.defaults.models["cursor/claude-4.5-sonnet"] = {"alias": "sonnet"} |
            .agents.defaults.models["cursor/gpt-5.2"] = {"alias": "gpt"} |
            .agents.defaults.models["cursor/gemini-3-pro"] = {"alias": "gemini"}
        ' "$CONFIG" > /tmp/oc.json && mv /tmp/oc.json "$CONFIG"
        log "✓ Cursor provider added to OpenClaw config"
    else
        log "✓ Cursor provider already configured"
    fi
}

# Install skill to workspace
install_skill() {
    local SKILL_DIR="$HOME/.openclaw/workspace/skills/cursor-proxy"
    mkdir -p "$SKILL_DIR"
    
    # Copy skill if running from repo
    if [ -f "$(dirname "$0")/skills/cursor-proxy/SKILL.md" ]; then
        cp "$(dirname "$0")/skills/cursor-proxy/SKILL.md" "$SKILL_DIR/"
        log "✓ Skill installed to workspace"
    fi
}

# Print next steps
print_summary() {
    echo ""
    echo "=========================================="
    echo "  Installation Complete!"
    echo "=========================================="
    echo ""
    echo "Next steps:"
    echo ""
    echo "  1. Login to Cursor:"
    echo "     $SCRIPTS_DIR/cursor-login.sh"
    echo ""
    
    case "$SERVICE_MGR" in
        systemd)
            echo "  2. Start the proxy:"
            echo "     systemctl --user start cursor-proxy"
            echo ""
            echo "  3. Check status:"
            echo "     systemctl --user status cursor-proxy"
            ;;
        launchd)
            echo "  2. Start the proxy:"
            echo "     launchctl load ~/Library/LaunchAgents/com.cursor-proxy.plist"
            ;;
        pm2)
            echo "  2. Start the proxy:"
            echo "     pm2 start $INSTALL_DIR/ecosystem.config.js"
            ;;
    esac
    
    echo ""
    echo "  4. Test the proxy:"
    echo "     curl http://127.0.0.1:3010/v1/models"
    echo ""
    echo "  5. Restart OpenClaw:"
    echo "     systemctl --user restart openclaw-gateway"
    echo ""
    echo "Documentation: https://github.com/GabrieleRisso/cursor-openclaw-bridge"
    echo ""
}

# Main
main() {
    echo ""
    echo "=========================================="
    echo "  Cursor-OpenClaw Bridge v$VERSION"
    echo "=========================================="
    echo ""
    
    detect_platform
    log "Platform: $OS ($SERVICE_MGR)"
    
    check_deps
    install_proxy
    create_login_script
    
    case "$SERVICE_MGR" in
        systemd) setup_systemd ;;
        launchd) setup_launchd ;;
        pm2)     setup_pm2 ;;
    esac
    
    configure_openclaw
    install_skill
    print_summary
}

main "$@"
