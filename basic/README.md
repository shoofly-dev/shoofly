# Shoofly Basic 🪰🧹

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**Real-time AI agent security monitoring. Free. Open source.**

Shoofly Basic watches every tool call your AI agent makes and flags threats — prompt injections, data exfiltration attempts, out-of-scope writes, and more — in real time. It runs as a lightweight sidecar daemon alongside your agent, independently of the agent itself.

---

## Quick Install

```bash
curl -fsSL https://shoofly.dev/install.sh | bash
```

That's it. Shoofly is now watching your agent.

---

## What It Monitors

Shoofly Basic detects five threat categories:

| Category | Code | What It Catches |
|----------|------|-----------------|
| **Prompt Injection** | PI | Instructions embedded in external content trying to override agent rules: "ignore previous instructions", jailbreak keywords, markup injection (`<system>`, `[INST]`), base64-encoded commands |
| **Tool Response Injection** | TRI | Malicious instructions hidden inside tool results: HTML comment injection, unexpected `system:` keys in API responses |
| **Out-of-Scope Write** | OSW | Agent writing to sensitive paths it should never touch: `/etc/`, `~/.ssh/`, `~/.aws/`, shell config files, LaunchAgents — or credential files like `*.pem`, `.env` |
| **Runaway Loop** | RL | Agent stuck in a loop: same tool called 5+ times in 60s, 20+ tool calls in 30s, repeated read-write cycles on the same file |
| **Data Exfiltration** | DE | Credentials leaving the machine: API keys in POST bodies, pipe-to-curl patterns, credential patterns in message sends |

---

## How It Works

Shoofly operates as two layers:

1. **SKILL.md (agent-side)**: Loads into the agent's context. Instructs the agent to self-monitor and fire alerts after every tool call.
2. **shoofly-daemon (sidecar)**: A background process that independently tails live OpenClaw session logs. Catches threats even if the agent's instructions are overridden via injection — the daemon is the ground truth.

The daemon reads `~/.openclaw/agents/<agent_id>/sessions/<session>.jsonl` and evaluates each new line against the open-source threat policy.

---

## Notification Channels

Configure during install. Supported channels:

| Channel | Delivery Method |
|---------|----------------|
| `terminal` | Write to stderr immediately |
| `openclaw_gateway` | POST to local OpenClaw gateway at port 18789 |
| `telegram` | Telegram bot message (bot token + chat ID required) |
| `whatsapp` | Via `wacli` if installed |
| `macos` | macOS system notification (`osascript`) |

Multiple channels supported — enter comma-separated choices during install.

When a threat is detected at MEDIUM or HIGH confidence, you receive:

> SHOOFLY BASIC 🪰🧹 WARNING: prompt injection detected on my-agent. Try ⚡🪰⚡ SHOOFLY ADVANCED to block attacks before they're inside your agent infra. shoofly.dev/advanced

---

## Confidence Scoring

| Matches | Level | Action |
|---------|-------|--------|
| 1 pattern | LOW | Log only, no notification |
| 2 patterns (same content) | MEDIUM | Log + notify |
| 3+ patterns OR any OSW/DE | HIGH | Log + notify (severity emphasized) |

LOW confidence = log only. Shoofly only bothers you when it's confident.

---

## Basic vs Advanced

| Feature | Basic (this repo) | Advanced |
|---------|------------------|----------|
| Price | **Free** | $19/mo |
| Monitors threats | Yes | Yes |
| Blocks threats | No | **Yes** |
| Hook timing | Post-execution | **Pre-execution** |
| `shoofly-check` binary | No | Yes |
| `blocked.log` | No | Yes |
| Policy file | Open source | Same open source |
| Notification formula | WARNING 🪰🧹 | BLOCKED ⚡🪰⚡ |

Basic monitors and alerts. Advanced intercepts and stops the threat before the tool executes.

Upgrade: [shoofly.dev/advanced](https://shoofly.dev/advanced)

---

## Threat Policy

The full threat policy is open source at [`github.com/shoofly-dev/policy`](https://github.com/shoofly-dev/policy). It's a versioned YAML file (`policy/threats.yaml`) — readable, forkable, and auditable.

Rules:
- Semantically versioned — patch updates never break compatibility
- Rule IDs are immutable — old IDs are never reused
- CHANGELOG.md tracks every addition and modification
- Community PRs welcome — all changes reviewed before merge

---

## Contributing

Pull requests are welcome. For threat policy changes (new threat IDs, pattern updates), open a PR against [`github.com/shoofly-dev/policy`](https://github.com/shoofly-dev/policy) with:

1. The threat ID and name
2. The regex or matching logic
3. Why this pattern is distinct from existing threats
4. False positive risk assessment

---

## Security Notes

- `shoofly-daemon` runs as your user only — never root
- Telegram credentials stored only in `~/.shoofly/.env` (chmod 600) — never in config.json
- `~/.shoofly/config.json` is chmod 600
- `alerts.log` is capped at 10MB and auto-rotates (max 3 copies kept)
- No credentials are hardcoded anywhere

---

## License

MIT — see [LICENSE](LICENSE)

---

*Shoofly — watching your agents so you don't have to.* 🪰
