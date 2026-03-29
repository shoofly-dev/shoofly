#!/usr/bin/env bash
# Shoofly Uninstaller — removes Basic and Advanced cleanly
# Usage: curl -fsSL https://shoofly.dev/uninstall.sh | bash

set -euo pipefail

# ─── TTY guard — re-exec with a real TTY if piped from curl ──────────────────
if [ ! -t 0 ]; then
  SELF=$(mktemp /tmp/shoofly-uninstall-XXXXXX)
  curl -fsSL "https://shoofly.dev/uninstall.sh" -o "$SELF"
  chmod +x "$SELF"
  exec bash "$SELF" < /dev/tty
fi

echo ""
echo "🪰 Shoofly Uninstaller"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ─── Step 1: Detect what is installed ────────────────────────────────────────
TIER="unknown"
HAS_DAEMON=false
HAS_PLIST=false
HAS_SKILL_BASIC=false
HAS_SKILL_ADVANCED=false
HAS_CONFIG=false

if [ -f "$HOME/.shoofly/config.json" ]; then
  HAS_CONFIG=true
  TIER=$(jq -r '.tier // "unknown"' "$HOME/.shoofly/config.json" 2>/dev/null || echo "unknown")
fi

[ -f "$HOME/.shoofly/bin/shoofly-daemon" ] && HAS_DAEMON=true
[ -f "$HOME/Library/LaunchAgents/dev.shoofly.daemon.plist" ] && HAS_PLIST=true
[ -d "$HOME/.openclaw/skills/shoofly-basic" ] && HAS_SKILL_BASIC=true
[ -d "$HOME/.openclaw/skills/shoofly-advanced" ] && HAS_SKILL_ADVANCED=true

if ! $HAS_CONFIG && ! $HAS_DAEMON && ! $HAS_PLIST && ! $HAS_SKILL_BASIC && ! $HAS_SKILL_ADVANCED; then
  echo "  Nothing to remove — Shoofly is not installed."
  echo ""
  exit 0
fi

# ─── Step 2: Show what will be removed ───────────────────────────────────────
echo "Detected installation:"
if $HAS_CONFIG; then
  echo "  • Config:    ~/.shoofly/config.json (tier: $TIER)"
fi
if $HAS_DAEMON; then
  echo "  • Daemon:    ~/.shoofly/bin/shoofly-daemon"
fi
if $HAS_PLIST; then
  echo "  • LaunchAgent: ~/Library/LaunchAgents/dev.shoofly.daemon.plist"
fi
if $HAS_SKILL_BASIC; then
  echo "  • Skill:     ~/.openclaw/skills/shoofly-basic/"
fi
if $HAS_SKILL_ADVANCED; then
  echo "  • Skill:     ~/.openclaw/skills/shoofly-advanced/"
fi
echo ""

# ─── Step 3: Confirm ─────────────────────────────────────────────────────────
printf "Remove Shoofly? This cannot be undone. [y/N] "
read -r CONFIRM </dev/tty
case "$CONFIRM" in
  y|Y|yes|Yes|YES) ;;
  *)
    echo ""
    echo "Cancelled — nothing was removed."
    exit 0
    ;;
esac

echo ""

# ─── Step 4: Stop and remove daemon ─────────────────────────────────────────
if $HAS_PLIST; then
  launchctl unload "$HOME/Library/LaunchAgents/dev.shoofly.daemon.plist" 2>/dev/null || true
  rm -f "$HOME/Library/LaunchAgents/dev.shoofly.daemon.plist"
  echo "  ✓ LaunchAgent stopped and removed"
fi

pkill -f shoofly-daemon 2>/dev/null || true

# ─── Step 5: Remove binaries ────────────────────────────────────────────────
if [ -d "$HOME/.shoofly/bin" ]; then
  rm -rf "$HOME/.shoofly/bin/"
  echo "  ✓ Binaries removed (~/.shoofly/bin/)"
fi

# ─── Step 6: Remove OpenClaw skills ─────────────────────────────────────────
if $HAS_SKILL_BASIC; then
  rm -rf "$HOME/.openclaw/skills/shoofly-basic"
  echo "  ✓ Removed ~/.openclaw/skills/shoofly-basic/"
fi
if $HAS_SKILL_ADVANCED; then
  rm -rf "$HOME/.openclaw/skills/shoofly-advanced"
  echo "  ✓ Removed ~/.openclaw/skills/shoofly-advanced/"
fi

# ─── Step 7: Optional config/logs cleanup ────────────────────────────────────
echo ""
printf "Remove config and logs? (~/.shoofly/config.json, ~/.shoofly/logs/, ~/.shoofly/policy/) [y/N] "
read -r CLEAN </dev/tty
case "$CLEAN" in
  y|Y|yes|Yes|YES)
    rm -rf "$HOME/.shoofly/config.json" "$HOME/.shoofly/logs/" "$HOME/.shoofly/policy/" "$HOME/.shoofly/.env" "$HOME/.shoofly/audit.db" "$HOME/.shoofly/daemon.sock"
    echo "  ✓ Config, logs, policy, and data removed"
    # Remove .shoofly dir if empty
    rmdir "$HOME/.shoofly" 2>/dev/null || true
    FULL_CLEAN=true
    ;;
  *)
    FULL_CLEAN=false
    ;;
esac

# ─── Done ────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "${FULL_CLEAN:-false}" = true ]; then
  echo "✅  Shoofly fully removed."
else
  echo "✅  Shoofly removed. Config and logs kept at ~/.shoofly/ (safe to delete manually)."
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
