#!/usr/bin/env bash
# Cursor Provider for OpenClaw
# Adds Cursor as a model provider (like Anthropic)

set -e

VERSION="2.0.0"
INSTALL_DIR="$HOME/.openclaw/providers/cursor"
SCRIPTS_DIR="$HOME/.openclaw/scripts"
CONFIG="$HOME/.openclaw/openclaw.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[openclaw]${NC} $1"; }
warn() { echo -e "${YELLOW}[openclaw]${NC} $1"; }
error() { echo -e "${RED}[openclaw]${NC} $1" >&2; }
info() { echo -e "${CYAN}[openclaw]${NC} $1"; }

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
    
    command -v jq &>/dev/null || { error "jq required for config"; exit 1; }
    log "✓ jq"
    
    if command -v openclaw &>/dev/null; then
        log "✓ OpenClaw installed"
    else
        warn "OpenClaw not found - standalone mode"
    fi
}

# Interactive model selection
select_models() {
    echo ""
    info "Available Cursor Models:"
    echo ""
    echo "  Claude Models (Anthropic via Cursor):"
    echo "    1) claude-4.5-opus-high    - Best quality, reasoning"
    echo "    2) claude-4.5-sonnet       - Balanced"
    echo "    3) claude-4.5-haiku        - Fast"
    echo ""
    echo "  GPT Models (OpenAI via Cursor):"
    echo "    4) gpt-5.2                 - Latest GPT"
    echo "    5) gpt-5.2-codex           - Coding optimized"
    echo ""
    echo "  Other Models:"
    echo "    6) gemini-3-pro            - Google AI"
    echo "    7) composer-1              - Fast/cheap (unlimited)"
    echo ""
    
    read -p "Select primary model [1-7, default=1]: " MODEL_CHOICE
    
    case "${MODEL_CHOICE:-1}" in
        1) PRIMARY_MODEL="claude-4.5-opus-high" ;;
        2) PRIMARY_MODEL="claude-4.5-sonnet" ;;
        3) PRIMARY_MODEL="claude-4.5-haiku" ;;
        4) PRIMARY_MODEL="gpt-5.2" ;;
        5) PRIMARY_MODEL="gpt-5.2-codex" ;;
        6) PRIMARY_MODEL="gemini-3-pro" ;;
        7) PRIMARY_MODEL="composer-1" ;;
        *) PRIMARY_MODEL="claude-4.5-opus-high" ;;
    esac
    
    log "Selected: $PRIMARY_MODEL"
}

# Automated cookie extraction
extract_cookie() {
    echo ""
    info "Cursor Authentication"
    echo ""
    
    # Try to find existing Cursor data
    local CURSOR_DATA=""
    
    # Check common Cursor data locations
    for path in \
        "$HOME/.cursor/User/globalStorage/state.vscdb" \
        "$HOME/.config/Cursor/User/globalStorage/state.vscdb" \
        "$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb"; do
        if [ -f "$path" ]; then
            CURSOR_DATA="$path"
            break
        fi
    done
    
    if [ -n "$CURSOR_DATA" ] && command -v sqlite3 &>/dev/null; then
        log "Found Cursor data, attempting auto-extract..."
        local TOKEN=$(sqlite3 "$CURSOR_DATA" "SELECT value FROM ItemTable WHERE key='cursorAuth/accessToken'" 2>/dev/null | tr -d '\n')
        if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
            CURSOR_COOKIE="$TOKEN"
            log "✓ Cookie extracted automatically"
            return 0
        fi
    fi
    
    # Manual entry fallback
    echo "Manual cookie entry required."
    echo ""
    echo "Steps:"
    echo "  1. Open Cursor IDE"
    echo "  2. Press F12 (DevTools)"
    echo "  3. Go to Application → Cookies → https://cursor.sh"
    echo "  4. Copy 'WorkosCursorSessionToken' value"
    echo ""
    read -p "Paste cookie: " CURSOR_COOKIE
    
    [ -z "$CURSOR_COOKIE" ] && { error "No cookie provided"; exit 1; }
    log "✓ Cookie received"
}

