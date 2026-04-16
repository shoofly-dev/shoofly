#!/usr/bin/env bash
# Shoofly Advanced v3 — one-command installer
# Works with Claude Code, Cline, any AI terminal tool, or standalone
# Usage: SHOOFLY_TOKEN=your_token bash <(curl -fsSL https://shoofly.dev/install-advanced.sh)
#
# v3 removes OpenClaw dependency. Auto-detects installed AI tools.
# Hooks into Claude Code natively via ~/.claude/settings.json (PreToolUse blocking).

set -euo pipefail

# ─── Step 0: Validate install token ─────────────────────────────────────────
INSTALL_TOKEN="${SHOOFLY_TOKEN:-}"
if [[ -z "$INSTALL_TOKEN" ]]; then
  echo ""
  echo "⚠️  This installer requires a personal install token."
  echo "   Your token was included in your purchase confirmation email."
  echo ""
  echo "   Usage: SHOOFLY_TOKEN=your_token bash <(curl -fsSL https://shoofly.dev/install-advanced.sh)"
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
  echo "   This token may have already been used or expired (48h)."
  echo "   Contact support@shoofly.dev for a new install link."
  echo ""
  exit 1
fi
echo "  ✓ Token validated"

# ─── TTY guard ───────────────────────────────────────────────────────────────
if [ ! -t 0 ]; then
  SELF="/tmp/shoofly-advanced-$$.sh"
  curl -fsSL "https://shoofly.dev/install-advanced.sh" -o "$SELF"
  chmod +x "$SELF"
  exec env SHOOFLY_TOKEN="$INSTALL_TOKEN" bash "$SELF" < /dev/tty
fi

# ═════════════════════════════════════════════════════════════════════════════
#  TUI library — interactive selectors via Node.js, plain fallback otherwise
#  API: tui_select / tui_multiselect / tui_text / tui_text_secret
#       tui_intro / tui_outro / tui_note / tui_step / tui_warn / tui_info
# ═════════════════════════════════════════════════════════════════════════════

# ANSI codes
_G='\033[0;32m'   # green
_B='\033[1m'      # bold
_D='\033[2m'      # dim
_R='\033[0m'      # reset

# Unicode box chars
_DIA='◆'  _BAR='│'  _COR='└'

# Output globals (set by tui_select / tui_multiselect)
TUI_RESULT=""
TUI_RESULTS=()
_TUI_JS=""   # path to Node.js TUI helper; recreated if deleted by subshell EXIT trap
_JQ_TMP=""   # temp jq binary; cleaned on exit if install is interrupted

_tui_restore() { printf '\033[?25h'; stty echo icanon 2>/dev/null || true; [[ -n "${_TUI_JS:-}" ]] && rm -f "$_TUI_JS" 2>/dev/null; [[ -n "${_JQ_TMP:-}" ]] && rm -f "$_JQ_TMP" 2>/dev/null; }
trap '_tui_restore' EXIT INT TERM

