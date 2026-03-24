# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Shoofly, please report it responsibly:

- **Email:** security@shoofly.dev
- **Do not** open a public GitHub issue for security vulnerabilities
- We aim to respond within 48 hours and will coordinate a fix and disclosure timeline with you

## False Positive Scanner Findings

Automated security scanners (gitleaks, GitHub secret scanning, ClawHub policy checks) may flag the following files:

| File | Reason flagged | Why it's a false positive |
|------|---------------|--------------------------|
| `basic/bin/shoofly-daemon` | Contains credential regex patterns | These are detection patterns, not real credentials |
| `basic/policy/threats.yaml` | Contains credential regex patterns | Policy file defining what patterns to detect |
| `basic/skills/shoofly-basic/SKILL.md` | References credential patterns in documentation | Documentation examples, not real credentials |
| `advanced/bin/shoofly-daemon` | Contains credential regex patterns | These are detection patterns, not real credentials |
| `advanced/policy/threats.yaml` | Contains credential regex patterns | Policy file defining what patterns to detect |

**Why this happens:** Shoofly is a security monitoring tool that detects credential patterns at runtime (e.g. `sk-[a-zA-Z0-9]{20,}` for OpenAI keys, `ghp_[a-zA-Z0-9]{36}` for GitHub tokens). Because the tool *contains* these patterns to match against, static scanners that look for the same patterns will flag Shoofly's own source as a false positive.

This is a well-known challenge for security tooling — the scanner and the tool it scans use the same signatures.

**Verification:** All Shoofly releases are scanned with VirusTotal (0/63 detections) prior to publish. See release notes for VT permalinks.

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.2.x   | ✅ Yes    |
| < 1.2   | ❌ No     |