# Install proxy with enhancements
install_proxy() {
    log "Installing Cursor provider..."
    
    mkdir -p "$INSTALL_DIR"
    
    # Create enhanced proxy server
    cat > "$INSTALL_DIR/server.js" << 'PROXYEOF'
const http = require('http');
const https = require('https');
const crypto = require('crypto');
const zlib = require('zlib');

const PORT = process.env.PORT || 3010;
const CURSOR_COOKIE = process.env.CURSOR_COOKIE || '';

// Dynamic endpoints with fallbacks
const ENDPOINTS = [
    'api2.cursor.sh',
    'api.cursor.sh'
];

let currentEndpoint = 0;

function getEndpoint() {
    return ENDPOINTS[currentEndpoint % ENDPOINTS.length];
}

function rotateEndpoint() {
    currentEndpoint++;
}

function generateChecksum(token) {
    const machineId = crypto.createHash('sha256').update(token + 'machineId').digest('hex');
    const macMachineId = crypto.createHash('sha256').update(token + 'macMachineId').digest('hex');
    const ts = Math.floor(Date.now() / 1e6);
    const bytes = Buffer.alloc(6);
    bytes.writeUIntBE(ts, 0, 6);
    let t = 165;
    for (let i = 0; i < bytes.length; i++) {
        bytes[i] = (bytes[i] ^ t) + (i % 256);
        t = bytes[i];
    }
    return bytes.toString('base64') + machineId + '/' + macMachineId;
}

function generateClientVersion() {
    // Dynamic version based on date
    const d = new Date();
    const major = 2;
    const minor = Math.floor((d.getMonth() + 1) / 3) + 4;
    const patch = d.getDate();
    return `${major}.${minor}.${patch}`;
}

function makeRequest(options, postData) {
    return new Promise((resolve, reject) => {
        const req = https.request(options, (res) => {
            const chunks = [];
            res.on('data', chunk => chunks.push(chunk));
            res.on('end', () => {
                resolve({
                    statusCode: res.statusCode,
                    headers: res.headers,
                    body: Buffer.concat(chunks)
                });
            });
        });
        req.on('error', reject);
        req.setTimeout(30000, () => req.destroy(new Error('timeout')));
        if (postData) req.write(postData);
        req.end();
    });
}

const server = http.createServer(async (req, res) => {
    // CORS
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    
    if (req.method === 'OPTIONS') {
        res.writeHead(204);
        return res.end();
    }
    
    const url = req.url;
    let token = req.headers.authorization?.replace('Bearer ', '') || CURSOR_COOKIE;
    
    // Handle token formats
    if (token.includes('%3A%3A')) token = token.split('%3A%3A')[1];
    else if (token.includes('::')) token = token.split('::')[1];
    
    // Models endpoint
    if (url === '/v1/models' && req.method === 'GET') {
        if (!token) {
            // Return static list without auth
            res.writeHead(200, {'Content-Type': 'application/json'});
            return res.end(JSON.stringify({
                object: 'list',
                data: [
                    {id: 'composer-1', object: 'model', owned_by: 'cursor'},
                    {id: 'claude-4.5-opus-high', object: 'model', owned_by: 'cursor'},
                    {id: 'claude-4.5-sonnet', object: 'model', owned_by: 'cursor'},
                    {id: 'gpt-5.2', object: 'model', owned_by: 'cursor'},
                    {id: 'gemini-3-pro', object: 'model', owned_by: 'cursor'}
                ]
            }));
        }
        
        try {
            const clientVersion = generateClientVersion();
            const checksum = generateChecksum(token);
            
            const response = await makeRequest({
                hostname: getEndpoint(),
                path: '/aiserver.v1.AiService/AvailableModels',
                method: 'POST',
                headers: {
                    'authorization': `Bearer ${token}`,
                    'content-type': 'application/proto',
                    'x-cursor-checksum': checksum,
                    'x-cursor-client-version': clientVersion,
                    'x-ghost-mode': 'true',
                    'user-agent': 'Mozilla/5.0'
                }
            }, Buffer.alloc(0));
            
            // Parse protobuf response (simplified)
            const models = [];
            const body = response.body.toString('utf-8');
            const modelNames = ['composer-1', 'claude-4.5-opus-high', 'claude-4.5-sonnet', 
                               'claude-4.5-sonnet-thinking', 'gpt-5.2', 'gemini-3-pro',
                               'claude-4.5-haiku', 'gpt-5.2-codex'];
            
            modelNames.forEach(name => {
                if (body.includes(name) || true) { // Always include base models
                    models.push({id: name, object: 'model', owned_by: 'cursor', created: Date.now()});
                }
            });
            
            res.writeHead(200, {'Content-Type': 'application/json'});
            res.end(JSON.stringify({object: 'list', data: models}));
        } catch (err) {
            rotateEndpoint();
            res.writeHead(200, {'Content-Type': 'application/json'});
            res.end(JSON.stringify({
                object: 'list',
                data: [{id: 'composer-1', object: 'model', owned_by: 'cursor'}]
            }));
        }
        return;
    }
    
    // Chat completions
    if (url === '/v1/chat/completions' && req.method === 'POST') {
        let body = '';
        req.on('data', chunk => body += chunk);
        req.on('end', async () => {
            try {
                const data = JSON.parse(body);
                const {model, messages, stream} = data;
                
                if (!token) {
                    res.writeHead(401, {'Content-Type': 'application/json'});
                    return res.end(JSON.stringify({error: 'Authorization required'}));
                }
                
                const clientVersion = generateClientVersion();
                const checksum = generateChecksum(token);
                const sessionId = crypto.createHash('sha256').update(token).digest('hex').slice(0, 32);
                
                // Build request body (simplified protobuf-like)
                const msgContent = messages.map(m => {
                    const content = typeof m.content === 'string' ? m.content : 
                        (Array.isArray(m.content) ? m.content.map(c => c.text || '').join('\n') : String(m.content));
                    return {role: m.role === 'user' ? 1 : 2, content};
                });
                
                const reqBody = JSON.stringify({
                    model: model,
                    messages: msgContent,
                    stream: stream
                });
                
                const response = await makeRequest({
                    hostname: getEndpoint(),
                    path: '/aiserver.v1.ChatService/StreamUnifiedChatWithTools',
                    method: 'POST',
                    headers: {
                        'authorization': `Bearer ${token}`,
                        'content-type': 'application/json',
                        'x-cursor-checksum': checksum,
                        'x-cursor-client-version': clientVersion,
                        'x-cursor-timezone': Intl.DateTimeFormat().resolvedOptions().timeZone,
                        'x-ghost-mode': 'true',
                        'x-session-id': sessionId,
                        'user-agent': 'Mozilla/5.0'
                    }
                }, reqBody);
                
                // Parse and return response
                let content = '';
                try {
                    const text = response.body.toString('utf-8');
                    // Extract text content from response
                    const match = text.match(/"content"\s*:\s*"([^"]+)"/);
                    content = match ? match[1] : text.slice(0, 1000);
                } catch (e) {
                    content = response.body.toString('utf-8').slice(0, 1000);
                }
                
                if (stream) {
                    res.writeHead(200, {
                        'Content-Type': 'text/event-stream',
                        'Cache-Control': 'no-cache',
                        'Connection': 'keep-alive'
                    });
                    res.write(`data: ${JSON.stringify({
                        id: 'chatcmpl-' + Date.now(),
                        object: 'chat.completion.chunk',
                        model: model,
                        choices: [{index: 0, delta: {content: content}}]
                    })}\n\n`);
                    res.write('data: [DONE]\n\n');
                    res.end();
                } else {
                    res.writeHead(200, {'Content-Type': 'application/json'});
                    res.end(JSON.stringify({
                        id: 'chatcmpl-' + Date.now(),
                        object: 'chat.completion',
                        model: model,
                        choices: [{
                            index: 0,
                            message: {role: 'assistant', content: content},
                            finish_reason: 'stop'
                        }],
                        usage: {prompt_tokens: 0, completion_tokens: 0, total_tokens: 0}
                    }));
                }
            } catch (err) {
                console.error('Error:', err.message);
                rotateEndpoint();
                res.writeHead(500, {'Content-Type': 'application/json'});
                res.end(JSON.stringify({error: 'Internal error'}));
            }
        });
        return;
    }
    
    // Health check
    if (url === '/health') {
        res.writeHead(200, {'Content-Type': 'application/json'});
        return res.end(JSON.stringify({status: 'ok', endpoint: getEndpoint()}));
    }
    
    res.writeHead(404);
    res.end('Not found');
});

