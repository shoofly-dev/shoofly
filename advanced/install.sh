#!/usr/bin/env bash
# Shoofly Advanced — one-command installer
# Usage: curl -fsSL https://shoofly.dev/install-advanced.sh | bash
#
# This script installs Shoofly Advanced on top of (or independently of) Shoofly Basic.
# Advanced adds: shoofly-check (pre-execution intercept), blocked.log, Unix socket daemon.
#
# License: MIT

set -euo pipefail

# DEV COPY — never serve this file directly to users; use builds/shoofly-advanced/install.sh for distribution
# (builds/ copy has BASE_URL pinned to release tag; this source copy intentionally tracks main)
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
curl -fsSL "$BASE_URL/policy/threats.yaml" -o ~/.shoofly/policy/threats.yaml
echo "  ✓ Policy downloaded: ~/.shoofly/policy/threats.yaml"

# shoofly-daemon (Advanced version with socket server)
curl -fsSL "$BASE_URL/bin/shoofly-daemon" -o ~/.shoofly/bin/shoofly-daemon
chmod +x ~/.shoofly/bin/shoofly-daemon
echo "  ✓ Daemon downloaded: ~/.shoofly/bin/shoofly-daemon"

# shoofly-notify
curl -fsSL "$BASE_URL/bin/shoofly-notify" -o ~/.shoofly/bin/shoofly-notify
chmod +x ~/.shoofly/bin/shoofly-notify
echo "  ✓ Notify dispatcher downloaded: ~/.shoofly/bin/shoofly-notify"

# shoofly-check (Advanced-only pre-execution intercept)
curl -fsSL "$BASE_URL/bin/shoofly-check" -o ~/.shoofly/bin/shoofly-check
chmod +x ~/.shoofly/bin/shoofly-check
echo "  ✓ shoofly-check downloaded: ~/.shoofly/bin/shoofly-check"

# Advanced SKILL.md
curl -fsSL "$BASE_URL/skills/shoofly-advanced/SKILL.md" -o ~/.openclaw/skills/shoofly-advanced/SKILL.md
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
  ALREADY=$(jq --arg p "$HOOK_PATH" '(.plugins.entries // []) | map(.path) | contains([$p])' "$OPENCLAW_CFG" 2>/dev/null || echo "false")
  if [[ "$ALREADY" != "true" ]]; then
    _TMP=$(mktemp)
    jq --arg p "$HOOK_PATH" '(.plugins.entries //= []) | .plugins.entries += [{"path": $p, "enabled": true}]' "$OPENCLAW_CFG" > "$_TMP" && mv "$_TMP" "$OPENCLAW_CFG"
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

# ─── Step 5: Run interactive setup wizard (writes ~/.shoofly/config.json) ─────
command -v node >/dev/null 2>&1 || {
  echo "ERROR: node is required but not installed."
  echo "  macOS:   brew install node"
  exit 1
}
# Always download fresh so hint changes take effect immediately
curl -fsSL "$BASE_URL/advanced/bin/shoofly-setup" -o ~/.shoofly/bin/shoofly-setup
chmod +x ~/.shoofly/bin/shoofly-setup
node ~/.shoofly/bin/shoofly-setup --tier advanced

# ─── Step 8: Initialize log files ─────────────────────────────────────────────
touch ~/.shoofly/logs/alerts.log
touch ~/.shoofly/logs/blocked.log
echo "  ✓ Log files initialized:"
echo "      ~/.shoofly/logs/alerts.log"
echo "      ~/.shoofly/logs/blocked.log"

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

# ─── Add ~/.shoofly/bin to PATH ──────────────────────────────────────────────
SHOOFLY_PATH_LINE='export PATH="$HOME/.shoofly/bin:$PATH"'
for rc in ~/.zshrc ~/.bash_profile ~/.bashrc; do
  if [[ -f "$rc" ]] && ! grep -q '.shoofly/bin' "$rc" 2>/dev/null; then
    echo "" >> "$rc"
    echo "# Shoofly CLI tools" >> "$rc"
    echo "$SHOOFLY_PATH_LINE" >> "$rc"
  fi
done
export PATH="$HOME/.shoofly/bin:$PATH"
echo "  ✓ ~/.shoofly/bin added to PATH"

# ─── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Shoofly Advanced installed!"
echo ""
echo "   Hook:        ~/.openclaw/extensions/shoofly-hook/index.ts"
echo "   Skill:       ~/.openclaw/skills/shoofly-advanced/SKILL.md"
echo "   Check:       ~/.shoofly/bin/shoofly-check"
echo "   Daemon:      ~/.shoofly/bin/shoofly-daemon"
echo "   Socket:      ~/.shoofly/daemon.sock"
echo "   Alerts log:  ~/.shoofly/logs/alerts.log"
echo "   Blocked log: ~/.shoofly/logs/blocked.log"
echo "   Policy:      ~/.shoofly/policy/threats.yaml"
echo "   Config:      ~/.shoofly/config.json"
echo "   Docs:        https://shoofly.dev/docs/advanced"
echo ""
echo "⚡🪰⚡ Shoofly Advanced is active. Threats will be blocked before execution."
echo ""
