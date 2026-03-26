#!/usr/bin/env bash
# Shoofly Advanced — one-command installer
# Usage: curl -fsSL https://shoofly.dev/install-advanced.sh | bash
#
# This script installs Shoofly Advanced on top of (or independently of) Shoofly Basic.
# Advanced adds: shoofly-check (pre-execution intercept), blocked.log, Unix socket daemon.
#
# License: MIT

set -euo pipefail

# ─── Step 0: Validate install token ───────────────────────────────────────────
INSTALL_TOKEN="${SHOOFLY_TOKEN:-}"
if [[ -z "$INSTALL_TOKEN" ]]; then
  echo ""
  echo "⚠️  This installer requires a personal install token."
  echo "   Your token was included in your purchase confirmation email."
  echo "   Usage: SHOOFLY_TOKEN=your_token bash <(curl -fsSL https://shoofly.dev/install-advanced.sh)"
  echo "   Or contact support@shoofly.dev for help."
  echo ""
  exit 1
fi

echo "Validating install token..."
VALIDATE_STATUS=$(/usr/bin/curl -s -o /dev/null -w "%{http_code}" \
  "https://shoofly-stripe-production.up.railway.app/validate?token=${INSTALL_TOKEN}")

if [[ "$VALIDATE_STATUS" != "200" ]]; then
  echo ""
  echo "⚠️  Token validation failed (status: $VALIDATE_STATUS)."
  echo "   This token may have already been used or may have expired (48h)."
  echo "   Contact support@shoofly.dev for a new install link."
  echo ""
  exit 1
fi
echo "  ✓ Token validated"

BASE_URL="https://raw.githubusercontent.com/shoofly-dev/shoofly/main"

echo ""
echo "⚡🪰⚡ Shoofly Advanced Installer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ─── Step 1: Verify dependencies ──────────────────────────────────────────────
echo "Checking dependencies..."

command -v jq >/dev/null 2>&1 || {
  echo "ERROR: jq is required but not installed."
  echo "  macOS:   brew install jq"
  echo "  Ubuntu:  sudo apt-get install jq"
  exit 1
}

command -v curl >/dev/null 2>&1 || {
  echo "ERROR: curl is required but not installed."
  exit 1
}

command -v openclaw >/dev/null 2>&1 || {
  echo "ERROR: openclaw is required but not installed."
  echo "  See: https://openclaw.ai/install"
  exit 1
}

echo "  ✓ jq, curl, openclaw found"

# ─── Step 2: Create directories ───────────────────────────────────────────────
echo "Creating directories..."
mkdir -p ~/.shoofly/{bin,policy,logs}
mkdir -p ~/.openclaw/skills/shoofly-advanced/policy
echo "  ✓ Directories ready"

# ─── Step 3: Download core files ──────────────────────────────────────────────
echo "Downloading Shoofly Advanced files..."

# Threat policy
curl -fsSL "$BASE_URL/advanced/policy/threats.yaml" -o ~/.shoofly/policy/threats.yaml
echo "  ✓ Policy downloaded: ~/.shoofly/policy/threats.yaml"

# shoofly-daemon (Advanced version with socket server)
curl -fsSL "$BASE_URL/advanced/bin/shoofly-daemon" -o ~/.shoofly/bin/shoofly-daemon
chmod +x ~/.shoofly/bin/shoofly-daemon
echo "  ✓ Daemon downloaded: ~/.shoofly/bin/shoofly-daemon"

# shoofly-notify
curl -fsSL "$BASE_URL/advanced/bin/shoofly-notify" -o ~/.shoofly/bin/shoofly-notify
chmod +x ~/.shoofly/bin/shoofly-notify
echo "  ✓ Notify dispatcher downloaded: ~/.shoofly/bin/shoofly-notify"

# shoofly-check (Advanced-only pre-execution intercept)
curl -fsSL "$BASE_URL/advanced/bin/shoofly-check" -o ~/.shoofly/bin/shoofly-check
chmod +x ~/.shoofly/bin/shoofly-check
echo "  ✓ shoofly-check downloaded: ~/.shoofly/bin/shoofly-check"

# shoofly-policy-lint and parse-policy.py (custom policy support)
curl -fsSL "$BASE_URL/advanced/bin/shoofly-policy-lint" -o ~/.shoofly/bin/shoofly-policy-lint
chmod +x ~/.shoofly/bin/shoofly-policy-lint
echo "  ✓ shoofly-policy-lint downloaded: ~/.shoofly/bin/shoofly-policy-lint"

