#!/usr/bin/env bash
# Shoofly Basic v3 — one-command installer
# Works with Claude Code, Cline, any AI terminal tool, or standalone
# Usage: curl -fsSL https://shoofly.dev/install.sh | bash

set -euo pipefail

# ─── TTY guard ───────────────────────────────────────────────────────────────
if [ ! -t 0 ]; then
  SELF=$(mktemp /tmp/shoofly-basic-XXXXXX.sh)
  curl -fsSL "https://shoofly.dev/install.sh" -o "$SELF"
  chmod +x "$SELF"
  exec bash "$SELF" < /dev/tty
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

# Emoji support — skip on non-UTF-8 locales to avoid terminal rendering gaps
_FLY="🪰 "
case "${LANG:-}${LC_ALL:-}${LC_CTYPE:-}" in
  *[Uu][Tt][Ff]8*|*[Uu][Tt][Ff]-8*) ;;  # UTF-8 confirmed
  "")                                    ;;  # unset → macOS default is UTF-8
  *) _FLY=""                            ;;  # non-UTF-8 locale: omit emoji
esac

# Output globals (set by tui_select / tui_multiselect)
TUI_RESULT=""
TUI_RESULTS=()
_TUI_JS=""   # path to Node.js TUI helper; recreated if deleted by subshell EXIT trap

_tui_restore() { printf '\033[?25h'; stty echo icanon 2>/dev/null || true; [[ -n "${_TUI_JS:-}" ]] && rm -f "$_TUI_JS" 2>/dev/null; }
trap '_tui_restore' EXIT INT TERM

