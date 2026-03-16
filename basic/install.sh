#!/usr/bin/env bash
set -euo pipefail

# 1. Verify dependencies
command -v jq >/dev/null || { echo "jq required: brew install jq"; exit 1; }
command -v curl >/dev/null || { echo "curl required"; exit 1; }
command -v openclaw >/dev/null || { echo "openclaw required: see openclaw.ai/install"; exit 1; }

# 2. Create directories
mkdir -p ~/.shoofly/{bin,policy,logs}
mkdir -p ~/.openclaw/skills/shoofly-basic/policy

# 3. Download files
BASE_URL="https://raw.githubusercontent.com/shoofly-dev/shoofly/main"
curl -fsSL "$BASE_URL/basic/skills/shoofly-basic/SKILL.md" -o ~/.openclaw/skills/shoofly-basic/SKILL.md
curl -fsSL "$BASE_URL/basic/policy/threats.yaml" -o ~/.shoofly/policy/threats.yaml
ln -sf ~/.shoofly/policy/threats.yaml ~/.openclaw/skills/shoofly-basic/policy/threats.yaml
curl -fsSL "$BASE_URL/basic/bin/shoofly-daemon" -o ~/.shoofly/bin/shoofly-daemon
curl -fsSL "$BASE_URL/basic/bin/shoofly-notify" -o ~/.shoofly/bin/shoofly-notify
chmod +x ~/.shoofly/bin/shoofly-daemon ~/.shoofly/bin/shoofly-notify

# 4. Detect notification channel preference
echo ""
echo "🪰 Shoofly Basic — notification setup"
echo "Where should Shoofly send threat alerts?"
echo "  1) Terminal only (default)"
echo "  2) OpenClaw gateway (local)"
echo "  3) Telegram"
echo "  4) WhatsApp"
echo "  5) macOS notifications"
echo "  Multiple: enter comma-separated numbers (e.g. 1,5)"
read -r -p "Choice [1]: " CHANNEL_CHOICE
CHANNEL_CHOICE=${CHANNEL_CHOICE:-1}

# Map choices to channel names
CHANNELS=()
[[ "$CHANNEL_CHOICE" == *"1"* ]] && CHANNELS+=("terminal")
[[ "$CHANNEL_CHOICE" == *"2"* ]] && CHANNELS+=("openclaw_gateway")
[[ "$CHANNEL_CHOICE" == *"3"* ]] && CHANNELS+=("telegram")
[[ "$CHANNEL_CHOICE" == *"4"* ]] && CHANNELS+=("whatsapp")
[[ "$CHANNEL_CHOICE" == *"5"* ]] && CHANNELS+=("macos")

# If telegram, collect credentials
if [[ "$CHANNEL_CHOICE" == *"3"* ]]; then
  read -r -p "Telegram Bot Token: " TG_TOKEN
  read -r -p "Telegram Chat ID: " TG_CHAT_ID
  echo "TELEGRAM_BOT_TOKEN=$TG_TOKEN" >> ~/.shoofly/.env
  echo "TELEGRAM_CHAT_ID=$TG_CHAT_ID" >> ~/.shoofly/.env
  chmod 600 ~/.shoofly/.env
fi

# 5. Get agent name
AGENT_NAME=$(openclaw status 2>/dev/null | jq -r '.agentName // "agent"' 2>/dev/null || echo "agent")
read -r -p "Agent name [$AGENT_NAME]: " INPUT_NAME
AGENT_NAME=${INPUT_NAME:-$AGENT_NAME}

# 6. Get agent ID for session log path
AGENT_ID=$(openclaw status 2>/dev/null | jq -r '.agentId // ""' 2>/dev/null || echo "")

# 7. Write config
CHANNELS_JSON=$(printf '"%s",' "${CHANNELS[@]}" | sed 's/,$//')
cat > ~/.shoofly/config.json <<EOF
{
  "tier": "basic",
  "notification_channels": [$CHANNELS_JSON],
  "agent_name": "$AGENT_NAME",
  "agent_id": "$AGENT_ID",
  "installed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "version": "1.0.0",
  "policy_path": "$HOME/.shoofly/policy/threats.yaml"
}
EOF
chmod 600 ~/.shoofly/config.json

# 8. Install launchd plist (macOS) to auto-start daemon
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
  launchctl load ~/Library/LaunchAgents/dev.shoofly.daemon.plist 2>/dev/null || true
fi

# 9. Start daemon in foreground for first run verification, then background
~/.shoofly/bin/shoofly-daemon --config ~/.shoofly/config.json --verify && echo "✓ Shoofly daemon verified"

echo ""
echo "✅ Shoofly Basic installed!"
echo "   Alerts log: ~/.shoofly/logs/alerts.log"
echo "   Policy:     ~/.shoofly/policy/threats.yaml"
echo "   Docs:       https://shoofly.dev/docs"
echo ""
echo "🪰 Watching your agents. Stay safe."
