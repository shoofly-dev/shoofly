#!/usr/bin/env bash
# Shoofly Uninstaller — removes any version of Shoofly (Basic or Advanced)
# Usage: bash uninstall-shoofly.sh
# Or via curl: bash <(curl -fsSL https://shoofly.dev/uninstall.sh)

set -euo pipefail

# ─── TTY guard ───────────────────────────────────────────────────────────────
if [ ! -t 0 ]; then
  SELF="/tmp/shoofly-uninstall-$$.sh"
  curl -fsSL "https://shoofly.dev/uninstall.sh" -o "$SELF"
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

# Output globals (set by tui_select / tui_multiselect)
TUI_RESULT=""
TUI_RESULTS=()
_TUI_JS=""   # path to Node.js TUI helper; recreated if deleted by subshell EXIT trap
_JQ_TMP=""   # temp jq binary; cleaned on exit if needed

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
#  Uninstall logic
# ═════════════════════════════════════════════════════════════════════════════

tui_intro "🪰 Shoofly Uninstaller" "Removes 🪰 Shoofly and all associated files from this machine."

# ─── Step 0: jq dependency ───────────────────────────────────────────────────
if ! command -v jq >/dev/null 2>&1; then
  if [[ -x "$HOME/.shoofly/bin/jq" ]]; then
    jq() { "$HOME/.shoofly/bin/jq" "$@"; }
    tui_step "Using bundled jq from ~/.shoofly/bin/jq"
  else
    tui_warn "jq not found — downloading for uninstall..."
    _JQ_TMP="/tmp/shoofly-jq-$$"
    case "$(uname -s)/$(uname -m)" in
      Darwin/arm64)  _jq_bin="jq-macos-arm64" ;;
      Darwin/x86_64) _jq_bin="jq-macos-amd64" ;;
      Linux/aarch64) _jq_bin="jq-linux-arm64"  ;;
      Linux/x86_64)  _jq_bin="jq-linux-amd64"  ;;
      *)
        printf "  ${_D}Unsupported platform — install jq manually.${_R}\n"; exit 1 ;;
    esac
    curl -fsSL "https://github.com/jqlang/jq/releases/download/jq-1.7.1/${_jq_bin}" \
      -o "$_JQ_TMP" 2>/dev/null || {
      rm -f "$_JQ_TMP"; _JQ_TMP=""
      printf "  ${_D}ERROR: Failed to download jq. Check your internet connection.${_R}\n"; exit 1; }
    chmod +x "$_JQ_TMP"
    jq() { "$_JQ_TMP" "$@"; }
    tui_step "jq 1.7.1 downloaded"
  fi
fi

# ─── Step 1: Detect what's installed ─────────────────────────────────────────
printf "Detecting 🪰 Shoofly install...\n"

SHOOFLY_DIR="$HOME/.shoofly"
CONFIG_FILE="$SHOOFLY_DIR/config.json"

if [[ ! -d "$SHOOFLY_DIR" && ! -f "$CONFIG_FILE" ]]; then
  tui_info "No Shoofly installation found at ~/.shoofly"
  tui_outro "Nothing to remove."
  exit 0
fi

INSTALLED_TIER="unknown"
INSTALLED_VER="unknown"
if [[ -f "$CONFIG_FILE" ]]; then
  INSTALLED_TIER=$(jq -r '.tier // "unknown"' "$CONFIG_FILE" 2>/dev/null || echo "unknown")
  INSTALLED_VER=$(jq -r '.version // "unknown"' "$CONFIG_FILE" 2>/dev/null || echo "unknown")
fi
tui_step "Found: 🪰 Shoofly ${INSTALLED_TIER} v${INSTALLED_VER}"

# Detect Claude Code hook
CC_HOOK_FOUND=false
CC_SETTINGS="$HOME/.claude/settings.json"
if [[ -f "$CC_SETTINGS" ]]; then
  if jq -e '.hooks.PreToolUse // .hooks.PostToolUse // [] | .. | strings | test("shoofly")' \
       "$CC_SETTINGS" >/dev/null 2>&1; then
    CC_HOOK_FOUND=true
    tui_step "Claude Code hook found in ~/.claude/settings.json"
  fi
fi

# Detect OpenClaw hook (legacy)
OC_HOOK_FOUND=false
OC_CONFIG="$HOME/.openclaw/openclaw.json"
if [[ -f "$OC_CONFIG" ]]; then
  if jq -e '.plugins.entries | to_entries[] | .key | test("shoofly")' \
       "$OC_CONFIG" >/dev/null 2>&1; then
    OC_HOOK_FOUND=true
    tui_step "OpenClaw hook found in ~/.openclaw/openclaw.json  (legacy)"
  fi
fi

