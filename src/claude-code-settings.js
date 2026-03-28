#!/usr/bin/env node
/**
 * claude-code-settings — generates and injects Shoofly HTTP hook config
 * into ~/.claude/settings.json for Claude Code.
 *
 * Reads tier from ~/.shoofly/config.json (defaults to "basic").
 * Merges into existing settings without overwriting other keys.
 */

const fs = require("fs");
const path = require("path");
const os = require("os");

const HOME = os.homedir();
const SETTINGS_PATH = path.join(HOME, ".claude", "settings.json");
const CONFIG_PATH = path.join(HOME, ".shoofly", "config.json");

function readTier() {
  try {
    const cfg = JSON.parse(fs.readFileSync(CONFIG_PATH, "utf8"));
    if (cfg.tier === "advanced") return "advanced";
  } catch {}
  return "basic";
}

function buildHookConfig(tier) {
  if (tier === "advanced") {
    return {
      hooks: {
        PreToolUse: [
          {
            type: "http",
            url: "http://localhost:7777/shoofly/v1/pre-tool-use",
            matcher: ".*",
          },
        ],
      },
    };
  }
  // Basic tier
  return {
    hooks: {
      PostToolUse: [
        {
          type: "http",
          url: "http://localhost:7777/shoofly/v1/post-tool-use",
        },
      ],
    },
  };
}

function main() {
  const tier = readTier();
  const hookConfig = buildHookConfig(tier);

  // Read existing settings
  let settings = {};
  try {
    settings = JSON.parse(fs.readFileSync(SETTINGS_PATH, "utf8"));
  } catch {}

  // Merge hooks — replace shoofly hooks but keep other hook entries
  if (!settings.hooks) settings.hooks = {};

  if (tier === "advanced") {
    settings.hooks.PreToolUse = hookConfig.hooks.PreToolUse;
    // Remove basic hook if present
    if (settings.hooks.PostToolUse) {
      settings.hooks.PostToolUse = settings.hooks.PostToolUse.filter(
        (h) => !h.url || !h.url.includes("shoofly")
      );
      if (settings.hooks.PostToolUse.length === 0) delete settings.hooks.PostToolUse;
    }
  } else {
    settings.hooks.PostToolUse = hookConfig.hooks.PostToolUse;
    // Remove advanced hook if present
    if (settings.hooks.PreToolUse) {
      settings.hooks.PreToolUse = settings.hooks.PreToolUse.filter(
        (h) => !h.url || !h.url.includes("shoofly")
      );
      if (settings.hooks.PreToolUse.length === 0) delete settings.hooks.PreToolUse;
    }
  }

  // Ensure ~/.claude/ exists
  fs.mkdirSync(path.dirname(SETTINGS_PATH), { recursive: true });
  fs.writeFileSync(SETTINGS_PATH, JSON.stringify(settings, null, 2) + "\n");

  console.log(`✅ Claude Code settings updated for ${tier} tier: ${SETTINGS_PATH}`);
}

main();
