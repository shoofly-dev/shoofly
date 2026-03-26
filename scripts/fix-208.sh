#!/usr/bin/env bash
# fix-208.sh — Card 208 F1/F2/W1/W2 fixes
# Run from: /Users/leeroy/Projects/shoofly-workspace
set -euo pipefail

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_INSTALLER="$WORKSPACE/builds/shoofly-advanced/install.sh"
ADV_INSTALLER="$WORKSPACE/advanced/install.sh"
STATUS_BIN="$HOME/.shoofly/bin/shoofly-status"
HOOK_SRC="$HOME/.openclaw/extensions/shoofly-hook/index.ts"

echo "=== Card 208 F1/F2/W1/W2 Fix Script ==="
echo ""

# ─── F1: Bundle shoofly-hook in Advanced installer ────────────────────────────
echo "F1: Adding shoofly-hook bundle step to installers..."

HOOK_STEP='
# ─── Step 3b: Install shoofly-hook extension (Advanced: pre-execution blocking) ──
echo "Installing shoofly-hook extension..."
HOOK_DIR="$HOME/.openclaw/extensions/shoofly-hook"
mkdir -p "$HOOK_DIR"
curl -fsSL "$BASE_URL/extensions/shoofly-hook/index.ts" -o "$HOOK_DIR/index.ts"
echo "  ✓ shoofly-hook downloaded: $HOOK_DIR/index.ts"
# Register in openclaw.json if present
OPENCLAW_CFG="$HOME/.openclaw/openclaw.json"
if [[ -f "$OPENCLAW_CFG" ]]; then
  HOOK_PATH="$HOME/.openclaw/extensions/shoofly-hook/index.ts"
  ALREADY=$(jq --arg p "$HOOK_PATH" '"'"'(.plugins.entries // []) | map(.path) | contains([$p])'"'"'" "$OPENCLAW_CFG" 2>/dev/null || echo "false")
  if [[ "$ALREADY" != "true" ]]; then
    _TMP=$(mktemp)
    jq --arg p "$HOOK_PATH" '"'"'(.plugins.entries //= []) | .plugins.entries += [{"path": $p, "enabled": true}]'"'"'" "$OPENCLAW_CFG" > "$_TMP" && mv "$_TMP" "$OPENCLAW_CFG"
    echo "  ✓ shoofly-hook registered in openclaw.json"
  else
    echo "  ✓ shoofly-hook already registered in openclaw.json"
  fi
else
  echo "  WARN: openclaw.json not found — register hook manually"
fi
echo "  ✓ shoofly-hook extension installed"
'

# Insert after the line "# Advanced SKILL.md" download block (Step 3), before Step 4
# Find the marker: "# ─── Step 4:" and insert before it
for INSTALLER in "$BUILD_INSTALLER" "$ADV_INSTALLER"; do
  if [[ ! -f "$INSTALLER" ]]; then
    echo "  SKIP: $INSTALLER not found"
    continue
  fi
  if grep -q "shoofly-hook" "$INSTALLER"; then
    echo "  SKIP: $INSTALLER already has shoofly-hook step"
    continue
  fi
  # Insert Step 3b before Step 4
  python3 - "$INSTALLER" <<'PYEOF'
import sys, re
path = sys.argv[1]
with open(path) as f:
    content = f.read()

hook_step = '''
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

'''

# Insert before Step 4
marker = '# ─── Step 4:'
if marker in content:
    content = content.replace(marker, hook_step + marker, 1)
    with open(path, 'w') as f:
        f.write(content)
    print(f"  ✓ Hook step inserted in {path}")
else:
    print(f"  WARN: Could not find Step 4 marker in {path} — manual insertion needed")
PYEOF
done

# Also update the Done summary in build installer to mention hook
python3 - "$BUILD_INSTALLER" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    content = f.read()
old = '   Skill:       ~/.openclaw/skills/shoofly-advanced/SKILL.md'
new = '   Hook:        ~/.openclaw/extensions/shoofly-hook/index.ts\n   Skill:       ~/.openclaw/skills/shoofly-advanced/SKILL.md'
if old in content and '   Hook:' not in content:
    content = content.replace(old, new)
    with open(path, 'w') as f:
        f.write(content)
    print("  ✓ Done summary updated with hook path")
else:
    print("  SKIP: Done summary already updated or marker not found")
PYEOF

echo ""
echo "F1 complete."

# ─── F2 + W2: Fix shoofly-status ──────────────────────────────────────────────
echo ""
echo "F2+W2: Patching shoofly-status..."

python3 - "$STATUS_BIN" <<'PYEOF'
import sys, re
path = sys.argv[1]
with open(path) as f:
    content = f.read()

changed = []

# W2: Fix header to use dynamic tier label instead of hardcoded "Basic"
old_header = 'printf "🪰 Shoofly Basic  —  agent: %s  —  tier: %s\\n" "$AGENT_NAME" "$TIER"'
new_header = 'TIER_LABEL=$(echo "$TIER" | awk \'{print toupper(substr($0,1,1)) substr($0,2)}\')\nprintf "🪰 Shoofly %s  —  agent: %s\\n" "$TIER_LABEL" "$AGENT_NAME"'
if old_header in content:
    content = content.replace(old_header, new_header)
    changed.append("W2: header now uses dynamic tier label")
else:
    changed.append("W2: WARN — header pattern not found, manual fix needed")

# F2a: Add HOOK_ALERTS_LOG variable after ALERTS_LOG definition
old_alerts_log = 'ALERTS_LOG="$SHOOFLY_DIR/logs/alerts.log"'
new_alerts_log = 'ALERTS_LOG="$SHOOFLY_DIR/logs/alerts.log"\nHOOK_ALERTS_LOG="$SHOOFLY_DIR/logs/hook-alerts.log"'
if old_alerts_log in content and 'HOOK_ALERTS_LOG' not in content:
    content = content.replace(old_alerts_log, new_alerts_log)
    changed.append("F2a: HOOK_ALERTS_LOG variable added")
else:
    changed.append("F2a: SKIP — already present or pattern not found")

# F2b: Replace "(Basic: detect only)" blocked line with tier-aware block count
old_blocked = 'printf "%-16s —   (Basic: detect only)\\n" "Blocked today"'
new_blocked = (
    'if [[ "$TIER" == "advanced" && -f "$HOOK_ALERTS_LOG" ]]; then\n'
    '  BLOCKED_TODAY=$(awk -v cutoff="$TODAY" \'BEGIN{c=0} {if(index($0,cutoff)>0)c++} END{print c}\' "$HOOK_ALERTS_LOG" 2>/dev/null || echo 0)\n'
    '  printf "%-16s —   %s (hook blocks today)\\n" "Blocked today" "$BLOCKED_TODAY"\n'
    'else\n'
    '  printf "%-16s —   (Basic: detect only)\\n" "Blocked today"\n'
    'fi'
)
if old_blocked in content:
    content = content.replace(old_blocked, new_blocked)
    changed.append("F2b: Blocked-today now reads hook-alerts.log for Advanced tier")
else:
    changed.append("F2b: WARN — blocked-today pattern not found, manual fix needed")

# F2c: Merge hook alerts into today's alert display
# Find the awk pass over ALERTS_LOG for today's count and add hook log to it
old_awk = 'awk -v cutoff="$TODAY"'
if old_awk in content and 'HOOK_ALERTS_LOG' in content:
    # Replace first awk invocation on ALERTS_LOG to also read HOOK_ALERTS_LOG
    # Pattern: cat "$ALERTS_LOG" | awk   OR   awk ... "$ALERTS_LOG"
    old_cat = 'cat "$ALERTS_LOG"'
    new_cat = '{ [[ -f "$ALERTS_LOG" ]] && cat "$ALERTS_LOG"; [[ -f "$HOOK_ALERTS_LOG" ]] && cat "$HOOK_ALERTS_LOG"; }'
    if old_cat in content:
        content = content.replace(old_cat, new_cat, 1)  # only first occurrence (today's count)
        changed.append("F2c: Alert count now merges daemon + hook logs")
    else:
        changed.append("F2c: WARN — cat ALERTS_LOG pattern not found; check awk invocation manually")

with open(path, 'w') as f:
    f.write(content)

for c in changed:
    print(f"  {c}")
PYEOF

echo ""
echo "F2+W2 complete."

# ─── W1: Triage DE check tool name scope in shoofly-hook ─────────────────────
echo ""
echo "W1: Expanding DE check to cover Bash/bash/shell tool names..."

python3 - "$HOOK_SRC" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    content = f.read()

old_check = 'if (toolName !== "exec" && toolName !== "Exec") return null;'
new_check = (
    '// Cover all exec-style tool names: OpenClaw normalizes to "exec" but handle raw names defensively\n'
    '  const EXEC_TOOLS = new Set(["exec", "Exec", "bash", "Bash", "shell", "Shell"]);\n'
    '  if (!EXEC_TOOLS.has(toolName)) return null;'
)

if old_check in content:
    content = content.replace(old_check, new_check)
    with open(path, 'w') as f:
        f.write(content)
    print("  ✓ W1: DE check now covers exec/Exec/bash/Bash/shell/Shell tool names")
else:
    print("  WARN W1: pattern not found — check index.ts manually")
PYEOF

echo ""
echo "=== Validation ==="
echo ""

echo -n "bash -n builds/shoofly-advanced/install.sh: "
bash -n "$BUILD_INSTALLER" && echo "PASS" || echo "FAIL"

if [[ -f "$ADV_INSTALLER" ]]; then
  echo -n "bash -n advanced/install.sh: "
  bash -n "$ADV_INSTALLER" && echo "PASS" || echo "FAIL"
fi

echo -n "bash -n shoofly-status: "
bash -n "$STATUS_BIN" && echo "PASS" || echo "FAIL"

echo ""
echo "=== Done ==="
echo "Files touched:"
echo "  $BUILD_INSTALLER"
[[ -f "$ADV_INSTALLER" ]] && echo "  $ADV_INSTALLER"
echo "  $STATUS_BIN"
echo "  $HOOK_SRC"