# shoofly-status and shoofly-health (operational visibility)
curl -fsSL "$BASE_URL/advanced/bin/shoofly-status" -o ~/.shoofly/bin/shoofly-status
chmod +x ~/.shoofly/bin/shoofly-status
echo "  ✓ shoofly-status downloaded: ~/.shoofly/bin/shoofly-status"
curl -fsSL "$BASE_URL/advanced/bin/shoofly-health" -o ~/.shoofly/bin/shoofly-health
chmod +x ~/.shoofly/bin/shoofly-health
echo "  ✓ shoofly-health downloaded: ~/.shoofly/bin/shoofly-health"

# shoofly-log (audit trail query CLI)
curl -fsSL "$BASE_URL/advanced/bin/shoofly-log" -o ~/.shoofly/bin/shoofly-log
chmod +x ~/.shoofly/bin/shoofly-log
echo "  ✓ shoofly-log downloaded: ~/.shoofly/bin/shoofly-log"

# shoofly-scan (secret detection at rest)
curl -fsSL "$BASE_URL/advanced/bin/shoofly-scan" -o ~/.shoofly/bin/shoofly-scan
chmod +x ~/.shoofly/bin/shoofly-scan
echo "  ✓ shoofly-scan downloaded: ~/.shoofly/bin/shoofly-scan"

# Advanced SKILL.md
curl -fsSL "$BASE_URL/advanced/skills/shoofly-advanced/SKILL.md" -o ~/.openclaw/skills/shoofly-advanced/SKILL.md
echo "  ✓ Advanced SKILL.md installed"

# Symlink policy into skill directory
ln -sf ~/.shoofly/policy/threats.yaml ~/.openclaw/skills/shoofly-advanced/policy/threats.yaml
echo "  ✓ Policy symlinked into skill directory"


# ─── Step 3b: Install shoofly-hook extension (Advanced: pre-execution blocking) ──
echo "Installing shoofly-hook extension (Advanced tier: pre-execution blocking)..."
HOOK_DIR="$HOME/.openclaw/extensions/shoofly-hook"
mkdir -p "$HOOK_DIR"
curl -fsSL "$BASE_URL/extensions/shoofly-hook/index.ts" -o "$HOOK_DIR/index.ts"
echo "  ✓ shoofly-hook downloaded: $HOOK_DIR/index.ts"
# Register in openclaw.json if present and not already registered
OPENCLAW_CFG="$HOME/.openclaw/openclaw.json"
if [[ -f "$OPENCLAW_CFG" ]]; then
  HOOK_PATH="$HOME/.openclaw/extensions/shoofly-hook/index.ts"
  HOOK_KEY="shoofly-hook"
  # plugins.entries is a dict keyed by name, not an array
  ALREADY=$(jq --arg k "$HOOK_KEY" '.plugins.entries | has($k)' "$OPENCLAW_CFG" 2>/dev/null || echo "false")
  if [[ "$ALREADY" != "true" ]]; then
    _TMP=$(mktemp)
    jq --arg k "$HOOK_KEY" --arg p "$HOOK_PATH" \
      '.plugins.entries //= {} | .plugins.entries[$k] = {"path": $p, "enabled": true}' \
      "$OPENCLAW_CFG" > "$_TMP" && mv "$_TMP" "$OPENCLAW_CFG"
    echo "  ✓ shoofly-hook registered in openclaw.json"
  else
    echo "  ✓ shoofly-hook already registered in openclaw.json"
  fi
else
  echo "  WARN: ~/.openclaw/openclaw.json not found — register hook manually by adding shoofly-hook to plugins.entries"
fi
echo "  ✓ shoofly-hook extension ready"

# ─── Step 4: License check placeholder ───────────────────────────────────────
# DEFERRED: Stripe license check not yet implemented.
#
# When payment is implemented, this section will:
#   1. Prompt for a license key (from shoofly.dev/dashboard after checkout)
#   2. Validate against: https://api.shoofly.dev/license/verify
#   3. Store license token in ~/.shoofly/.license (chmod 600, never in config.json)
#   4. shoofly-check validates token offline against stored public key on first run per session
#   5. Network re-validation at most weekly
#
# For now, Advanced is available without a license key.
echo "  (License check: deferred — no key required for now)"