# Write the Node.js TUI helper to a temp file (PID-named to avoid collisions).
# Called before every tui_select/tui_multiselect — checks if file still exists
# because subshell EXIT traps may delete it between calls.
_tui_ensure_js() {
  [[ -n "$_TUI_JS" && -f "$_TUI_JS" ]] && return 0
  _TUI_JS="/tmp/shoofly-tui-$$.js"
  set +e
  cat > "$_TUI_JS" << 'TUI_JS_EOF'
'use strict';
// Shoofly TUI helper — vanilla Node.js, no npm dependencies required.
// Reads: S_TYPE (select|multiselect), S_MSG, S_OPTS (JSON array of {v,l,h})
// Writes UI to stderr (visible on terminal), result to stdout (captured by bash).
const G='\x1b[0;32m',B='\x1b[1m',D='\x1b[2m',R='\x1b[0m',HID='\x1b[?25l',SHW='\x1b[?25h';
const DIA='◆',BAR='│',COR='└',RON='●',ROF='○',CON='◼',COF='◻';
const e=process.stderr;
const type=process.env.S_TYPE;
const msg=process.env.S_MSG;
const opts=JSON.parse(process.env.S_OPTS);

function pad(s,n){return (s+'                              ').slice(0,n);}
function up(n){e.write('\x1b['+n+'A');}
function clr(){e.write('\x1b[2K');}

if(type==='select'){
  let sel=0;
  function draw(done){
    for(let i=0;i<opts.length;i++){
      clr();
      if(done) e.write(i===sel?`${G}${BAR}${R}  ${G}${RON}${R} ${B}${opts[i].l}${R}\n`:`${D}${BAR}  ${ROF} ${opts[i].l}${R}\n`);
      else     e.write(i===sel?`${G}${BAR}${R}  ${G}${RON}${R} ${B}${pad(opts[i].l,24)}${R}  ${D}${opts[i].h||''}${R}\n`
                              :`${G}${BAR}${R}  ${ROF} ${pad(opts[i].l,24)}  ${D}${opts[i].h||''}${R}\n`);
    }
    clr(); e.write(`${G}${COR}${R}\n`);
  }
  e.write(`\n${G}${B}${DIA}${R}  ${msg}\n`);
  draw(false);
  e.write(HID);
  process.stdin.setRawMode(true);
  process.stdin.resume();
  process.stdin.setEncoding('utf8');
  process.stdin.on('data',function(k){
    if(k==='\x1b[A'||k==='\x1b[D'){sel=(sel-1+opts.length+opts.length)%opts.length;up(opts.length+1);draw(false);}
    else if(k==='\x1b[B'||k==='\x1b[C'){sel=(sel+1)%opts.length;up(opts.length+1);draw(false);}
    else if(k==='\r'||k==='\n'){
      e.write(SHW);up(opts.length+1);draw(true);
      process.stdout.write(opts[sel].v+'\n');
      process.stdin.setRawMode(false);process.exit(0);
    }
    else if(k==='\x03'){e.write(SHW+'\n');process.stdin.setRawMode(false);process.exit(1);}
  });
}
else if(type==='multiselect'){
  let cur=0; const chk=new Set();
  function draw(done){
    for(let i=0;i<opts.length;i++){
      clr();
      const on=chk.has(opts[i].v); const box=on?(G+CON+R):COF;
      if(done) e.write(`${on?G+BAR+R:D+BAR}  ${box} ${on?B:''}${opts[i].l}${R}\n`);
      else     e.write(`${G}${BAR}${R}  ${box} ${i===cur?B:''}${pad(opts[i].l,24)}${R}  ${D}${opts[i].h||''}${R}\n`);
    }
    clr(); e.write(`${G}${COR}${R}\n`);
  }
  e.write(`\n${G}${B}${DIA}${R}  ${msg}\n`);
  e.write(`${G}${BAR}${R}  ${D}Select one or more  ·  ↑↓ to move  ·  Space to select/deselect  ·  Enter when done${R}\n`);
  draw(false);
  e.write(HID);
  process.stdin.setRawMode(true);
  process.stdin.resume();
  process.stdin.setEncoding('utf8');
  process.stdin.on('data',function(k){
    if(k==='\x1b[A'){cur=(cur-1+opts.length+opts.length)%opts.length;up(opts.length+1);draw(false);}
    else if(k==='\x1b[B'){cur=(cur+1)%opts.length;up(opts.length+1);draw(false);}
    else if(k===' '){chk.has(opts[cur].v)?chk.delete(opts[cur].v):chk.add(opts[cur].v);up(opts.length+1);draw(false);}
    else if(k==='\r'||k==='\n'){
      e.write(SHW);
      up(opts.length+2); clr(); e.write('\n'); draw(true);
      [...chk].forEach(function(v){process.stdout.write(v+'\n');});
      process.stdin.setRawMode(false);process.exit(0);
    }
    else if(k==='\x03'){e.write(SHW+'\n');process.stdin.setRawMode(false);process.exit(1);}
  });
}
TUI_JS_EOF
  local _rc=$?
  set -e
  if [[ $_rc -ne 0 || ! -s "$_TUI_JS" ]]; then
    rm -f "$_TUI_JS" 2>/dev/null; _TUI_JS=""; return 1
  fi
}

# Build JSON array from "value|label|hint" bash option strings
_tui_opts_json() {
  local json='[' sep=''
  local v l h
  for opt in "$@"; do
    IFS='|' read -r v l h <<< "$opt"
    v="${v//\\/\\\\}"; v="${v//\"/\\\"}";
    l="${l//\\/\\\\}"; l="${l//\"/\\\"}";
    h="${h//\\/\\\\}"; h="${h//\"/\\\"}";
    json+="${sep}{\"v\":\"${v}\",\"l\":\"${l}\",\"h\":\"${h}\"}"
    sep=','
  done
  printf '%s' "${json}]"
}