# Write the Node.js TUI helper to a temp file (PID-named to avoid collisions).
# Called before every tui_select/tui_multiselect — checks if file still exists
# because subshell EXIT traps may delete it between calls.
_tui_ensure_js() {
  [[ -n "$_TUI_JS" && -f "$_TUI_JS" ]] && return
  _TUI_JS="/tmp/shoofly-tui-$$.js"
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
  if command -v node >/dev/null 2>&1; then
    _tui_ensure_js
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
  if command -v node >/dev/null 2>&1; then
    _tui_ensure_js
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
tui_intro "${_FLY}Shoofly Basic v3 — AI Agent Security" \
  "Monitors your AI agents and alerts on suspicious behavior."

# ─── Step 1: Hard dependencies ───────────────────────────────────────────────
printf "Checking dependencies...\n"
if ! command -v jq >/dev/null 2>&1; then
  tui_warn "jq not found"
  if command -v brew >/dev/null 2>&1; then
    printf "  Installing jq via Homebrew...\n"
    if brew install jq >/dev/null 2>&1; then
      tui_step "jq installed via Homebrew"
    else
      printf "\n  ${_D}brew install jq failed. Run it manually, then re-run this installer.${_R}\n\n"
      exit 1
    fi
  else
    printf "\n"
    printf "  ${_D}jq is required but Homebrew was not found.${_R}\n"
    printf "  ${_D}Install Homebrew:  https://brew.sh${_R}\n"
    printf "  ${_D}Then:              brew install jq${_R}\n"
    printf "  ${_D}Then re-run:       curl -fsSL https://shoofly.dev/install.sh | bash${_R}\n\n"
    exit 1
  fi
fi
command -v curl >/dev/null 2>&1 || {
  printf "  ${_D}ERROR: curl is required.${_R}\n"; exit 1; }
tui_step "jq, curl found"

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

  # Remove PostToolUse shoofly hooks from Claude Code settings
  if [[ -f "$HOME/.claude/settings.json" ]]; then
    _tmp=$(mktemp)
    jq '
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

# ─── Step 4: Alert sensitivity ───────────────────────────────────────────────
tui_select "How sensitive should ${_FLY}Shoofly be?" \
  "default|Default|alert on confirmed threats and likely threats  (recommended)" \
  "quiet|Quiet  |only alert on high-confidence, high-severity threats" \
  "verbose|Verbose|alert on anything suspicious, including low-confidence signals"
SENSITIVITY_LABEL="$TUI_RESULT"

# ─── Step 5: Notification channels ───────────────────────────────────────────
_CHANNEL_OPTS=(
  "macos|macOS notifications|banner + sound"
  "telegram|Telegram         |direct message to a Telegram chat"
  "terminal|Terminal          |printed where ${_FLY}Shoofly runs — good for logging"
)
[[ "$DETECTED_TOOL" == "openclaw" ]] && \
  _CHANNEL_OPTS+=("openclaw|OpenClaw (local)  |via OpenClaw gateway  (legacy)")
tui_multiselect "Where should ${_FLY}Shoofly send threat alerts?" "${_CHANNEL_OPTS[@]}"

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
tui_text "Agent name" "this label appears in your alerts" "$DEFAULT_AGENT"
AGENT_NAME="$TUI_RESULT"

# ─── Step 7: Review ──────────────────────────────────────────────────────────
CHANNELS_DISPLAY="${CHANNELS[*]}"
tui_note "Review your settings" \
"Sensitivity:  ${SENSITIVITY_LABEL}
Channels:     ${CHANNELS_DISPLAY// /, }
Agent:        ${AGENT_NAME}
Tool:         ${DETECTED_TOOL}"

# ─── Step 8: Install files ───────────────────────────────────────────────────
printf "\nInstalling ${_FLY}Shoofly Basic...\n"
mkdir -p "$HOME/.shoofly/"{bin,policy,logs}
tui_step "Directories ready"

BASE_URL="https://raw.githubusercontent.com/shoofly-dev/shoofly/main"
curl -fsSL "$BASE_URL/basic/policy/threats.yaml"    -o "$HOME/.shoofly/policy/threats.yaml"
curl -fsSL "$BASE_URL/basic/bin/shoofly-daemon"     -o "$HOME/.shoofly/bin/shoofly-daemon"
curl -fsSL "$BASE_URL/basic/bin/shoofly-notify"     -o "$HOME/.shoofly/bin/shoofly-notify"
curl -fsSL "$BASE_URL/basic/bin/shoofly-uninstall"  -o "$HOME/.shoofly/bin/shoofly-uninstall"
chmod +x "$HOME/.shoofly/bin/shoofly-daemon" \
         "$HOME/.shoofly/bin/shoofly-notify" \
         "$HOME/.shoofly/bin/shoofly-uninstall"
tui_step "Files downloaded"

# ─── Step 9: Write config ────────────────────────────────────────────────────
CHANNELS_JSON=$(printf '"%s",' "${CHANNELS[@]}" | sed 's/,$//')
cat > "$HOME/.shoofly/config.json" <<EOF
{
  "tier": "basic",
  "version": "3.0.0",
  "sensitivity": "$SENSITIVITY_LABEL",
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
case "$HOOK_METHOD" in
  claude-settings)
    local_settings="$HOME/.claude/settings.json"
    local_hook_cmd="$HOME/.shoofly/bin/shoofly-daemon --hook-mode"
    mkdir -p "$HOME/.claude"
    [[ ! -f "$local_settings" ]] && echo '{}' > "$local_settings"
    already=$(jq --arg c "$local_hook_cmd" \
      '.hooks.PostToolUse//[]|any(.[].hooks//[]|any(.command==$c))' \
      "$local_settings" 2>/dev/null || echo "false")
    if [[ "$already" != "true" ]]; then
      tmp=$(mktemp)
      jq --arg c "$local_hook_cmd" '
        .hooks//={}|.hooks.PostToolUse//=[]|
        .hooks.PostToolUse+=[{"matcher":".*","hooks":[{"type":"command","command":$c}]}]
      ' "$local_settings" > "$tmp" && mv "$tmp" "$local_settings"
      tui_step "Hook registered in ~/.claude/settings.json  (PostToolUse)"
    else
      tui_step "Claude Code hook already registered"
    fi
    ;;
  openclaw-legacy)
    cfg="$HOME/.openclaw/openclaw.json"
    if [[ -f "$cfg" ]]; then
      already=$(jq --arg k "shoofly-basic" '.plugins.entries|has($k)' "$cfg" 2>/dev/null || echo "false")
      if [[ "$already" != "true" ]]; then
        tmp=$(mktemp)
        jq --arg k "shoofly-basic" --arg p "$HOME/.shoofly/bin/shoofly-daemon" \
          '.plugins.entries//={}|.plugins.entries[$k]={"path":$p,"enabled":true}' \
          "$cfg" > "$tmp" && mv "$tmp" "$cfg"
        tui_step "Hook registered in ~/.openclaw/openclaw.json  (legacy)"
      else
        tui_step "OpenClaw hook already registered"
      fi
    else
      tui_warn "~/.openclaw/openclaw.json not found — skipping legacy hook"
    fi
    ;;
  manual)
    tui_info "Hook auto-registration not available for: ${DETECTED_TOOL}"
    printf "       ${_D}To monitor tool calls, add this PostToolUse command to your tool:${_R}\n"
    printf "       ${_D}%s${_R}\n" "$HOME/.shoofly/bin/shoofly-daemon --hook-mode"
    ;;