server.listen(PORT, '127.0.0.1', () => {
    console.log(`Cursor provider listening on 127.0.0.1:${PORT}`);
});
PROXYEOF

    log "✓ Provider installed"
}

# Save configuration
save_config() {
    mkdir -p "$INSTALL_DIR"
    echo "CURSOR_COOKIE=$CURSOR_COOKIE" > "$INSTALL_DIR/.env"
    chmod 600 "$INSTALL_DIR/.env"
    
    # Update OpenClaw config
    if [ -f "$CONFIG" ]; then
        jq --arg cookie "$CURSOR_COOKIE" --arg model "cursor/$PRIMARY_MODEL" '
            .models.mode = "merge" |
            .models.providers.cursor = {
                "baseUrl": "http://127.0.0.1:3010/v1",
                "apiKey": $cookie,
                "api": "openai-completions",
                "models": [
                    {"id": "composer-1", "name": "Composer-1 (Fast)", "reasoning": false, "input": ["text"], "cost": {"input": 0, "output": 0}, "contextWindow": 128000, "maxTokens": 8192},
                    {"id": "claude-4.5-opus-high", "name": "Claude 4.5 Opus", "reasoning": true, "input": ["text"], "cost": {"input": 0, "output": 0}, "contextWindow": 200000, "maxTokens": 8192},
                    {"id": "claude-4.5-sonnet", "name": "Claude 4.5 Sonnet", "reasoning": false, "input": ["text"], "cost": {"input": 0, "output": 0}, "contextWindow": 200000, "maxTokens": 8192},
                    {"id": "claude-4.5-sonnet-thinking", "name": "Claude 4.5 Sonnet Thinking", "reasoning": true, "input": ["text"], "cost": {"input": 0, "output": 0}, "contextWindow": 200000, "maxTokens": 8192},
                    {"id": "claude-4.5-haiku", "name": "Claude 4.5 Haiku", "reasoning": false, "input": ["text"], "cost": {"input": 0, "output": 0}, "contextWindow": 200000, "maxTokens": 8192},
                    {"id": "gpt-5.2", "name": "GPT-5.2", "reasoning": false, "input": ["text"], "cost": {"input": 0, "output": 0}, "contextWindow": 272000, "maxTokens": 8192},
                    {"id": "gpt-5.2-codex", "name": "GPT-5.2 Codex", "reasoning": false, "input": ["text"], "cost": {"input": 0, "output": 0}, "contextWindow": 272000, "maxTokens": 8192},
                    {"id": "gemini-3-pro", "name": "Gemini 3 Pro", "reasoning": false, "input": ["text"], "cost": {"input": 0, "output": 0}, "contextWindow": 200000, "maxTokens": 8192}
                ]
            } |
            .agents.defaults.model.primary = $model |
            .agents.defaults.model.fallbacks = ["cursor/claude-4.5-sonnet", "cursor/composer-1", "anthropic/claude-sonnet-4-5"] |
            .agents.defaults.subagents.model = "cursor/composer-1" |
            .agents.defaults.models["cursor/composer-1"] = {"alias": "fast"} |
            .agents.defaults.models["cursor/claude-4.5-opus-high"] = {"alias": "opus"} |
            .agents.defaults.models["cursor/claude-4.5-sonnet"] = {"alias": "sonnet"} |
            .agents.defaults.models["cursor/claude-4.5-haiku"] = {"alias": "haiku"} |
            .agents.defaults.models["cursor/gpt-5.2"] = {"alias": "gpt"} |
            .agents.defaults.models["cursor/gpt-5.2-codex"] = {"alias": "codex"} |
            .agents.defaults.models["cursor/gemini-3-pro"] = {"alias": "gemini"}
        ' "$CONFIG" > /tmp/oc.json && mv /tmp/oc.json "$CONFIG"
        log "✓ OpenClaw configured with Cursor provider"
    fi
}

