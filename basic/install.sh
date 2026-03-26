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

# 4. Download shoofly-setup wizard
curl -fsSL "$BASE_URL/advanced/bin/shoofly-setup" -o ~/.shoofly/bin/shoofly-setup
chmod +x ~/.shoofly/bin/shoofly-setup

# 5. Run interactive setup wizard (writes ~/.shoofly/config.json)
command -v node >/dev/null || { echo "node required: brew install node"; exit 1; }
node ~/.shoofly/bin/shoofly-setup --tier basic

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
