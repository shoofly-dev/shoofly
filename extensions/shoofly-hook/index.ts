/**
 * shoofly-hook — OpenClaw plugin for pre-execution tool call interception.
 * Merged single-file version for extension install.
 * Blocks: OSW (sensitive path writes), DE (credential exfil in exec)
 */

import * as fs from "fs";
import * as path from "path";
import * as os from "os";
import { execFile } from "child_process";

const HOME = os.homedir();
const LOG_DIR = path.join(HOME, ".shoofly", "logs");
const LOG_PATH = path.join(LOG_DIR, "hook-alerts.log");
const NOTIFY_BIN = path.join(HOME, ".shoofly", "bin", "shoofly-notify");

// Resolve session_id and agent_name once at module load
const SESSION_ID = process.env.OPENCLAW_SESSION_ID || process.env.SESSION_ID || "unknown";
const AGENT_NAME = (() => {
  // 1. Prefer env var set by OpenClaw when spawning agents
  if (process.env.OPENCLAW_AGENT_NAME) return process.env.OPENCLAW_AGENT_NAME;
  // 2. Fall back to openclaw.json agent_name field
  try {
    const cfg = JSON.parse(fs.readFileSync(path.join(HOME, ".openclaw", "openclaw.json"), "utf8"));
    return cfg.agent_name || "unknown";
  } catch {
    return "unknown";
  }
})();

// Sensitive paths — never allow agent writes here.
// NOTE: ~/.openclaw/ is NOT a blanket block — workspaces/ and workspace/ are
// legitimate agent write targets. Only specific sensitive subdirs are blocked.
const SENSITIVE_PATHS = [
  "/etc/",
  `${HOME}/.ssh/`,
  `${HOME}/.aws/`,
  `${HOME}/.bashrc`,
  `${HOME}/.zshrc`,
  `${HOME}/.bash_profile`,
  `${HOME}/.profile`,
  `${HOME}/.gnupg/`,
  `${HOME}/.openclaw/credentials/`,
  `${HOME}/.openclaw/identity/`,
  `${HOME}/.openclaw/openclaw.json`,
  `${HOME}/.openclaw/extensions/shoofly-hook/index.ts`,
  "/Library/LaunchDaemons/",
  `${HOME}/Library/LaunchAgents/`,
];

// Credential patterns in exec commands
const CRED_PATTERNS = [
  /sk-[a-zA-Z0-9-]{20,}/,
  /ghp_[a-zA-Z0-9]{36}/,
  /github_pat_[a-zA-Z0-9_]{82}/,
  /AKIA[A-Z0-9]{16}/,
  /-----BEGIN (RSA|EC|OPENSSH) PRIVATE KEY-----/,
  /cat.*id_rsa.*curl/,
  /cat.*credentials.*curl/,
];

const WRITE_TOOLS = ["write", "edit", "Write", "Edit"];

function logAlert(threat: string, toolName: string, summary: string): void {
  try {
    fs.mkdirSync(LOG_DIR, { recursive: true });
    const entry = JSON.stringify({
      ts: new Date().toISOString(),
      tier: "hook",
      threat,
      tool: toolName,
      summary,
      blocked: true,
      session_id: SESSION_ID,
      agent_name: AGENT_NAME,
    });
    fs.appendFileSync(LOG_PATH, entry + "\n");
  } catch {}
}

function fireNotify(threat: string, toolName: string): void {
  try {
    const msg = `SHOOFLY HOOK 🪰⚡ BLOCKED: ${threat} in ${toolName}. shoofly.dev/advanced`;
    execFile(NOTIFY_BIN, ["auto", msg], { timeout: 3000 }, () => {});
  } catch {}
}

function checkOSW(toolName: string, params: Record<string, unknown>) {
  if (!WRITE_TOOLS.includes(toolName)) return null;
  const filePath = String(params.file_path || params.path || "");
  if (!filePath) return null;
  const sensitive = SENSITIVE_PATHS.find(p => filePath.startsWith(p));
  if (sensitive) {
    const summary = `write to sensitive path: ${filePath}`;
    logAlert("OSW", toolName, summary);
    fireNotify("out-of-scope write", toolName);
    return { block: true, blockReason: `Shoofly: out-of-scope write blocked — ${filePath} is a protected path` };
  }
  return null;
}

function checkDE(toolName: string, params: Record<string, unknown>) {
  // Cover all exec-style tool names: OpenClaw normalizes to "exec" but handle raw names defensively
  const EXEC_TOOLS = new Set(["exec", "Exec", "bash", "Bash", "shell", "Shell"]);
  if (!EXEC_TOOLS.has(toolName)) return null;
  const cmd = String(params.command || "");
  if (!cmd) return null;
  const matched = CRED_PATTERNS.find(p => p.test(cmd));
  if (matched) {
    logAlert("DE", toolName, "credential pattern in exec command");
    fireNotify("data exfiltration attempt", toolName);
    return { block: true, blockReason: "Shoofly: exec command contains credential pattern — blocked to prevent exfiltration" };
  }
  return null;
}

export default function register(api: any) {
  api.on("before_tool_call", (event: any) => {
    const { toolName, params = {} } = event;
    return checkOSW(toolName, params) || checkDE(toolName, params) || undefined;
  });
}
