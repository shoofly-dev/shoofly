# Shoofly Advanced ⚡🪰⚡

**Pre-execution threat blocking for AI agents.**

Shoofly Advanced intercepts and stops threats _before_ your agent executes them. Where Basic monitors and alerts, Advanced **blocks** — the tool call never happens.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## How It Works

Shoofly operates as a two-layer security system:

**Layer 1 — Agent-side (SKILL.md):** Instructions baked into the agent's context. The agent is mandated to run `shoofly-check` before every tool call. Exit 1 = tool is blocked before it runs.

**Layer 2 — Sidecar daemon:** External background process that tails live OpenClaw session logs independently of the agent. Catches threats even if Layer 1 is bypassed via prompt injection. This is the backstop.

```
Agent → SKILL.md → shoofly-check ──► daemon.sock (RL checks)
                         │
                    exit 0: allow
                    exit 1: BLOCK ──► blocked.log + notification
                    exit 2: fail-open (log warning, proceed)
```

---

## Install

```bash
curl -fsSL https://shoofly.dev/install-advanced.sh | bash
```

**Requirements:** `jq`, `curl`, `openclaw`

---

## What Gets Installed

```
~/.openclaw/skills/shoofly-advanced/
├── SKILL.md                       # Agent instruction entrypoint
└── policy/
    └── threats.yaml               # Symlink to ~/.shoofly/policy/threats.yaml

~/.shoofly/
├── config.json                    # Runtime config (tier: advanced)
├── policy/
│   └── threats.yaml               # Open-source threat policy (full list)
├── bin/
│   ├── shoofly-daemon             # Sidecar daemon + Unix socket server
│   ├── shoofly-check              # Pre-execution intercept (Advanced only)
│   └── shoofly-notify             # Notification dispatcher
├── logs/
│   ├── alerts.log                 # Persistent alert log (10MB cap, rotates)
│   └── blocked.log                # Blocked actions log (Advanced only)
└── daemon.sock                    # Unix socket (chmod 600, runtime only)
```

---

## Threat Categories