# Detect LaunchAgent
PLIST_PATH="$HOME/Library/LaunchAgents/dev.shoofly.daemon.plist"
LAUNCHAGENT_FOUND=false
if [[ "$(uname)" == "Darwin" && -f "$PLIST_PATH" ]]; then
  LAUNCHAGENT_FOUND=true
  tui_step "LaunchAgent found: dev.shoofly.daemon.plist"
fi

# ─── Step 2: Show what will be removed ───────────────────────────────────────
REMOVAL_LIST=""
REMOVAL_LIST+="~/.shoofly/  (config, bins, policy, logs)\n"
$CC_HOOK_FOUND  && REMOVAL_LIST+="~/.claude/settings.json  (shoofly hook entries only)\n"
$OC_HOOK_FOUND  && REMOVAL_LIST+="~/.openclaw/openclaw.json  (shoofly plugin entries only)\n"
$LAUNCHAGENT_FOUND && REMOVAL_LIST+="~/Library/LaunchAgents/dev.shoofly.daemon.plist\n"

# Remove trailing newline for note display
REMOVAL_DISPLAY="${REMOVAL_LIST%\\n}"

tui_note "Will be removed" "$REMOVAL_DISPLAY

Your ~/.claude/settings.json and ~/.openclaw/openclaw.json
are NOT deleted — only shoofly entries are removed."

# ─── Step 3: Confirm ─────────────────────────────────────────────────────────
tui_select "Proceed with uninstall?" \
  "uninstall|Uninstall|remove everything listed above" \
  "cancel|Cancel   |leave 🪰 Shoofly installed"

if [[ "$TUI_RESULT" == "cancel" ]]; then
  tui_outro "No changes made."
  exit 0
fi

# ─── Step 4: Stop daemon ─────────────────────────────────────────────────────
printf "\nStopping 🪰 Shoofly...\n"

if $LAUNCHAGENT_FOUND; then
  launchctl unload "$PLIST_PATH" 2>/dev/null || true
  tui_step "Daemon unloaded"
else
  # Try to kill by process name in case daemon is running without a LaunchAgent
  pkill -f shoofly-daemon 2>/dev/null || true
fi

# ─── Step 5: Remove Claude Code hooks ────────────────────────────────────────
if $CC_HOOK_FOUND; then
  local_tmp=$(mktemp)
  # Remove any PreToolUse/PostToolUse hook entry whose command references shoofly
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
  ' "$CC_SETTINGS" > "$local_tmp" && mv "$local_tmp" "$CC_SETTINGS"
  tui_step "Claude Code hooks removed from ~/.claude/settings.json"
fi

# ─── Step 6: Remove OpenClaw hooks (legacy) ──────────────────────────────────
if $OC_HOOK_FOUND; then
  local_tmp=$(mktemp)
  jq 'if .plugins.entries then
        .plugins.entries = (.plugins.entries | with_entries(select(.key | test("shoofly") | not)))
      else . end' \
    "$OC_CONFIG" > "$local_tmp" && mv "$local_tmp" "$OC_CONFIG"
  tui_step "OpenClaw plugin entries removed from ~/.openclaw/openclaw.json"
fi

# ─── Step 7: Remove LaunchAgent plist ────────────────────────────────────────
if $LAUNCHAGENT_FOUND; then
  rm -f "$PLIST_PATH"
  tui_step "LaunchAgent plist removed"
fi

# ─── Step 8: Remove ~/.shoofly directory ─────────────────────────────────────
if [[ -d "$SHOOFLY_DIR" ]]; then
  rm -rf "$SHOOFLY_DIR"
  tui_step "~/.shoofly/ removed"
fi

# ─── Step 9: Remove PATH entry (advisory) ────────────────────────────────────
SHELL_RC=""
[[ "$SHELL" == */zsh ]]  && SHELL_RC="$HOME/.zshrc"
[[ "$SHELL" == */bash ]] && SHELL_RC="$HOME/.bashrc"

PATH_REMOVED=false
if [[ -n "$SHELL_RC" ]] && grep -q 'shoofly/bin' "$SHELL_RC" 2>/dev/null; then
  # Remove the 3-line PATH block added by the installer
  local_tmp=$(mktemp)
  # Remove blank line + comment + export line for shoofly
  awk '
    /^$/ { blank=$0; next }
    /^# Shoofly CLI tools$/ { comment=$0; next }
    /export PATH.*shoofly/ { next }
    { if (blank != "") { print blank; blank="" }
      if (comment != "") { print comment; comment="" }
      print }
    END { if (blank != "") print blank }
  ' "$SHELL_RC" > "$local_tmp" && mv "$local_tmp" "$SHELL_RC"
  PATH_REMOVED=true
  tui_step "PATH entry removed from ${SHELL_RC##*/}"
fi

# ─── Done ────────────────────────────────────────────────────────────────────
printf "\n"
tui_outro "🪰  Shoofly has been removed."
printf "  Restart your terminal to clear the PATH.\n\n"
