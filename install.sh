#!/usr/bin/env bash
# Shoofly Basic — one-command installer
# Usage: curl -fsSL https://shoofly.dev/install.sh | bash

set -euo pipefail

# ─── TTY guard — re-exec with a real TTY if piped from curl ──────────────────
# @clack/prompts requires an interactive terminal. When run as `curl | bash`,
# stdin is the pipe, not the terminal — keyboard input breaks.
# Fix: download self to /tmp and re-exec with /dev/tty as stdin.
if [ ! -t 0 ]; then
  SELF=$(mktemp /tmp/shoofly-basic-XXXXXX)
  curl -fsSL "https://shoofly.dev/install.sh" -o "$SELF"
  chmod +x "$SELF"
  exec bash "$SELF" < /dev/tty
fi

BASE_URL="https://raw.githubusercontent.com/shoofly-dev/shoofly/main"

echo ""
echo "🪰 Shoofly Basic Installer"
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

command -v node >/dev/null 2>&1 || {
  echo "ERROR: node is required but not installed."
  echo "  macOS:   brew install node"
  echo "  Ubuntu:  sudo apt-get install nodejs"
  exit 1
}

echo "  ✓ jq, curl, openclaw, node found"

# ─── Step 2: Create directories ───────────────────────────────────────────────
echo "Creating directories..."
mkdir -p ~/.shoofly/{bin,policy,logs}
mkdir -p ~/.openclaw/skills/shoofly-basic/policy
echo "  ✓ Directories ready"

# ─── Step 3: Download core files ──────────────────────────────────────────────
echo "Downloading Shoofly Basic files..."

curl -fsSL "$BASE_URL/basic/skills/shoofly-basic/SKILL.md" -o ~/.openclaw/skills/shoofly-basic/SKILL.md
echo "  ✓ SKILL.md installed"

curl -fsSL "$BASE_URL/basic/policy/threats.yaml" -o ~/.shoofly/policy/threats.yaml
echo "  ✓ Policy downloaded: ~/.shoofly/policy/threats.yaml"

ln -sf ~/.shoofly/policy/threats.yaml ~/.openclaw/skills/shoofly-basic/policy/threats.yaml
echo "  ✓ Policy symlinked into skill directory"

curl -fsSL "$BASE_URL/basic/bin/shoofly-daemon" -o ~/.shoofly/bin/shoofly-daemon
chmod +x ~/.shoofly/bin/shoofly-daemon
echo "  ✓ Daemon downloaded: ~/.shoofly/bin/shoofly-daemon"

curl -fsSL "$BASE_URL/basic/bin/shoofly-notify" -o ~/.shoofly/bin/shoofly-notify
chmod +x ~/.shoofly/bin/shoofly-notify
echo "  ✓ Notify dispatcher downloaded: ~/.shoofly/bin/shoofly-notify"

# Operational visibility binaries (shared with Advanced)
curl -fsSL "$BASE_URL/advanced/bin/shoofly-status" -o ~/.shoofly/bin/shoofly-status
chmod +x ~/.shoofly/bin/shoofly-status
echo "  ✓ shoofly-status downloaded: ~/.shoofly/bin/shoofly-status"

curl -fsSL "$BASE_URL/advanced/bin/shoofly-health" -o ~/.shoofly/bin/shoofly-health
chmod +x ~/.shoofly/bin/shoofly-health
echo "  ✓ shoofly-health downloaded: ~/.shoofly/bin/shoofly-health"

curl -fsSL "$BASE_URL/advanced/bin/shoofly-log" -o ~/.shoofly/bin/shoofly-log
chmod +x ~/.shoofly/bin/shoofly-log
echo "  ✓ shoofly-log downloaded: ~/.shoofly/bin/shoofly-log"

# ─── Step 4: Download shoofly-setup wizard ────────────────────────────────────
curl -fsSL "$BASE_URL/advanced/bin/shoofly-setup" -o ~/.shoofly/bin/shoofly-setup
chmod +x ~/.shoofly/bin/shoofly-setup
echo "  ✓ Setup wizard downloaded"

# ─── Step 5: Run interactive setup wizard (writes ~/.shoofly/config.json) ─────
run_wizard() {
  node ~/.shoofly/bin/shoofly-setup --tier basic
}

run_wizard
WIZARD_EXIT=$?
while [ $WIZARD_EXIT -ne 0 ]; do
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  if [ -f ~/.shoofly/config.json ]; then
    echo "   Happens to the best of us. 🙂"
    echo ""
    echo "   Your install is active — Shoofly is watching right now."
    echo "   No changes were saved."
  else
    echo "   No worries — nothing was changed."
  fi
  echo ""
  printf "   Want to run through setup again? (Y/N) "
  read -r RETRY </dev/tty
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  case "$RETRY" in
    y|Y|yes|Yes|YES)
      run_wizard
      WIZARD_EXIT=$?
      ;;
    *)
      exit 0
      ;;
  esac
done

# ─── Step 6: Initialize log files and audit database ──────────────────────────
touch ~/.shoofly/logs/alerts.log
echo "  ✓ Log file initialized: ~/.shoofly/logs/alerts.log"

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
  echo "  WARN: sqlite3 not found — audit trail disabled. Install with: brew install sqlite3"
fi

# ─── Step 7: Install launchd plist (macOS auto-start) ─────────────────────────
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

# ─── Step 8: Verify daemon ────────────────────────────────────────────────────
echo ""
echo "Verifying Shoofly Basic daemon..."
~/.shoofly/bin/shoofly-daemon --config ~/.shoofly/config.json --verify \
  && echo "  ✓ Daemon verified"

# ─── PATH setup ───────────────────────────────────────────────────────────────
SHOOFLY_BIN="$HOME/.shoofly/bin"
SHELL_RC=""
if [[ "$SHELL" == */zsh ]]; then
  SHELL_RC="$HOME/.zshrc"
elif [[ "$SHELL" == */bash ]]; then
  SHELL_RC="$HOME/.bashrc"
fi

if [[ -n "$SHELL_RC" ]]; then
  if ! grep -q 'shoofly/bin' "$SHELL_RC" 2>/dev/null; then
    echo "" >> "$SHELL_RC"
    echo "# Shoofly CLI tools" >> "$SHELL_RC"
    echo "export PATH=\"\$HOME/.shoofly/bin:\$PATH\"" >> "$SHELL_RC"
    echo "  ✓ Added ~/.shoofly/bin to PATH in $SHELL_RC"
    echo "  ⚠️  Run 'source $SHELL_RC' or open a new terminal for shoofly-* commands to work"
  fi
fi
# Make tools available in this session right now
export PATH="$SHOOFLY_BIN:$PATH"

# ─── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅  You're all set."
echo ""
echo "   Shoofly Basic is watching your agents."
echo ""
echo "   What's next:"
echo "     shoofly-status    see what Shoofly is doing right now"
echo "     shoofly-health    verify all components are healthy"
echo "     shoofly-log       browse recent alerts"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