All 20 threat rules are open-source and publicly auditable at [github.com/shoofly-dev/policy](https://github.com/shoofly-dev/policy).

| Category | IDs | Triggers |
|----------|-----|---------|
| **PI — Prompt Injection** | PI-001 to PI-008 | Ignore instructions, jailbreak keywords, markup tags, base64-encoded injections |
| **TRI — Tool Response Injection** | TRI-001, TRI-002 | HTML comment injection, unexpected `system:` keys in fetched content |
| **OSW — Out-of-Scope Write** | OSW-001 to OSW-003 | Writes to `/etc/`, `~/.ssh/`, `~/.aws/`, `~/.bashrc`, credential files |
| **RL — Runaway Loop** | RL-001 to RL-004 | Same tool 5×/60s, >20 calls/30s, read-write cycles, URL hammering |
| **DE — Data Exfiltration** | DE-001 to DE-004 | Credentials in POST body, pipe exfiltration, creds in messages, read-then-network |

**Advanced blocking rules:**
- HIGH severity threats: blocked
- MEDIUM severity threats: blocked
- LOW severity threats: log only (notify on 2+ matches)

---

## shoofly-check Reference

The pre-execution intercept binary. Called by the agent before every tool call.

```bash
~/.shoofly/bin/shoofly-check --tool <name> --args <json> [--config <path>]
```

**Exit codes:**
- `0` — Allow (proceed with tool call)
- `1` — Block (do NOT execute tool; JSON reason on stderr)
- `2` — Error/fail-open (allow tool call, log warning)

**Block JSON format (stderr):**
```json
{
  "decision": "block",
  "threat_id": "OSW-001",
  "confidence": "HIGH",
  "reason": "Write to sensitive credential/config path detected",
  "tool": "write",
  "args_snippet": "..."
}
```

**Timeout:** If `shoofly-check` takes longer than 3 seconds, the agent proceeds (fail-open). Shoofly will never permanently block agent operation due to latency.

---

## shoofly-daemon Socket Server

The Advanced daemon runs a Unix socket server at `~/.shoofly/daemon.sock` (chmod 600).

- Maintains an in-memory ring buffer of the last 500 tool calls (never persisted to disk)
- Serves `shoofly-check` queries for stateful RL (runaway loop) checks
- If the socket is unavailable, `shoofly-check` skips RL checks and fails open
- Cleared on daemon restart (privacy by design)

---

## Notification Format

**Block notification (fired immediately when a tool is blocked):**
```
⚡🪰⚡ SHOOFLY ADVANCED BLOCKED: [threat type] stopped on [agent name]. Your agent infra is protected.
```

**Notification channels** (configured during install):
- `terminal` — writes to stderr
- `openclaw_gateway` — POSTs to `http://127.0.0.1:18789/chat`
- `telegram` — sends via Bot API (token + chat ID stored in `~/.shoofly/.env`)
- `whatsapp` — delegates to `wacli` if installed
- `macos` — macOS notification center

---

## Log Files

**`~/.shoofly/logs/alerts.log`** — All evaluated threats (JSONL):
```json
{"ts":"2026-03-15T10:00:00Z","tier":"advanced","threat":"PI-006","confidence":"HIGH","agent":"my-agent","tool":"bash","summary":"PI-006: prompt injection detected","notified":true}
```

**`~/.shoofly/logs/blocked.log`** — Actions that were blocked (JSONL):
```json
{"ts":"2026-03-15T10:00:01Z","tier":"advanced","threat_id":"OSW-001","confidence":"HIGH","agent":"my-agent","tool":"write","reason":"Write to sensitive credential/config path detected","args_snippet":"..."}
```

Both logs are capped at 10MB and rotate (max 3 copies). Treat as sensitive — they may contain snippets of tool arguments.

---

## Advanced vs Basic

| Feature | Basic | Advanced |
|---------|-------|----------|
| Hook timing | Post-execution | Pre-execution |
| Threat response | Log + notify | **Block** (exit 1) + notify |
| shoofly-check | Not present | Present |
| blocked.log | Not present | Present |
| Daemon socket | Not present | Present (RL checks) |
| Fail behavior | N/A | Fail-open (never breaks agent) |
| Price | Free | $19/mo (Stripe — deferred) |

---

## Security Notes

1. **Fail-open by design.** If `shoofly-check` crashes or times out, the agent proceeds. This is intentional — Shoofly must never permanently block agent operation.

2. **Unix socket only.** The daemon socket is `~/.shoofly/daemon.sock`, chmod 600. It never binds to TCP/IP.

3. **No secrets in config.json.** Telegram tokens etc. live only in `~/.shoofly/.env` (chmod 600).

4. **In-memory call history.** The daemon's ring buffer is never written to disk. It clears on restart.

5. **Not a kernel sandbox.** A sophisticated attacker who fully compromises the agent process could bypass `shoofly-check` by calling tools directly. The sidecar daemon is the independent backstop.

6. **Avoiding circular blocking.** `shoofly-check` will never block writes to `~/.shoofly/` itself, preventing Shoofly from blocking its own notification mechanisms.

---

## Configuration

`~/.shoofly/config.json` (chmod 600):
```json
{
  "tier": "advanced",
  "notification_channels": ["terminal", "macos"],
  "agent_name": "my-agent",
  "agent_id": "abc123",
  "installed_at": "2026-03-15T00:00:00Z",
  "version": "1.0.0",
  "policy_path": "/Users/you/.shoofly/policy/threats.yaml"
}
```

---

## Upgrading from Basic

The Advanced installer detects an existing Shoofly Basic installation and upgrades automatically:
- Downloads and installs `shoofly-check`
- Installs the Advanced `SKILL.md`
- Updates `config.json` tier from `"basic"` to `"advanced"`
- Creates `blocked.log`

The Basic skill directory (`~/.openclaw/skills/shoofly-basic/`) is not removed — you can keep it for reference.

---

## Policy

The threat policy is open source regardless of tier. [github.com/shoofly-dev/policy](https://github.com/shoofly-dev/policy)

- MIT licensed
- Semantically versioned
- Community PRs accepted
- Rule IDs are immutable — new rules get new IDs

---

## Uninstall

```bash
curl -fsSL https://shoofly.dev/uninstall.sh | bash
```

---

## License

MIT — see [LICENSE](LICENSE).

Copyright (c) 2026 Shoofly Contributors