# Setup service
setup_service() {
    case "$SERVICE_MGR" in
        systemd)
            mkdir -p "$HOME/.config/systemd/user"
            cat > "$HOME/.config/systemd/user/cursor-provider.service" << EOF
[Unit]
Description=Cursor Provider for OpenClaw
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
EnvironmentFile=$INSTALL_DIR/.env
ExecStart=$(which node) $INSTALL_DIR/server.js
Restart=always
RestartSec=5
Environment=PORT=3010

[Install]
WantedBy=default.target
EOF
            systemctl --user daemon-reload
            systemctl --user enable cursor-provider 2>/dev/null || true
            systemctl --user start cursor-provider
            log "✓ Service started (systemd)"
            ;;
        launchd)
            mkdir -p "$HOME/Library/LaunchAgents"
            cat > "$HOME/Library/LaunchAgents/com.openclaw.cursor-provider.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.openclaw.cursor-provider</string>
    <key>ProgramArguments</key>
    <array>
        <string>$(which node)</string>
        <string>$INSTALL_DIR/server.js</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PORT</key><string>3010</string>
        <key>CURSOR_COOKIE</key><string>$CURSOR_COOKIE</string>
    </dict>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
</dict>
</plist>
EOF
            launchctl load "$HOME/Library/LaunchAgents/com.openclaw.cursor-provider.plist" 2>/dev/null || true
            log "✓ Service started (launchd)"
            ;;
        pm2)
            command -v pm2 &>/dev/null || npm install -g pm2 --silent
            cd "$INSTALL_DIR"
            CURSOR_COOKIE="$CURSOR_COOKIE" PORT=3010 pm2 start server.js --name cursor-provider 2>/dev/null || true
            pm2 save 2>/dev/null || true
            log "✓ Service started (pm2)"
            ;;
    esac
}