# ─── Step 5: Notification channel setup ───────────────────────────────────────
echo ""
echo "⚡🪰⚡ Shoofly Advanced — notification setup"
echo "Where should Shoofly send threat alerts and block events?"
echo "  1) Terminal only"
echo "  2) OpenClaw (recommended — uses your existing OpenClaw channels)"
echo "  3) Telegram direct (separate bot — only if not using OpenClaw)"
echo "  4) macOS notifications"
echo "  Multiple: enter comma-separated numbers (e.g. 1,2)"
echo ""
echo "  💡 If you use OpenClaw, pick 2 — alerts will route through your"
echo "     existing Telegram/WhatsApp/Discord setup automatically."
echo ""
read -r -t 30 -p "Choice [2]: " CHANNEL_CHOICE < /dev/tty
if [[ -z "$CHANNEL_CHOICE" ]]; then
  echo "(No input — defaulting to OpenClaw gateway)"
fi
CHANNEL_CHOICE=${CHANNEL_CHOICE:-2}

CHANNELS=()
[[ "$CHANNEL_CHOICE" == *"1"* ]] && CHANNELS+=("terminal")
[[ "$CHANNEL_CHOICE" == *"2"* ]] && CHANNELS+=("openclaw_gateway")
[[ "$CHANNEL_CHOICE" == *"3"* ]] && CHANNELS+=("telegram")
[[ "$CHANNEL_CHOICE" == *"4"* ]] && CHANNELS+=("macos")

