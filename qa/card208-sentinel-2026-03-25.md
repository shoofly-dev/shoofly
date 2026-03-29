# Card 208 — Sentinel Security Pass
**Date:** 2026-03-25
**Scope:** Static analysis only (no runtime testing)
**Verdict:** PASS

---

## S1 — F1: Hook install step

**Files:** `builds/shoofly-advanced/install.sh`, `advanced/install.sh`

| Check | Result | Notes |
|-------|--------|-------|
| curl uses `$BASE_URL` (no hardcoded, no `$()` injection) | **PASS** | Both files use `"$BASE_URL/..."` — properly double-quoted, no command substitution in URL. Build copy pinned to `v1.2.2`, dev copy tracks `main`. |
| jq commands use `--arg` and proper quoting | **PASS** | Lines 91/116 use `jq --arg p "$HOOK_PATH"` — value passed safely via jq's `--arg`, not interpolated into the filter string. |
| Shell injection in path handling (HOOK_DIR, HOOK_PATH) | **PASS** | `HOOK_DIR="$HOME/.openclaw/extensions/shoofly-hook"` — derived from `$HOME` only, no user input. All uses are double-quoted. |
| mktemp used for temp files | **PASS** | `_TMP=$(mktemp)` at lines 93/118 — no hardcoded `/tmp/` paths. |
| No secrets or creds in script | **PASS** | Telegram creds collected at runtime via `read -r`, stored to `~/.shoofly/.env` with `chmod 600`. No secrets in source. |

**S1 overall: PASS**

---

## S2 — F2: Alert log handling

**File:** `~/.shoofly/bin/shoofly-status`

| Check | Result | Notes |
|-------|--------|-------|
| File paths properly quoted | **PASS** | All path variables (`$ALERTS_LOG`, `$HOOK_ALERTS_LOG`, `$CONFIG_PATH`, `$PID_FILE`, `$POLICY_CACHE`) are double-quoted at every use site. |
| awk/grep injection via log content | **PASS** | awk scripts (lines 114-125, 138-159) process JSONL as passive text via field splitting — no `system()`, no backtick eval, no dynamic pattern construction from log data. grep at line 84 uses a fixed pattern. grep at line 129 uses a fixed literal string. |
| No sensitive data assumed in parsed JSONL | **PASS** | Only `ts`, `threat`, `rule_id`, `confidence`, `notified`, `summary` fields are extracted — no secrets, tokens, or credential fields. |
| No unsafe eval or backtick execution | **PASS** | No `eval`, no backtick command substitution, no `source` of untrusted files anywhere in the script. PID from pidfile is sanitized with `tr -d '[:space:]'` before use. |

**S2 overall: PASS**

---

## S3 — W1: DE check scope

**File:** `~/.openclaw/extensions/shoofly-hook/index.ts`

| Check | Result | Notes |
|-------|--------|-------|
| EXEC_TOOLS check is safe (no prototype pollution) | **PASS** | `new Set([...]).has(toolName)` — `Set.has()` performs strict `SameValueZero` comparison on the string. No property lookup on the set object, so prototype pollution of `Object` or `Set` cannot cause false negatives. |
| Credential regex — no ReDoS | **PASS** | Fixed-length patterns (`{36}`, `{82}`, `{16}`) and bounded quantifiers (`{20,}`) are safe. The two `cat.*xxx.*curl` patterns have nested `.*` but operate on single command strings (typically <1KB), making O(n^2) worst-case negligible in practice. |
| Block response message is safe to display | **PASS** | OSW block message interpolates `filePath` (`blocked — ${filePath} is a protected path`), but this is returned as a plain string to the plugin API, not rendered as HTML/JS. DE block message is fully static. Both are safe for terminal display. |

**S3 overall: PASS**

---

## S4 — W2: Header generation

**File:** `~/.shoofly/bin/shoofly-status`

| Check | Result | Notes |
|-------|--------|-------|
| TIER_LABEL awk is safe (no injection via $TIER) | **PASS** | Line 166: `echo "$TIER" | awk '{print toupper(substr($0,1,1)) substr($0,2)}'` — `$TIER` is piped as stdin to awk, not interpolated into the awk program text. Even a malicious `$TIER` value cannot inject awk code. |
| printf formatting is safe | **PASS** | Line 167: `printf "... %s ... %s\n" "$TIER_LABEL" "$AGENT_NAME"` — format string is a static literal; variables are passed as `%s` arguments, not embedded in the format string. No format-string injection possible. |

**S4 overall: PASS**

---

## Additional observations (informational, not blocking)

1. **Heredoc config generation** (install.sh lines 175-184 / 203-214): The fresh-install config.json is built via unquoted heredoc with `${AGENT_NAME}` and `${AGENT_ID}` interpolation. If a user enters a double-quote in their agent name, the JSON will be malformed. Not a security vulnerability (local config, user-supplied value), but a robustness nit. The upgrade path correctly uses jq.

2. **`cat.*id_rsa.*curl` regex**: While not ReDoS-vulnerable at command-string scale, this pattern is intentionally broad — it catches `cat` and `curl` anywhere in the same command with `id_rsa` between them. Acceptable for a heuristic block, but could produce false positives on innocent multi-step pipelines.

---

## Final verdict

| Section | Result |
|---------|--------|
| S1 — Hook install step | PASS |
| S2 — Alert log handling | PASS |
| S3 — DE check scope | PASS |
| S4 — Header generation | PASS |
| **Overall** | **PASS** |
