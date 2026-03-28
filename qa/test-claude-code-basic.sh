#!/usr/bin/env bash
# QA: Shoofly Claude Code — Basic tier PostToolUse alert test
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DAEMON="$SCRIPT_DIR/../src/claude-code-daemon.js"
PORT=7777
LOG_DIR="$HOME/.shoofly/logs"
LOG_PATH="$LOG_DIR/hook-alerts.log"
CONFIG_PATH="$HOME/.shoofly/config.json"
PASS=true

# Ensure basic tier
mkdir -p "$(dirname "$CONFIG_PATH")"
ORIG_CONFIG=""
[ -f "$CONFIG_PATH" ] && ORIG_CONFIG=$(cat "$CONFIG_PATH")
echo '{"tier": "basic"}' > "$CONFIG_PATH"

# Clear log
mkdir -p "$LOG_DIR"
: > "$LOG_PATH"

cleanup() {
  [ -n "${DAEMON_PID:-}" ] && kill "$DAEMON_PID" 2>/dev/null || true
  wait "$DAEMON_PID" 2>/dev/null || true
  # Restore original config
  if [ -n "$ORIG_CONFIG" ]; then
    echo "$ORIG_CONFIG" > "$CONFIG_PATH"
  fi
}
trap cleanup EXIT

# Start daemon
node "$DAEMON" &
DAEMON_PID=$!
sleep 1

echo "=== Basic Tier PostToolUse Tests ==="
echo ""

# Test 1: Safe tool call — no alert, response is {}
echo -n "Test 1: Safe tool call returns {} and no alert ... "
RESP=$(curl -s -X POST http://127.0.0.1:$PORT/shoofly/v1/post-tool-use \
  -H "Content-Type: application/json" \
  -d '{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.txt"},"session_id":"test-basic"}')

if [ "$RESP" = "{}" ]; then
  # Check no log entry was written
  if [ ! -s "$LOG_PATH" ]; then
    echo "PASS"
  else
    echo "FAIL (unexpected log entry)"
    PASS=false
  fi
else
  echo "FAIL (response: $RESP)"
  PASS=false
fi

# Test 2: Credential pattern in Bash — alert logged
echo -n "Test 2: Credential pattern fires alert to log ... "
: > "$LOG_PATH"
RESP=$(curl -s -X POST http://127.0.0.1:$PORT/shoofly/v1/post-tool-use \
  -H "Content-Type: application/json" \
  -d '{"tool_name":"Bash","tool_input":{"command":"echo sk-abcdefghijklmnopqrstuvwxyz1234"},"session_id":"test-basic"}')

if [ "$RESP" = "{}" ]; then
  # Check log entry was written
  if grep -q '"threat":"DE"' "$LOG_PATH" 2>/dev/null; then
    echo "PASS"
  else
    echo "FAIL (no alert in log)"
    PASS=false
  fi
else
  echo "FAIL (response: $RESP)"
  PASS=false
fi

echo ""
if [ "$PASS" = true ]; then
  echo "✅ PASS — all basic tier tests passed"
else
  echo "❌ FAIL — one or more tests failed"
  exit 1
fi