# Default if nothing selected
[[ ${#CHANNELS[@]} -eq 0 ]] && CHANNELS+=("openclaw_gateway")

# Collect Telegram credentials only if direct Telegram chosen (not OpenClaw)
if [[ "$CHANNEL_CHOICE" == *"3"* ]]; then
  echo ""
  echo "  Direct Telegram setup — you'll need a Telegram bot token."
  echo "  Create one via @BotFather on Telegram, then get your chat ID"
  echo "  by messaging your bot and visiting:"
  echo "  https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates"
  echo ""
  read -r -p "Telegram Bot Token: " TG_TOKEN < /dev/tty
  read -r -p "Telegram Chat ID: " TG_CHAT_ID < /dev/tty
  touch ~/.shoofly/.env
  chmod 600 ~/.shoofly/.env
  grep -q "TELEGRAM_BOT_TOKEN" ~/.shoofly/.env 2>/dev/null || echo "TELEGRAM_BOT_TOKEN=${TG_TOKEN}" >> ~/.shoofly/.env
  grep -q "TELEGRAM_CHAT_ID" ~/.shoofly/.env 2>/dev/null || echo "TELEGRAM_CHAT_ID=${TG_CHAT_ID}" >> ~/.shoofly/.env
  echo "  ✓ Telegram credentials saved to ~/.shoofly/.env (chmod 600)"
fi

# ─── Step 6: Agent name and ID ────────────────────────────────────────────────
AGENT_NAME=$(openclaw status 2>/dev/null | jq -r '.agentName // "agent"' 2>/dev/null || echo "agent")
read -r -p "Agent name [$AGENT_NAME]: " INPUT_NAME < /dev/tty
AGENT_NAME=${INPUT_NAME:-$AGENT_NAME}

AGENT_ID=$(openclaw status 2>/dev/null | jq -r '.agentId // ""' 2>/dev/null || echo "")

# ─── Step 7: Write config ─────────────────────────────────────────────────────
# Build JSON array of channel names
CHANNELS_JSON=$(printf '"%s",' "${CHANNELS[@]}" | sed 's/,$//')

# Check if config already exists (upgrading from Basic)
if [[ -f ~/.shoofly/config.json ]]; then
  echo ""
  echo "Existing Shoofly config found — upgrading to Advanced tier..."
  # Update tier to advanced, add custom_policy_path if missing, preserve other settings
  _TMP=$(mktemp)
  jq '.tier = "advanced" | .custom_policy_path //= ""' ~/.shoofly/config.json > "$_TMP" \
    && mv "$_TMP" ~/.shoofly/config.json
  chmod 600 ~/.shoofly/config.json
  echo "  ✓ Config updated: tier → advanced"
else
  # Fresh install
  cat > ~/.shoofly/config.json <<EOF
{
  "tier": "advanced",
  "notification_channels": [${CHANNELS_JSON}],
  "agent_name": "${AGENT_NAME}",
  "agent_id": "${AGENT_ID}",
  "installed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "version": "1.0.0",
  "policy_path": "${HOME}/.shoofly/policy/threats.yaml",
  "custom_policy_path": ""
}
EOF
  chmod 600 ~/.shoofly/config.json
  echo "  ✓ Config written: ~/.shoofly/config.json (chmod 600)"
fi

# ─── Step 8: Initialize log files and audit database ─────────────────────────
touch ~/.shoofly/logs/alerts.log
touch ~/.shoofly/logs/blocked.log
echo "  ✓ Log files initialized:"
echo "      ~/.shoofly/logs/alerts.log"
echo "      ~/.shoofly/logs/blocked.log"

if command -v sqlite3 >/dev/null 2>&1; then
  sqlite3 ~/.shoofly/audit.db \
    "CREATE TABLE IF NOT EXISTS tool_calls (
       id         INTEGER PRIMARY KEY AUTOINCREMENT,
       ts         TEXT NOT NULL,
       session    TEXT,
       agent      TEXT,
       tier       TEXT,
       tool       TEXT NOT NULL,
       args       TEXT,
       outcome    TEXT,
       threat_id  TEXT,
       rule_id    TEXT,
       confidence TEXT
     );
     CREATE INDEX IF NOT EXISTS idx_ts    ON tool_calls(ts);
     CREATE INDEX IF NOT EXISTS idx_tool  ON tool_calls(tool);
     CREATE INDEX IF NOT EXISTS idx_agent ON tool_calls(agent);" 2>/dev/null || true
  echo "  ✓ Audit database initialized: ~/.shoofly/audit.db"
else
  echo "WARN: sqlite3 not found — audit trail disabled. Install with: brew install sqlite3"
fi

# ─── Step 9: Install launchd plist (macOS auto-start) ────────────────────────
if [[ "$(uname)" == "Darwin" ]]; then
  cat > ~/Library/LaunchAgents/dev.shoofly.daemon.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>dev.shoofly.daemon</string>
  <key>ProgramArguments</key>
  <array>
    <string>$HOME/.shoofly/bin/shoofly-daemon</string>
    <string>--config</string>
    <string>$HOME/.shoofly/config.json</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$HOME/.shoofly/logs/daemon.log</string>
  <key>StandardErrorPath</key><string>$HOME/.shoofly/logs/daemon.err</string>
</dict></plist>
PLIST
  launchctl unload ~/Library/LaunchAgents/dev.shoofly.daemon.plist 2>/dev/null || true
  launchctl load ~/Library/LaunchAgents/dev.shoofly.daemon.plist 2>/dev/null || true
  echo "  ✓ LaunchAgent installed (auto-restart on crash)"
fi

# ─── Step 10: Verify daemon ───────────────────────────────────────────────────
echo ""
echo "Verifying Shoofly Advanced daemon..."
~/.shoofly/bin/shoofly-daemon --config ~/.shoofly/config.json --verify \
  && echo "  ✓ Daemon verified"

# ─── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Shoofly Advanced installed!"
echo ""
echo "   Hook:        ~/.openclaw/extensions/shoofly-hook/index.ts
   Skill:       ~/.openclaw/skills/shoofly-advanced/SKILL.md"
echo "   Check:       ~/.shoofly/bin/shoofly-check"
echo "   Daemon:      ~/.shoofly/bin/shoofly-daemon"
echo "   Socket:      ~/.shoofly/daemon.sock"
echo "   Alerts log:  ~/.shoofly/logs/alerts.log"
echo "   Blocked log: ~/.shoofly/logs/blocked.log"
echo "   Policy:      ~/.shoofly/policy/threats.yaml"
echo "   Config:      ~/.shoofly/config.json"
echo "   Docs:        https://shoofly.dev/docs/advanced"
echo ""
echo "   Run  shoofly-status   to see current operational status."
echo "   Run  shoofly-health   to verify all components are healthy."
echo ""
echo "💡 Add a shoofly.yaml to your project to define custom detection and blocking rules."
echo "   Validate it with: shoofly-policy-lint ./shoofly.yaml"
echo "   Docs: https://shoofly.dev/docs/custom-policies"
echo ""
echo "⚡🪰⚡ Shoofly Advanced is active. Threats will be blocked before execution."
echo ""
