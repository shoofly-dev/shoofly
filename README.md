# Shoofly

Drop-in runtime security for OpenClaw AI agents.

```
curl -fsSL https://shoofly.dev/install.sh | bash
```

Shoofly wraps your agent and checks every action against an open ruleset — catching prompt injection, anomalous tool use, and credential sniffing before they reach your infrastructure.

## How it works

1. Run `curl -fsSL https://shoofly.dev/install.sh | bash` in your agent project
2. **Basic:** Every tool call is logged and evaluated against an open ruleset in real time. Threats trigger alerts — prompt injection attempts, out-of-scope writes, credential sniffing.
3. **Advanced:** Adds two components — a **daemon** (background sidecar that monitors and alerts) and a **hook** (OpenClaw plugin that intercepts tool calls before they execute and blocks them). Same product, one upgrade.

## Tiers

- 🪰🧹 **Shoofly Basic** — Free forever. Detect threats, send notifications. Never blocks. Install: `curl -fsSL https://shoofly.dev/install.sh | bash`
- ⚡🪰⚡ **Shoofly Advanced** — $19/mo. Daemon + hook. Tool calls blocked before execution, 24/7, automatic. Upgrade: `curl -fsSL https://shoofly.dev/install-advanced.sh | bash`

## Open source

The rules that protect your OpenClaw agents are open. Read them, fork them, run them yourself.

→ [shoofly.dev](https://shoofly.dev)