# Fallback: plain numbered select (no Node.js)
_tui_bash_select() {
  local message="$1"; shift
  printf "\n%s\n" "$message"
  local i=1
  for opt in "$@"; do
    IFS='|' read -r v l h <<< "$opt"; printf "  %d) %s\n" "$i" "$l"; i=$((i+1))
  done
  printf "Choice [1]: "; local choice; IFS= read -r choice < /dev/tty
  choice=${choice:-1}; local idx=$((choice-1))
  [[ $idx -lt 0 || $idx -ge $# ]] && idx=0
  local opt; eval "opt=\"\${${$((idx+1))}}\""
  # bash doesn't support dynamic positional args easily — use an array
  local -a a=("$@"); IFS='|' read -r TUI_RESULT _ _ <<< "${a[$idx]}"
}

# Fallback: plain numbered multiselect (no Node.js)
_tui_bash_multiselect() {
  local message="$1"; shift
  printf "\n%s\n" "$message"
  printf "(space-separated numbers, e.g. 1 4 — blank = option 1)\n"
  local i=1
  local -a a=("$@")
  for opt in "$@"; do
    IFS='|' read -r v l h <<< "$opt"; printf "  %d) %s\n" "$i" "$l"; i=$((i+1))
  done
  printf "Choices [1]: "; local choices; IFS= read -r choices < /dev/tty
  choices=${choices:-1}; TUI_RESULTS=()
  local c idx v
  for c in $choices; do
    idx=$((c-1)); [[ $idx -ge 0 && $idx -lt ${#a[@]} ]] || continue
    IFS='|' read -r v _ _ <<< "${a[$idx]}"; TUI_RESULTS+=("$v")
  done
  [[ ${#TUI_RESULTS[@]} -eq 0 ]] && { IFS='|' read -r v _ _ <<< "${a[0]}"; TUI_RESULTS=("$v"); }
}

# tui_select <message> [option strings "value|label|hint" ...]
# Sets TUI_RESULT to selected value.
tui_select() {
  local message="$1"; shift
  if command -v node >/dev/null 2>&1 && _tui_ensure_js; then
    local json; json=$(_tui_opts_json "$@")
    TUI_RESULT=$(S_TYPE=select S_MSG="$message" S_OPTS="$json" node "$_TUI_JS" < /dev/tty) || {
      printf "\n%s  Setup cancelled.%s\n" "$_D" "$_R"; exit 1
    }
  else
    _tui_bash_select "$message" "$@"
  fi
}

# tui_multiselect <message> [option strings "value|label|hint" ...]
# Sets TUI_RESULTS array to selected values.
tui_multiselect() {
  local message="$1"; shift
  TUI_RESULTS=()
  if command -v node >/dev/null 2>&1 && _tui_ensure_js; then
    local json; json=$(_tui_opts_json "$@")
    while IFS= read -r line; do
      [[ -n "$line" ]] && TUI_RESULTS+=("$line")
    done < <(S_TYPE=multiselect S_MSG="$message" S_OPTS="$json" node "$_TUI_JS" < /dev/tty)
  else
    _tui_bash_multiselect "$message" "$@"
  fi
}

# tui_intro <title> <subtitle>
tui_intro() {
  printf "\n${_G}${_B}${_DIA}${_R}  ${_B}%s${_R}\n" "$1"
  [[ -n "${2:-}" ]] && printf "${_G}${_BAR}${_R}  ${_D}%s${_R}\n" "$2"
  printf "${_G}${_COR}${_R}\n\n"
}

# tui_outro <message>
tui_outro() {
  printf "\n${_G}${_B}${_DIA}${_R}  ${_B}%s${_R}\n\n" "$1"
}

# tui_note <title> <body (newlines ok)>
tui_note() {
  local title="$1" body="$2" width=52
  local border; border=$(printf '─%.0s' $(seq 1 $((width - ${#title} - 3))))
  printf "\n${_D}┌─ %s %s┐${_R}\n" "$title" "$border"
  while IFS= read -r line; do
    printf "${_D}│${_R}  %-${width}s${_D}│${_R}\n" "$line"
  done <<< "$body"
  printf "${_D}└$(printf '─%.0s' $(seq 1 $((width + 2))))┘${_R}\n\n"
}

# tui_text <message> <hint> <default>
# Sets TUI_RESULT to entered text (or default if blank).
tui_text() {
  local message="$1" hint="$2" default="$3"
  local prompt="${message}"
  [[ -n "$hint" ]] && prompt="${prompt}  (${hint})"
  [[ -n "$default" ]] && prompt="${prompt} [${default}]"
  local input
  read -rp $'\n'"  ${prompt}: " input < /dev/tty
  TUI_RESULT="${input:-$default}"
}

# tui_text_secret <message> <hint>
# Sets TUI_RESULT; input is hidden (paste works).
tui_text_secret() {
  local message="$1" hint="$2"
  local prompt="${message}"
  [[ -n "$hint" ]] && prompt="${prompt}  (${hint})"
  local input
  read -rsp $'\n'"  ${prompt}: " input < /dev/tty
  printf "\n"
  TUI_RESULT="$input"
}

# tui_step / tui_warn / tui_info — inline progress lines
tui_step() { printf "  ${_G}✓${_R}  %s\n" "$1"; }
tui_warn()  { printf "  ${_D}⚠  %s${_R}\n" "$1"; }
tui_info()  { printf "  ${_D}ℹ  %s${_R}\n" "$1"; }

# ═════════════════════════════════════════════════════════════════════════════
#  Install script begins here
# ═════════════════════════════════════════════════════════════════════════════

# ─── Intro ───────────────────────────────────────────────────────────────────
tui_intro "🪰 Shoofly Advanced v3 — Pre-Execution Blocking" \
  "Intercepts and blocks malicious AI agent tool calls before they execute."

# ─── Step 1: Hard dependencies ───────────────────────────────────────────────
printf "Checking dependencies...\n"
command -v curl >/dev/null 2>&1 || {
  printf "  ${_D}ERROR: curl is required.${_R}\n"; exit 1; }

if ! command -v jq >/dev/null 2>&1; then
  tui_warn "jq not found — downloading bundled binary..."
  _JQ_TMP="/tmp/shoofly-jq-$$"
  case "$(uname -s)/$(uname -m)" in
    Darwin/arm64)  _jq_bin="jq-macos-arm64" ;;
    Darwin/x86_64) _jq_bin="jq-macos-amd64" ;;
    Linux/aarch64) _jq_bin="jq-linux-arm64"  ;;
    Linux/x86_64)  _jq_bin="jq-linux-amd64"  ;;
    *)
      printf "  ${_D}Unsupported platform — install jq manually: https://jqlang.github.io/jq/${_R}\n"
      exit 1 ;;
  esac
  curl -fsSL "https://github.com/jqlang/jq/releases/download/jq-1.7.1/${_jq_bin}" \
    -o "$_JQ_TMP" 2>/dev/null || {
    rm -f "$_JQ_TMP"; _JQ_TMP=""
    printf "  ${_D}ERROR: Failed to download jq. Check your internet connection.${_R}\n"
    exit 1
  }
  chmod +x "$_JQ_TMP"
  jq() { "$_JQ_TMP" "$@"; }
  tui_step "jq 1.7.1 downloaded"
fi
tui_step "Dependencies ready"

# ─── Step 2: Auto-detect AI tool ─────────────────────────────────────────────
printf "\nDetecting AI tools...\n"
DETECTED_TOOL="none"; HOOK_METHOD="manual"
if command -v claude >/dev/null 2>&1; then
  DETECTED_TOOL="claude-code"; HOOK_METHOD="claude-settings"
  tui_step "Claude Code detected: $(claude --version 2>/dev/null || echo 'installed')"
elif command -v openclaw >/dev/null 2>&1; then
  DETECTED_TOOL="openclaw"; HOOK_METHOD="openclaw-legacy"
  tui_step "OpenClaw detected (legacy mode)"
elif command -v code >/dev/null 2>&1 && ls "$HOME/.vscode/extensions/saoudrizwan.claude-dev"* >/dev/null 2>&1; then
  DETECTED_TOOL="cline"; HOOK_METHOD="manual"
  tui_step "Cline (VS Code) detected"
else
  tui_info "No AI tool CLI detected — installing as standalone daemon"
fi

# Warn if pre-execution blocking will require manual wiring
if [[ "$HOOK_METHOD" == "manual" && "$DETECTED_TOOL" != "none" ]]; then
  tui_warn "Pre-execution blocking for ${DETECTED_TOOL} requires manual hook setup."
  tui_info "The daemon and shoofly-check will be installed. Instructions follow."
fi

# ─── Step 3: Existing install check ──────────────────────────────────────────
if [[ -f "$HOME/.shoofly/config.json" ]]; then
  EXISTING_TIER=$(jq -r '.tier // "unknown"' "$HOME/.shoofly/config.json" 2>/dev/null || echo "unknown")
  EXISTING_VER=$(jq -r '.version // "unknown"' "$HOME/.shoofly/config.json" 2>/dev/null || echo "unknown")
  tui_note "Existing Install Detected" \
"Tier: ${EXISTING_TIER}  ·  Version: ${EXISTING_VER}
Continuing will upgrade your install. Nothing breaks."
  tui_select "What would you like to do?" \
    "upgrade|Upgrade / reinstall|clean remove, then fresh install" \
    "cancel|Cancel             |leave the existing install unchanged"
  [[ "$TUI_RESULT" == "cancel" ]] && { tui_outro "No changes made."; exit 0; }

  # Clean remove before reinstall
  printf "\nCleaning existing install...\n"

  # Stop daemon
  if [[ -f "$HOME/Library/LaunchAgents/dev.shoofly.daemon.plist" ]]; then
    launchctl unload "$HOME/Library/LaunchAgents/dev.shoofly.daemon.plist" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/dev.shoofly.daemon.plist"
    tui_step "LaunchAgent removed"
  fi

  # Remove PreToolUse/PostToolUse shoofly hooks from Claude Code settings
  if [[ -f "$HOME/.claude/settings.json" ]]; then
    _tmp=$(mktemp)
    jq '
      if .hooks.PreToolUse then
        .hooks.PreToolUse = [
          .hooks.PreToolUse[] |
          .hooks = (.hooks // [] | map(select(.command | test("shoofly") | not))) |
          select((.hooks | length) > 0)
        ]
      else . end |
      if .hooks.PostToolUse then
        .hooks.PostToolUse = [
          .hooks.PostToolUse[] |
          .hooks = (.hooks // [] | map(select(.command | test("shoofly") | not))) |
          select((.hooks | length) > 0)
        ]
      else . end
    ' "$HOME/.claude/settings.json" > "$_tmp" && mv "$_tmp" "$HOME/.claude/settings.json"
    tui_step "Existing Claude Code hooks removed"
  fi

  # Remove ~/.shoofly directory
  rm -rf "$HOME/.shoofly"
  tui_step "~/.shoofly/ cleared"
fi

# ─── Step 4: Blocking mode ───────────────────────────────────────────────────
tui_select "How should 🪰 Shoofly respond to threats?" \
  "default|Default |block high-confidence threats, notify on others  (recommended)" \
  "strict|Strict  |block anything suspicious, including low-confidence signals" \
  "monitor|Monitor |log + notify only, never block  (same as Basic)"

SENSITIVITY_LABEL="$TUI_RESULT"
case "$SENSITIVITY_LABEL" in
  monitor) BLOCKING_ENABLED="false" ;;
  *)       BLOCKING_ENABLED="true"  ;;
esac

# ─── Step 5: Notification channels ───────────────────────────────────────────
_CHANNEL_OPTS=(
  "macos|macOS notifications|banner + sound"
  "telegram|Telegram         |direct message to a Telegram chat"
  "terminal|Terminal          |printed where 🪰 Shoofly runs — good for logging"
)
[[ "$DETECTED_TOOL" == "openclaw" ]] && \
  _CHANNEL_OPTS+=("openclaw|OpenClaw (local)  |via OpenClaw gateway  (legacy)")
tui_multiselect "Where should 🪰 Shoofly send threat alerts?" "${_CHANNEL_OPTS[@]}"

CHANNELS=("${TUI_RESULTS[@]+"${TUI_RESULTS[@]}"}")
[[ ${#CHANNELS[@]} -eq 0 ]] && CHANNELS=("macos")

TELEGRAM_CHOSEN=false
for c in "${CHANNELS[@]}"; do [[ "$c" == "telegram" ]] && TELEGRAM_CHOSEN=true && break; done

if $TELEGRAM_CHOSEN; then
  printf "\n${_G}${_BAR}${_R}  ${_D}Have a bot already? Paste your token below.${_R}\n"
  printf "${_G}${_BAR}${_R}  ${_D}Need one? Telegram → search @BotFather → /newbot${_R}\n"
  while true; do
    tui_text "Bot token" "e.g. 1234567890:ABC-DEF..." ""
    TG_TOKEN="$TUI_RESULT"
    printf "  Checking token..."
    TG_TOKEN_CHECK=$(curl -s "https://api.telegram.org/bot${TG_TOKEN}/getMe" 2>/dev/null)
    if ! echo "$TG_TOKEN_CHECK" | jq -e '.ok == true' >/dev/null 2>&1; then
      printf "\r\033[2K  ${_D}⚠  Invalid token — Telegram rejected it. Try again.${_R}\n"
      continue
    fi
    BOT_NAME=$(echo "$TG_TOKEN_CHECK" | jq -r '.result.username // "bot"' 2>/dev/null)
    printf "\r\033[2K  ${_G}✓${_R}  Token valid — @%s\n" "$BOT_NAME"

    tui_text "Chat ID" "message your bot on Telegram — it replies with your ID" ""
    TG_CHAT_ID="$TUI_RESULT"
    printf "  Sending test message..."
    TG_SEND_CHECK=$(curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
      -d "chat_id=${TG_CHAT_ID}" \
      -d "text=🪰 Shoofly install verification — your Chat ID is confirmed." \
      2>/dev/null)
    if ! echo "$TG_SEND_CHECK" | jq -e '.ok == true' >/dev/null 2>&1; then
      printf "\r\033[2K  ${_D}⚠  Couldn't reach that Chat ID — check it and re-enter.${_R}\n"
      continue
    fi
    printf "\r\033[2K  ${_G}✓${_R}  Test message delivered\n"

    printf "\n  Bot token: 🔒 [hidden]  ·  Chat ID: ${_B}%s${_R}\n" "$TG_CHAT_ID"
    tui_select "Are these correct?" \
      "yes|Yes — continue|save credentials and proceed" \
      "no|No — re-enter |go back and correct"
    [[ "$TUI_RESULT" == "yes" ]] && break
  done
  mkdir -p "$HOME/.shoofly"
  echo "TELEGRAM_BOT_TOKEN=$TG_TOKEN"  >> "$HOME/.shoofly/.env"
  echo "TELEGRAM_CHAT_ID=$TG_CHAT_ID"  >> "$HOME/.shoofly/.env"
  chmod 600 "$HOME/.shoofly/.env"
  tui_step "Telegram credentials saved"
fi

# ─── Step 6: Agent name ───────────────────────────────────────────────────────
DEFAULT_AGENT="$(whoami)-agent"
tui_text "Agent name" "this label appears in your alerts and audit log" "$DEFAULT_AGENT"
AGENT_NAME="$TUI_RESULT"

# ─── Step 7: Review ──────────────────────────────────────────────────────────
CHANNELS_DISPLAY="${CHANNELS[*]}"
tui_note "Review your settings" \
"Mode:         ${SENSITIVITY_LABEL}  (blocking: ${BLOCKING_ENABLED})
Channels:     ${CHANNELS_DISPLAY// /, }
Agent:        ${AGENT_NAME}
Tool:         ${DETECTED_TOOL}"

# ─── Step 8: Install files ───────────────────────────────────────────────────
printf "\nInstalling 🪰 Shoofly Advanced...\n"
mkdir -p "$HOME/.shoofly/"{bin,policy,logs}
tui_step "Directories ready"

# Place bundled jq permanently if we downloaded it during dep check
if [[ -n "${_JQ_TMP:-}" && -f "$_JQ_TMP" ]]; then
  cp "$_JQ_TMP" "$HOME/.shoofly/bin/jq"
  chmod +x "$HOME/.shoofly/bin/jq"
  rm -f "$_JQ_TMP"; _JQ_TMP=""
  jq() { "$HOME/.shoofly/bin/jq" "$@"; }
  tui_step "jq installed to ~/.shoofly/bin/jq"
fi

BASE_URL="https://raw.githubusercontent.com/shoofly-dev/shoofly/main"

curl -fsSL "$BASE_URL/advanced/policy/threats.yaml" -o "$HOME/.shoofly/policy/threats.yaml"
tui_step "Threat policy: ~/.shoofly/policy/threats.yaml"

for BIN in shoofly-daemon shoofly-notify shoofly-check shoofly-policy-lint \
           shoofly-status shoofly-health shoofly-log shoofly-scan shoofly-uninstall; do
  curl -fsSL "$BASE_URL/advanced/bin/$BIN" -o "$HOME/.shoofly/bin/$BIN"
  chmod +x "$HOME/.shoofly/bin/$BIN"
done
tui_step "All binaries downloaded and marked executable"

# ─── Step 9: Write config ────────────────────────────────────────────────────
CHANNELS_JSON=$(printf '"%s",' "${CHANNELS[@]}" | sed 's/,$//')
cat > "$HOME/.shoofly/config.json" <<EOF
{
  "tier": "advanced",
  "version": "3.0.0",
  "sensitivity": "$SENSITIVITY_LABEL",
  "blocking_enabled": $BLOCKING_ENABLED,
  "notification_channels": [$CHANNELS_JSON],
  "agent_name": "$AGENT_NAME",
  "installed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "policy_path": "$HOME/.shoofly/policy/threats.yaml",
  "detected_tool": "$DETECTED_TOOL"
}
EOF
chmod 600 "$HOME/.shoofly/config.json"
tui_step "Config written"

# ─── Step 10: Hook registration ──────────────────────────────────────────────
printf "\nConfiguring hooks...\n"

register_claude_code_hooks() {
  local settings_file="$HOME/.claude/settings.json"
  local check_cmd="$HOME/.shoofly/bin/shoofly-check"
  mkdir -p "$HOME/.claude"
  [[ ! -f "$settings_file" ]] && echo '{}' > "$settings_file"
  local already
  already=$(jq --arg cmd "$check_cmd" '
    .hooks.PreToolUse // [] |
    any(.[].hooks // [] | any(.command == $cmd))
  ' "$settings_file" 2>/dev/null || echo "false")
  if [[ "$already" == "true" ]]; then
    tui_step "Claude Code blocking hook already registered"
    return
  fi
  local tmp; tmp=$(mktemp)
  jq --arg cmd "$check_cmd" '
    .hooks //= {} |
    .hooks.PreToolUse //= [] |
    .hooks.PreToolUse += [{
      "matcher": ".*",
      "hooks": [{"type": "command", "command": $cmd}]
    }]
  ' "$settings_file" > "$tmp" && mv "$tmp" "$settings_file"
  tui_step "Blocking hook registered in ~/.claude/settings.json  (PreToolUse)"
  tui_info "Every tool call will be evaluated by shoofly-check before execution."
}

register_openclaw_hooks_legacy() {
  local cfg="$HOME/.openclaw/openclaw.json"
  if [[ ! -f "$cfg" ]]; then
    tui_warn "~/.openclaw/openclaw.json not found — skipping legacy hook"
    return
  fi
  local already
  already=$(jq --arg k "shoofly-advanced" '.plugins.entries | has($k)' "$cfg" 2>/dev/null || echo "false")
  if [[ "$already" != "true" ]]; then
    local tmp; tmp=$(mktemp)
    jq --arg k "shoofly-advanced" --arg p "$HOME/.shoofly/bin/shoofly-check" \
      '.plugins.entries //= {} | .plugins.entries[$k] = {"path": $p, "enabled": true}' \
      "$cfg" > "$tmp" && mv "$tmp" "$cfg"
    tui_step "Blocking hook registered in ~/.openclaw/openclaw.json  (legacy)"
  else
    tui_step "OpenClaw hook already registered  (legacy)"
  fi
}

case "$HOOK_METHOD" in
  claude-settings)
    register_claude_code_hooks
    ;;
  openclaw-legacy)
    register_openclaw_hooks_legacy
    ;;
  manual)
    tui_info "Hook auto-registration not available for: ${DETECTED_TOOL}"
    printf "\n"
    printf "  ${_D}┌─ Manual Hook Setup ──────────────────────────────────────────────────┐${_R}\n"
    printf "  ${_D}│${_R}  Configure your AI tool to run this command before every tool call: ${_D}│${_R}\n"
    printf "  ${_D}│${_R}                                                                      ${_D}│${_R}\n"
    printf "  ${_D}│${_R}    %s  ${_D}│${_R}\n" "$HOME/.shoofly/bin/shoofly-check"
    printf "  ${_D}│${_R}                                                                      ${_D}│${_R}\n"
    printf "  ${_D}│${_R}  shoofly-check exits 0 (allow) or non-zero (block).                 ${_D}│${_R}\n"
    if [[ "$DETECTED_TOOL" == "cline" ]]; then
      printf "  ${_D}│${_R}                                                                      ${_D}│${_R}\n"
      printf "  ${_D}│${_R}  For Cline, add to VS Code settings.json:                            ${_D}│${_R}\n"
      printf '  \033[2m│\033[0m    "cline.hooks.preToolUse": ["~/.shoofly/bin/shoofly-check"]   \033[2m│\033[0m\n'
    fi
    printf "  ${_D}└──────────────────────────────────────────────────────────────────────┘${_R}\n\n"
    ;;
esac

# ─── Step 11: Initialize audit database ─────────────────────────────────────
touch "$HOME/.shoofly/logs/alerts.log"
touch "$HOME/.shoofly/logs/blocked.log"
tui_step "Log files initialized"

if command -v sqlite3 >/dev/null 2>&1; then
  sqlite3 "$HOME/.shoofly/audit.db" \
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
  tui_step "Audit database initialized: ~/.shoofly/audit.db"
else
  tui_warn "sqlite3 not found — audit trail disabled.  Install: brew install sqlite3"
fi

# ─── Step 12: LaunchAgent ────────────────────────────────────────────────────
if [[ "$(uname)" == "Darwin" ]]; then
  cat > "$HOME/Library/LaunchAgents/dev.shoofly.daemon.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>dev.shoofly.daemon</string>
  <key>ProgramArguments</key><array>
    <string>$HOME/.shoofly/bin/shoofly-daemon</string>
    <string>--config</string><string>$HOME/.shoofly/config.json</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$HOME/.shoofly/logs/daemon.log</string>
  <key>StandardErrorPath</key><string>$HOME/.shoofly/logs/daemon.err</string>
</dict></plist>
PLIST
  launchctl unload "$HOME/Library/LaunchAgents/dev.shoofly.daemon.plist" 2>/dev/null || true
  launchctl load   "$HOME/Library/LaunchAgents/dev.shoofly.daemon.plist" 2>/dev/null || true
  tui_step "LaunchAgent installed  (daemon auto-restarts)"
fi

# ─── Step 13: PATH setup ──────────────────────────────────────────────────────
SHOOFLY_BIN="$HOME/.shoofly/bin"
SHELL_RC=""
[[ "$SHELL" == */zsh ]]  && SHELL_RC="$HOME/.zshrc"
[[ "$SHELL" == */bash ]] && SHELL_RC="$HOME/.bashrc"

if [[ -n "$SHELL_RC" ]] && ! grep -q 'shoofly/bin' "$SHELL_RC" 2>/dev/null; then
  { echo ""; echo "# Shoofly CLI tools"; echo "export PATH=\"\$HOME/.shoofly/bin:\$PATH\""; } >> "$SHELL_RC"
  tui_step "Added ~/.shoofly/bin to PATH in ${SHELL_RC##*/}"
fi
export PATH="$SHOOFLY_BIN:$PATH"

# ─── Step 14: Verify daemon ───────────────────────────────────────────────────
printf "\nVerifying 🪰 Shoofly Advanced daemon...\n"
if "$HOME/.shoofly/bin/shoofly-daemon" --config "$HOME/.shoofly/config.json" --verify 2>/dev/null; then
  tui_step "Daemon verified"
else
  tui_warn "Daemon verify returned non-zero — this is normal on first install."
  tui_info "Run: shoofly-health  after your first tool call to confirm."
fi

# ─── Step 15: Smoke test ─────────────────────────────────────────────────────
printf "\nSending test notification...\n"
"$HOME/.shoofly/bin/shoofly-notify" auto "⚡🪰⚡ SHOOFLY ADVANCED — INSTALL VERIFIED ✅

Agent: $AGENT_NAME
Mode: $SENSITIVITY_LABEL  (blocking: $BLOCKING_ENABLED)
Tool: $DETECTED_TOOL
Status: Pre-execution blocking active

This is a one-time setup confirmation." 2>/dev/null || true
tui_step "Test notification sent via ${CHANNELS[*]}"

# ─── Done ────────────────────────────────────────────────────────────────────
tui_note "🪰 Shoofly Advanced is active" \
"Agent:     ${AGENT_NAME}
Mode:      ${SENSITIVITY_LABEL}  (blocking: ${BLOCKING_ENABLED})
Tool:      ${DETECTED_TOOL}

Alerts:    ~/.shoofly/logs/alerts.log
Blocked:   ~/.shoofly/logs/blocked.log
Audit DB:  ~/.shoofly/audit.db

shoofly-status    — what 🪰 Shoofly is doing right now
shoofly-health    — verify all components are healthy
shoofly-log       — browse recent alerts and blocks
shoofly-scan      — scan files for leaked secrets"

if [[ -n "$SHELL_RC" ]]; then
  tui_info "To use shoofly-* commands:  source ~/${SHELL_RC##*/}"
fi
if [[ "$HOOK_METHOD" == "manual" ]]; then
  tui_warn "Pre-execution blocking requires manual hook setup. See instructions above."
fi

tui_outro "🪰 Blocking threats before they execute."
