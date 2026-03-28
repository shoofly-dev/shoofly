#!/usr/bin/env bash
# Shoofly Basic (OpenClaw + Claude Code) — one-command installer
# Usage: curl -fsSL https://shoofly.dev/install-claude-code.sh | bash

set -euo pipefail

# ─── TTY guard — re-exec with a real TTY if piped from curl ──────────────────
# @clack/prompts requires an interactive terminal. When run as `curl | bash`,
# stdin is the pipe, not the terminal — keyboard input breaks.
# Fix: download self to /tmp and re-exec with /dev/tty as stdin.
if [ ! -t 0 ]; then
  SELF=$(mktemp /tmp/shoofly-cc-basic-XXXXXX)
  curl -fsSL "https://shoofly.dev/install-claude-code.sh" -o "$SELF"
  chmod +x "$SELF"
  exec bash "$SELF" < /dev/tty
fi

echo ""
echo "🪰 Shoofly Basic — OpenClaw + Claude Code"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ─── Step 1: Verify dependencies ──────────────────────────────────────────────
echo "Checking dependencies..."

command -v node >/dev/null 2>&1 || {
  echo "ERROR: node is required but not installed."
  echo "  macOS:   brew install node"
  echo "  Ubuntu:  sudo apt-get install nodejs"
  exit 1
}

command -v claude >/dev/null 2>&1 || {
  echo "ERROR: Claude Code CLI ('claude') is not installed or not in PATH."
  echo "  Install it: https://docs.anthropic.com/en/docs/claude-code"
  exit 1
}

echo "  ✓ node found: $(node --version)"
echo "  ✓ claude found: $(claude --version 2>/dev/null || echo 'ok')"

# ─── Step 2: Create directories ───────────────────────────────────────────────
echo "Creating directories..."
mkdir -p ~/.shoofly/{bin,policy,logs}
echo "  ✓ Directories ready"

# ─── Step 3: Copy files ───────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

cp "$SCRIPT_DIR/src/claude-code-daemon.js" ~/.shoofly/bin/shoofly-claude-daemon.js
chmod +x ~/.shoofly/bin/shoofly-claude-daemon.js
echo "  ✓ Daemon copied: ~/.shoofly/bin/shoofly-claude-daemon.js"

cp "$SCRIPT_DIR/src/claude-code-setup.js" ~/.shoofly/bin/shoofly-claude-code-setup.js
chmod +x ~/.shoofly/bin/shoofly-claude-code-setup.js
echo "  ✓ Setup wizard copied: ~/.shoofly/bin/shoofly-claude-code-setup.js"

cp "$SCRIPT_DIR/advanced/bin/shoofly-notify" ~/.shoofly/bin/shoofly-notify
chmod +x ~/.shoofly/bin/shoofly-notify
echo "  ✓ shoofly-notify copied"

cp "$SCRIPT_DIR/advanced/bin/shoofly-health" ~/.shoofly/bin/shoofly-health
chmod +x ~/.shoofly/bin/shoofly-health
echo "  ✓ shoofly-health copied"

cp "$SCRIPT_DIR/advanced/bin/shoofly-status" ~/.shoofly/bin/shoofly-status
chmod +x ~/.shoofly/bin/shoofly-status
echo "  ✓ shoofly-status copied"

# ─── Step 4: Run interactive setup wizard ─────────────────────────────────────
run_wizard() {
  node ~/.shoofly/bin/shoofly-claude-code-setup.js --tier basic
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
