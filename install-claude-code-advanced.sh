#!/usr/bin/env bash
# Shoofly Advanced (OpenClaw + Claude Code) — one-command installer
# Usage: SHOOFLY_TOKEN=your_token bash <(curl -fsSL https://shoofly.dev/install-claude-code-advanced.sh)

set -euo pipefail

# ─── Step 0: Validate install token ───────────────────────────────────────────
INSTALL_TOKEN="${SHOOFLY_TOKEN:-}"
if [[ -z "$INSTALL_TOKEN" ]]; then
  echo ""
  echo "⚠️  This installer requires a personal install token."
  echo "   Your token was included in your purchase confirmation email."
  echo "   Usage: SHOOFLY_TOKEN=your_token bash <(curl -fsSL https://shoofly.dev/install-claude-code-advanced.sh)"
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

# ─── TTY guard — re-exec with a real TTY if piped from curl ──────────────────
if [ ! -t 0 ]; then
  SELF=$(mktemp /tmp/shoofly-cc-advanced-XXXXXX)
  curl -fsSL "https://shoofly.dev/install-claude-code-advanced.sh" -o "$SELF"
  chmod +x "$SELF"
  exec env SHOOFLY_TOKEN="$INSTALL_TOKEN" bash "$SELF" < /dev/tty
fi

echo ""
echo "⚡🪰⚡ Shoofly Advanced — OpenClaw + Claude Code"
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
  node ~/.shoofly/bin/shoofly-claude-code-setup.js --tier advanced
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