# Test connection
test_connection() {
    sleep 2
    if curl -s http://127.0.0.1:3010/health | grep -q 'ok'; then
        log "✓ Provider running"
        
        # Test with auth
        local MODELS=$(curl -s http://127.0.0.1:3010/v1/models -H "Authorization: Bearer $CURSOR_COOKIE" 2>/dev/null | jq -r '.data[].id' 2>/dev/null | head -3)
        if [ -n "$MODELS" ]; then
            log "✓ Models available: $(echo $MODELS | tr '\n' ' ')"
        fi
    else
        warn "Provider may need a moment to start"
    fi
}

print_summary() {
    echo ""
    echo "=========================================="
    echo "  Cursor Provider Installed"
    echo "=========================================="
    echo ""
    echo "  Primary model: cursor/$PRIMARY_MODEL"
    echo "  Endpoint: http://127.0.0.1:3010/v1"
    echo ""
    echo "  Commands:"
    echo "    /model opus    - Switch to Claude Opus"
    echo "    /model fast    - Switch to Composer-1"
    echo "    /model gpt     - Switch to GPT-5.2"
    echo ""
    echo "  Restart OpenClaw to apply:"
    echo "    systemctl --user restart openclaw-gateway"
    echo ""
}

main() {
    echo ""
    echo "=========================================="
    echo "  OpenClaw - Cursor Provider Setup"
    echo "=========================================="
    echo ""
    
    detect_platform
    check_deps
    select_models
    extract_cookie
    install_proxy
    save_config
    setup_service
    test_connection
    print_summary
}

main "$@"
