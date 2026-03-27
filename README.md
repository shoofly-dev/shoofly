# Shoofly

Drop-in runtime security for OpenClaw AI agents.

```
curl -fsSL https://shoofly.dev/install.sh | bash
```

Shoofly intercepts your agent's tool calls and blocks dangerous ones before they execute. Prompt injection, credential sniffing, and out-of-scope writes are blocked — not detected.

## How it works

1. Run `curl -fsSL https://shoofly.dev/install.sh | bash` in your agent project
2. **Basic:** Every tool call is logged and evaluated against an open ruleset in real time. Threats trigger alerts — prompt injection attempts, out-of-scope writes, credential sniffing.
3. **Advanced:** Adds two components — a **daemon** (background sidecar that monitors and alerts) and a **hook** (OpenClaw plugin that intercepts tool calls before they execute and blocks them). Same product, one upgrade.

## Tiers

- 🪰🧹 **Shoofly Basic** — Free forever. Detect threats, send notifications. Never blocks. Install: `curl -fsSL https://shoofly.dev/install.sh | bash`
- ⚡🪰⚡ **Shoofly Advanced** — $19/mo. Tool call interceptor. Prompt injection, data exfiltration, and dangerous writes blocked before execution. Upgrade: https://shoofly.dev/advanced

## Open source

The rules that protect your OpenClaw agents are open. Read them, fork them, run them yourself.

→ [shoofly.dev](https://shoofly.dev)
