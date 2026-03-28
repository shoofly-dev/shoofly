#!/usr/bin/env node
/**
 * shoofly-claude-daemon — HTTP hook server for Claude Code runtime.
 * Applies the same threat policy as extensions/shoofly-hook/index.ts.
 * No external dependencies — Node.js built-ins only.
 *
 * Endpoints:
 *   POST /shoofly/v1/pre-tool-use   (Advanced tier — block before exec)
 *   POST /shoofly/v1/post-tool-use  (Basic tier — alert after exec)
 */

const http = require("http");
const fs = require("fs");
const path = require("path");
const { execFile } = require("child_process");
const os = require("os");

const HOME = os.homedir();
const PORT = 7777;
const LOG_DIR = path.join(HOME, ".shoofly", "logs");
const LOG_PATH = path.join(LOG_DIR, "hook-alerts.log");
const NOTIFY_BIN = path.join(HOME, ".shoofly", "bin", "shoofly-notify");
const CONFIG_PATH = path.join(HOME, ".shoofly", "config.json");

// ---------------------------------------------------------------------------
// Threat policy — kept in sync with extensions/shoofly-hook/index.ts
// ---------------------------------------------------------------------------

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
  `${HOME}/Library/Application Support/Google/Chrome/Default/Local Extension Settings/`,
];

const CRED_PATTERNS = [
  /sk-[a-zA-Z0-9-]{20,}/,
  /ghp_[a-zA-Z0-9]{36}/,
  /github_pat_[a-zA-Z0-9_]{82}/,
  /AKIA[A-Z0-9]{16}/,
  /-----BEGIN (RSA|EC|OPENSSH) PRIVATE KEY-----/,
  /cat.*id_rsa.*curl/,
  /cat.*credentials.*curl/,
];

const WRITE_TOOLS = new Set(["write", "edit", "Write", "Edit"]);
const EXEC_TOOLS = new Set(["exec", "Exec", "bash", "Bash", "shell", "Shell"]);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function readTier() {
  try {
    const cfg = JSON.parse(fs.readFileSync(CONFIG_PATH, "utf8"));
    if (cfg.tier === "advanced") return "advanced";
  } catch {}
  return "basic";
}

function logAlert(threat, toolName, summary, blocked, sessionId) {
  try {
    fs.mkdirSync(LOG_DIR, { recursive: true });
    const entry = JSON.stringify({
      ts: new Date().toISOString(),
      tier: "claude-code",
      threat,
      tool: toolName,
      summary,
      blocked,
      session_id: sessionId || "unknown",
    });
    fs.appendFileSync(LOG_PATH, entry + "\n");
  } catch {}
}

function fireNotify(threat, toolName) {
  try {
    const action = readTier() === "advanced" ? "BLOCKED" : "ALERT";
    const msg = `SHOOFLY DAEMON 🪰⚡ ${action}: ${threat} in ${toolName}. shoofly.dev`;
    execFile(NOTIFY_BIN, ["auto", msg], { timeout: 3000 }, () => {});
  } catch {}
}

// ---------------------------------------------------------------------------
// Threat checks
// ---------------------------------------------------------------------------

function checkOSW(toolName, toolInput) {
  if (!WRITE_TOOLS.has(toolName)) return null;
  const filePath = String(toolInput.file_path || toolInput.path || "");
  if (!filePath) return null;
  const sensitive = SENSITIVE_PATHS.find((p) => filePath.startsWith(p));
  if (sensitive) {
    return {
      threat: "OSW",
      summary: `write to sensitive path: ${filePath}`,
      reason: `Shoofly: out-of-scope write blocked — ${filePath} is a protected path`,
    };
  }
  return null;
}

function checkDE(toolName, toolInput) {
  if (!EXEC_TOOLS.has(toolName)) return null;
  const cmd = String(toolInput.command || "");
  if (!cmd) return null;
  const matched = CRED_PATTERNS.find((p) => p.test(cmd));
  if (matched) {
    return {
      threat: "DE",
      summary: "credential pattern in exec command",
      reason: "Shoofly: exec command contains credential pattern — blocked to prevent exfiltration",
    };
  }
  return null;
}

function evaluate(toolName, toolInput) {
  return checkOSW(toolName, toolInput) || checkDE(toolName, toolInput);
}

// ---------------------------------------------------------------------------
// Request handling
// ---------------------------------------------------------------------------

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on("data", (c) => chunks.push(c));
    req.on("end", () => {
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString()));
      } catch (e) {
        reject(e);
      }
    });
    req.on("error", reject);
  });
}

function handlePreToolUse(body) {
  const toolName = body.tool_name || "";
  const toolInput = body.tool_input || {};
  const sessionId = body.session_id || "";
  const result = evaluate(toolName, toolInput);
  if (result) {
    logAlert(result.threat, toolName, result.summary, true, sessionId);
    fireNotify(result.threat === "OSW" ? "out-of-scope write" : "data exfiltration attempt", toolName);
    return {
      permissionDecision: "deny",
      permissionDecisionReason: result.reason,
    };
  }
  return { permissionDecision: "allow" };
}

function handlePostToolUse(body) {
  const toolName = body.tool_name || "";
  const toolInput = body.tool_input || {};
  const sessionId = body.session_id || "";
  const result = evaluate(toolName, toolInput);
  if (result) {
    logAlert(result.threat, toolName, result.summary, false, sessionId);
    fireNotify(result.threat === "OSW" ? "out-of-scope write" : "data exfiltration attempt", toolName);
  }
  return {};
}

// ---------------------------------------------------------------------------
// Server
// ---------------------------------------------------------------------------

const server = http.createServer(async (req, res) => {
  if (req.method !== "POST") {
    res.writeHead(405, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "method not allowed" }));
    return;
  }

  try {
    const body = await readBody(req);
    let response;

    if (req.url === "/shoofly/v1/pre-tool-use") {
      response = handlePreToolUse(body);
    } else if (req.url === "/shoofly/v1/post-tool-use") {
      response = handlePostToolUse(body);
    } else {
      res.writeHead(404, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "not found" }));
      return;
    }

    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify(response));
  } catch (err) {
    res.writeHead(400, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "invalid request" }));
  }
});

server.listen(PORT, "127.0.0.1", () => {
  const tier = readTier();
  console.log(`🪰 shoofly-claude-daemon running on http://127.0.0.1:${PORT} (tier: ${tier})`);
});
