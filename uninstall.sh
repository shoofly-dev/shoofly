#!/usr/bin/env bash
# Shoofly — Universal Uninstaller
# Usage: curl -fsSL https://shoofly.dev/uninstall.sh | bash
set -euo pipefail

# ─── TTY guard — re-exec with a real TTY if piped from curl ──────────────────
if [ ! -t 0 ]; then
  SELF=$(mktemp /tmp/shoofly-uninstall-XXXXXX)
  curl -fsSL "https://shoofly.dev/uninstall.sh" -o "$SELF"
  chmod +x "$SELF"
  exec bash "$SELF" < /dev/tty
fi

# ─── Detect tier ─────────────────────────────────────────────────────────────
CONFIG="$HOME/.shoofly/config.json"
if [ ! -f "$CONFIG" ]; then
  echo "No Shoofly installation found."
  exit 0
fi

TIER=$(jq -r '.tier // empty' "$CONFIG" 2>/dev/null || true)

if [ "$TIER" = "advanced" ]; then
  # ─── Advanced uninstall ──────────────────────────────────────────────────
  echo ""
  echo "⚡🪰⚡ Shoofly Advanced — Uninstall"
  echo "────────────────────────────────────────"
  echo ""

  PLIST="$HOME/Library/LaunchAgents/dev.shoofly.daemon.plist"
  if [ -f "$PLIST" ]; then
    echo "Stopping LaunchAgent…"
    launchctl unload "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
  fi

  pkill -f shoofly-daemon 2>/dev/null || true

  echo "Removing binaries…"
  rm -f ~/.shoofly/bin/shoofly-daemon \
        ~/.shoofly/bin/shoofly-notify \
        ~/.shoofly/bin/shoofly-setup \
        ~/.shoofly/bin/shoofly-check \
        ~/.shoofly/bin/shoofly-health \
        ~/.shoofly/bin/shoofly-log \
        ~/.shoofly/bin/shoofly-block-log \
        ~/.shoofly/bin/shoofly-status \
        ~/.shoofly/bin/shoofly-policy-lint \
        ~/.shoofly/bin/shoofly-scan

  echo "Removing OpenClaw skill…"
  rm -rf ~/.openclaw/skills/shoofly-advanced

  echo "Removing hook extension…"
  rm -rf ~/.openclaw/extensions/shoofly-hook/

  echo ""
  read -r -p "Remove ~/.shoofly/ config and logs? [y/N]: " answer < /dev/tty
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    rm -rf ~/.shoofly/
    echo ""
    echo "Shoofly Advanced fully removed."
  else
    if [ -f ~/.shoofly/logs/blocked.log ]; then
      read -r -p "Remove blocked.log separately? [y/N]: " blocked < /dev/tty
      if [[ "$blocked" =~ ^[Yy]$ ]]; then
        rm -f ~/.shoofly/logs/blocked.log
        echo "blocked.log removed."
      fi
    fi
    echo ""
    echo "Shoofly Advanced removed. Config and logs kept at ~/.shoofly/"
  fi
else
  # ─── Basic uninstall ────────────────────────────────────────────────────
  echo ""
  echo "🪰 Shoofly Basic — Uninstall"
  echo "────────────────────────────────────────"
  echo ""

  PLIST="$HOME/Library/LaunchAgents/dev.shoofly.daemon.plist"
  if [ -f "$PLIST" ]; then
    echo "Stopping LaunchAgent…"
    launchctl unload "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
  fi

  pkill -f shoofly-daemon 2>/dev/null || true

  echo "Removing binaries…"
  rm -f ~/.shoofly/bin/shoofly-daemon \
        ~/.shoofly/bin/shoofly-notify \
        ~/.shoofly/bin/shoofly-setup

  echo "Removing OpenClaw skill…"
  rm -rf ~/.openclaw/skills/shoofly-basic

  echo ""
  read -r -p "Remove ~/.shoofly/ config and logs? [y/N]: " answer < /dev/tty
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    rm -rf ~/.shoofly/
    echo ""
    echo "Shoofly Basic fully removed."
  else
    echo ""
    echo "Shoofly Basic removed. Config and logs kept at ~/.shoofly/"
  fi
fi