esac

# ─── Step 11: LaunchAgent ────────────────────────────────────────────────────
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
  tui_step "LaunchAgent installed  (daemon auto-starts)"
fi

# ─── Step 12: PATH ───────────────────────────────────────────────────────────
SHOOFLY_BIN="$HOME/.shoofly/bin"; SHELL_RC=""
[[ "$SHELL" == */zsh ]]  && SHELL_RC="$HOME/.zshrc"
[[ "$SHELL" == */bash ]] && SHELL_RC="$HOME/.bashrc"
if [[ -n "$SHELL_RC" ]] && ! grep -q 'shoofly/bin' "$SHELL_RC" 2>/dev/null; then
  { echo ""; echo "# Shoofly CLI tools"; echo "export PATH=\"\$HOME/.shoofly/bin:\$PATH\""; } >> "$SHELL_RC"
  tui_step "~/.shoofly/bin added to PATH in ${SHELL_RC##*/}"
fi
export PATH="$SHOOFLY_BIN:$PATH"

# ─── Step 13: Daemon + smoke test ────────────────────────────────────────────
printf "\nStarting daemon...\n"
"$HOME/.shoofly/bin/shoofly-daemon" --config "$HOME/.shoofly/config.json" --verify \
  && tui_step "Daemon verified" || tui_warn "Daemon verify returned non-zero — run shoofly-health to diagnose"

printf "\nSending test notification...\n"
"$HOME/.shoofly/bin/shoofly-notify" auto "🪰 SHOOFLY BASIC — INSTALL VERIFIED ✅

Agent: $AGENT_NAME  ·  Sensitivity: $SENSITIVITY_LABEL  ·  Tool: $DETECTED_TOOL
Status: Monitoring active

This is a one-time setup confirmation." 2>/dev/null || true
tui_step "Test notification sent via ${CHANNELS[*]}"

# ─── Done ────────────────────────────────────────────────────────────────────
tui_note "All set" \
"Agent:       ${AGENT_NAME}
Sensitivity: ${SENSITIVITY_LABEL}
Tool:        ${DETECTED_TOOL}
Alerts log:  ~/.shoofly/logs/alerts.log
Policy:      ~/.shoofly/policy/threats.yaml"

tui_outro "${_FLY}Shoofly Basic is watching. Threats will be flagged. You'll be the first to know.

  Run  shoofly-status  anytime to check in.
  Upgrade to Advanced for pre-execution blocking: shoofly.dev/#pricing-advanced"
