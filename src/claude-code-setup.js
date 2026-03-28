#!/usr/bin/env node
// claude-code-setup — interactive setup wizard for Shoofly Claude Code edition
// Usage: node claude-code-setup.js --tier basic | --tier advanced [--dry-run]

'use strict';

const { existsSync, writeFileSync, mkdirSync, readFileSync, copyFileSync, chmodSync } = require('fs');
const { join, dirname } = require('path');
const { execSync, execFile, spawn } = require('child_process');
const os = require('os');

// ── Resolve @clack/prompts ──────────────────────────────────────────────────
let clack;
const candidatePaths = [
  join(__dirname, '..', 'node_modules', '@clack', 'prompts'),
  '/opt/homebrew/lib/node_modules/@clack/prompts',
  join(os.homedir(), '.shoofly', 'node_modules', '@clack', 'prompts'),
];
for (const p of candidatePaths) {
  if (existsSync(p)) { try { clack = require(p); break; } catch {} }
}
if (!clack) {
  const installDir = join(os.homedir(), '.shoofly');
  mkdirSync(installDir, { recursive: true });
  console.log('Installing @clack/prompts...');
  try {
    execSync('npm install --save @clack/prompts', { cwd: installDir, stdio: 'ignore' });
    clack = require(join(installDir, 'node_modules', '@clack', 'prompts'));
  } catch {
    console.error('Failed to load @clack/prompts. Run: npm install -g @clack/prompts');
    process.exit(1);
  }
}

const { intro, outro, text, select, multiselect, confirm, note, spinner, cancel, isCancel, log } = clack;

// ── Args ─────────────────────────────────────────────────────────────────────
const args = process.argv.slice(2);
const tierIdx = args.indexOf('--tier');
const tier = tierIdx !== -1 ? args[tierIdx + 1] : null;
const dryRun = args.includes('--dry-run');

if (args.includes('--help') || args.includes('-h')) {
  console.log(`
  claude-code-setup — interactive setup wizard (Claude Code edition)

  Usage:
    node claude-code-setup.js --tier basic     Set up Shoofly Basic (detection)
    node claude-code-setup.js --tier advanced  Set up Shoofly Advanced (blocking)
    node claude-code-setup.js --dry-run        Preview without writing config
`);
  process.exit(0);
}

if (!tier || !['basic', 'advanced'].includes(tier)) {
  console.error('Error: --tier basic or --tier advanced is required.');
  process.exit(1);
}

// ── Helpers ───────────────────────────────────────────────────────────────────
const HOME = os.homedir();
const SHOOFLY_DIR = join(HOME, '.shoofly');
const CONFIG_PATH = join(SHOOFLY_DIR, 'config.json');
const BIN_DIR = join(SHOOFLY_DIR, 'bin');
const PLATFORM = process.platform;

function bail(value) {
  if (isCancel(value)) {
    const existing = readExistingConfig();
    if (existing) {
      cancel('No worries — you\'re still protected. Nothing changed.');
    } else {
      cancel('No worries. You can start over anytime — just run the installer again.');
    }
    process.exit(1);
  }
  return value;
}

function readExistingConfig() {
  try { return JSON.parse(readFileSync(CONFIG_PATH, 'utf8')); } catch { return null; }
}

function desktopLabel() {
  if (PLATFORM === 'darwin') return 'macOS notifications';
  if (PLATFORM === 'linux')  return 'Desktop notifications';
  return                            'Desktop notifications';
}

function channelLabel(v) {
  const map = {
    openclaw_gateway: 'OpenClaw',
    macos:    'macOS notifications',
    desktop:  PLATFORM === 'darwin' ? 'macOS notifications' : 'Desktop notifications',
    terminal: 'Terminal',
    telegram: 'Telegram',
  };
  return map[v] || v;
}

function channelOptions() {
  const desktopValue = PLATFORM === 'darwin' ? 'macos' : 'desktop';
  return [
    { value: 'openclaw_gateway', label: 'OpenClaw (agent events)', hint: 'fires a background system event' },
    { value: 'telegram',         label: 'Telegram', hint: 'direct message to a Telegram chat' },
    { value: desktopValue,       label: desktopLabel() },
    { value: 'terminal',         label: 'Terminal', hint: 'printed where Shoofly runs' },
  ];
}

// ── Telegram setup ────────────────────────────────────────────────────────────
async function setupTelegram(existing) {
  console.log('');
  log.info('Have a bot already? Paste your token below.');
  log.info('Need one? Open Telegram → search @BotFather → type /newbot  (takes ~30 sec)');
  console.log('');

  const tgToken = bail(await text({
    message: "Bot token\nTip: Already have one? Find it in @BotFather → My Bots → your bot → API Token",
    initialValue: existing?.telegram_bot_token || '',
    placeholder: '1234567890:ABC-DEF...',
    validate: v => !v ? 'Bot token is required' : undefined,
  }));
  const tgChatId = bail(await text({
    message: "Chat ID — where should alerts land?\nTip: Don't know yours? Message @[YourBotsName] on Telegram — it replies with your ID instantly.",
    initialValue: existing?.telegram_chat_id || '',
    placeholder: '123456789',
    validate: v => !v ? 'Chat ID is required' : undefined,
  }));

  return { telegram_bot_token: tgToken, telegram_chat_id: tgChatId };
}

// ── Review screen ─────────────────────────────────────────────────────────────
async function reviewStep(answers) {
  while (true) {
    const lines = answers.map((a, i) =>
      `  [${i + 1}]  ${a.label.padEnd(18)}${a.display}`
    );

    note(
      lines.join('\n') +
      '\n\n  Type a number to change it, or press Enter to continue.',
      'Review your settings'
    );

    const choice = bail(await text({
      message: 'Change a setting (1–' + answers.length + ') or press Enter to continue',
      placeholder: 'Enter to save',
      validate: v => {
        if (!v) return;
        const n = parseInt(v);
        if (isNaN(n) || n < 1 || n > answers.length) return `Enter a number between 1 and ${answers.length}, or press Enter`;
      },
    }));

    if (!choice) return true;

    const idx = parseInt(choice) - 1;
    const newVal = await answers[idx].edit();
    if (isCancel(newVal)) { cancel('Setup cancelled.'); process.exit(0); }
    answers[idx].value = newVal.value;
    answers[idx].display = newVal.display;
    if (newVal.side) Object.assign(answers[idx], { side: newVal.side });
  }
}

// ── Shared: install daemon, hooks, policy, LaunchAgent, smoke test ───────────
async function installAndFinish(config, telegramCreds) {
  // Store Telegram credentials in config
  if (telegramCreds) {
    config.telegram_bot_token = telegramCreds.telegram_bot_token;
    config.telegram_chat_id = telegramCreds.telegram_chat_id;
  }

  if (dryRun) {
    note(JSON.stringify(config, null, 2), 'Dry run — not saved');
  } else {
    mkdirSync(SHOOFLY_DIR, { recursive: true });
    mkdirSync(BIN_DIR, { recursive: true });
    mkdirSync(join(SHOOFLY_DIR, 'logs'), { recursive: true });
    writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2) + '\n', { mode: 0o600 });
    log.success('Configuration saved');
  }

  if (dryRun) return;

  // ── Download threat policy
  const sPol = spinner();
  sPol.start('Downloading threat policy...');
  try {
    const policyDir = join(SHOOFLY_DIR, 'policy');
    mkdirSync(policyDir, { recursive: true });
    const policyPath = join(policyDir, 'threats.yaml');
    const BASE_URL = 'https://raw.githubusercontent.com/shoofly-dev/shoofly/main';
    execSync(`curl -fsSL "${BASE_URL}/basic/policy/threats.yaml" -o "${policyPath}"`, { stdio: 'pipe' });
    sPol.stop('Threat policy downloaded  ✓');
  } catch {
    try {
      const bundled = join(dirname(dirname(__filename)), 'basic', 'policy', 'threats.yaml');
      const policyPath = join(SHOOFLY_DIR, 'policy', 'threats.yaml');
      if (existsSync(bundled)) {
        copyFileSync(bundled, policyPath);
        sPol.stop('Threat policy installed from bundle  ✓');
      } else {
        sPol.stop('⚠️  Policy download failed — run shoofly-health to diagnose');
      }
    } catch {
      sPol.stop('⚠️  Policy download failed — run shoofly-health to diagnose');
    }
  }

  // ── Inject Claude Code hooks (inlined — no external script dependency)
  const s2 = spinner();
  s2.start('Configuring Claude Code hooks...');
  try {
    const settingsPath = join(HOME, '.claude', 'settings.json');
    let claudeSettings = {};
    try { claudeSettings = JSON.parse(readFileSync(settingsPath, 'utf8')); } catch {}
    if (!claudeSettings.hooks) claudeSettings.hooks = {};
    if (tier === 'advanced') {
      claudeSettings.hooks.PreToolUse = [{ type: 'http', url: 'http://localhost:7777/shoofly/v1/pre-tool-use', matcher: '.*' }];
      if (claudeSettings.hooks.PostToolUse) {
        claudeSettings.hooks.PostToolUse = claudeSettings.hooks.PostToolUse.filter(h => !h.url || !h.url.includes('shoofly'));
        if (claudeSettings.hooks.PostToolUse.length === 0) delete claudeSettings.hooks.PostToolUse;
      }
    } else {
      claudeSettings.hooks.PostToolUse = [{ type: 'http', url: 'http://localhost:7777/shoofly/v1/post-tool-use' }];
      if (claudeSettings.hooks.PreToolUse) {
        claudeSettings.hooks.PreToolUse = claudeSettings.hooks.PreToolUse.filter(h => !h.url || !h.url.includes('shoofly'));
        if (claudeSettings.hooks.PreToolUse.length === 0) delete claudeSettings.hooks.PreToolUse;
      }
    }
    mkdirSync(join(HOME, '.claude'), { recursive: true });
    writeFileSync(settingsPath, JSON.stringify(claudeSettings, null, 2) + '\n');
    s2.stop('Claude Code hooks configured ✓');
  } catch (err) {
    s2.stop('Hook configuration failed — run shoofly-health to diagnose');
  }

  // ── Install LaunchAgent (macOS)
  if (PLATFORM === 'darwin') {
    const sLA = spinner();
    sLA.start('Installing LaunchAgent...');
    try {
      const nodePath = process.execPath;
      const plistPath = join(HOME, 'Library', 'LaunchAgents', 'dev.shoofly.claude-daemon.plist');
      const daemonPath = join(BIN_DIR, 'shoofly-claude-daemon.js');
      const plistContent = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>dev.shoofly.claude-daemon</string>
  <key>ProgramArguments</key>
  <array>
    <string>${nodePath}</string>
    <string>${daemonPath}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${join(SHOOFLY_DIR, 'logs', 'claude-daemon-stdout.log')}</string>
  <key>StandardErrorPath</key>
  <string>${join(SHOOFLY_DIR, 'logs', 'claude-daemon-stderr.log')}</string>
</dict>
</plist>`;
      mkdirSync(dirname(plistPath), { recursive: true });
      writeFileSync(plistPath, plistContent);
      try { execSync(`launchctl unload "${plistPath}" 2>/dev/null`); } catch {}
      execSync(`launchctl load "${plistPath}"`);
      sLA.stop('LaunchAgent installed — daemon starts automatically at login  ✓');
    } catch (err) {
      sLA.stop('LaunchAgent install failed — start manually: node ~/.shoofly/bin/shoofly-claude-daemon.js');
    }
  } else {
    log.info('Auto-start not yet supported on this platform. Start manually: node ~/.shoofly/bin/shoofly-claude-daemon.js');
  }

  // ── Smoke test
  const s3 = spinner();
  s3.start('Running smoke test...');
  try {
    const daemonDst = join(BIN_DIR, 'shoofly-claude-daemon.js');
    const daemon = spawn(process.execPath, [daemonDst], {
      stdio: 'ignore',
      detached: true,
    });
    daemon.unref();

    await new Promise(r => setTimeout(r, 1200));

    const endpoint = config.tier === 'advanced'
      ? '/shoofly/v1/pre-tool-use'
      : '/shoofly/v1/post-tool-use';

    const httpOk = await new Promise((resolve) => {
      const req = require('http').request({
        hostname: '127.0.0.1',
        port: 7777,
        path: endpoint,
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        timeout: 5000,
      }, (res) => resolve(res.statusCode === 200));
      req.on('error', () => resolve(false));
      req.on('timeout', () => { req.destroy(); resolve(false); });
      req.write(JSON.stringify({ tool_name: 'test', tool_input: {}, session_id: 'smoke-test' }));
      req.end();
    });

    try { process.kill(daemon.pid); } catch {}

    const notifyPath = join(BIN_DIR, 'shoofly-notify');
    if (existsSync(notifyPath)) {
      try {
        execSync(`"${notifyPath}" auto "Smoke test: Shoofly Claude Code is working!"`, { stdio: 'pipe', timeout: 10000 });
      } catch {}
    }

    if (httpOk) {
      s3.stop('Smoke test passed ✓');
    } else {
      s3.stop('Smoke test failed — run shoofly-health to diagnose');
    }
  } catch {
    s3.stop('Smoke test failed — run shoofly-health to diagnose');
  }

  // ── Remote gap disclosure
  note(
    "Dispatch cloud sessions and scheduled tasks running on Anthropic infrastructure\n" +
    "do not execute local hooks. Local Claude Code CLI sessions are fully covered.",
    "⚠️  Remote session gap"
  );
}

// ── BASIC flow ────────────────────────────────────────────────────────────────
async function runBasic() {
  intro('🪰  Shoofly Basic — OpenClaw + Claude Code\n│  Real-time threat detection for your AI agents.\n│  Flags threats the moment they appear — you stay in control.');

  const existing = readExistingConfig();
  if (existing) {
    note(
      `Already configured as ${existing.tier}  (agent: ${existing.agent_name || os.hostname().split('.')[0]}).\nWe will update your settings — nothing breaks.`,
      'Existing Install'
    );
  }

  // ── Step 1: Channels
  const channelDefaults = (existing?.tier === 'basic' && existing?.notification_channels?.length)
    ? existing.notification_channels.filter(ch =>
        ch !== 'telegram' || (existing.telegram_bot_token && existing.telegram_chat_id))
    : ['openclaw_gateway'];

  let channels = bail(await multiselect({
    message: 'Where should Shoofly send threat alerts?\n  Press Space to select · Arrow keys to navigate · Enter to confirm',
    options: channelOptions(),
    initialValues: channelDefaults,
    required: true,
  }));

  let telegramCreds = null;
  if (channels.includes('telegram')) {
    telegramCreds = await setupTelegram(existing);
  }

  // ── Step 2: Agent name
  const defaultName = existing?.agent_name || os.hostname().split('.')[0] || 'agent';
  let agentName = bail(await text({
    message: 'Confirm your agent name',
    initialValue: defaultName,
    hint: 'Press Enter to keep as-is, or type a new name',
  }));

  // ── Review
  const answers = [
    {
      label: 'Alert channels',
      display: channels.map(channelLabel).join(', '),
      value: channels,
      edit: async () => {
        const v = bail(await multiselect({
          message: 'Where should Shoofly send threat alerts?\n  Press Space to select · Arrow keys to navigate · Enter to confirm',
          options: channelOptions(),
          initialValues: channels,
          required: true,
        }));
        if (v.includes('telegram') && !telegramCreds) telegramCreds = await setupTelegram(existing);
        return { value: v, display: v.map(channelLabel).join(', ') };
      },
    },
    {
      label: 'Agent name',
      display: agentName,
      value: agentName,
      edit: async () => {
        const v = bail(await text({
          message: 'Agent name',
          placeholder: agentName,
          hint: 'Press Enter to keep "' + agentName + '", or type a new name',
          validate: () => undefined,
        }));
        const final = v || agentName;
        return { value: final, display: final };
      },
    },
  ];

  await reviewStep(answers);
  channels  = answers[0].value;
  agentName = answers[1].value;

  // ── Write config + install
  const config = {
    tier: 'basic',
    notification_channels: channels,
    agent_name: agentName,
    installed_at: new Date().toISOString(),
    version: '2.0.0',
    runtime: 'claude-code',
    policy_path: join(SHOOFLY_DIR, 'policy', 'threats.yaml'),
  };

  await installAndFinish(config, telegramCreds);

  // ── Summary
  note(
    [
      `Tier:      Basic (detection)`,
      `Channels:  ${channels.map(channelLabel).join(', ')}`,
      `Agent:     ${agentName}`,
      `Log:       ~/.shoofly/logs/alerts.log`,
    ].join('\n'),
    'All set'
  );

  outro('🪰  Shoofly Basic (OpenClaw + Claude Code) is watching.\nThreats will be flagged. You\'ll be the first to know.\n\nRun  shoofly-status  anytime to check in.');
}

// ── ADVANCED flow ─────────────────────────────────────────────────────────────
async function runAdvanced() {
  intro('⚡🪰⚡  Shoofly Advanced — OpenClaw + Claude Code\n│  Pre-execution blocking.\n│  Threats stopped before they fire — not detected after the damage is done.');

  const existing = readExistingConfig();
  if (existing?.tier === 'basic') {
    note(
      `Shoofly Basic (OpenClaw + Claude Code) detected  (agent: ${existing.agent_name || os.hostname().split('.')[0]}).\n` +
      `Advanced adds the hook layer — intercepts every tool call before it runs.\n` +
      `Your Basic settings carry over.`,
      'Upgrading from Basic'
    );
  } else if (existing?.tier === 'advanced') {
    note(
      `Already configured as Advanced  (agent: ${existing.agent_name || os.hostname().split('.')[0]}).\nYour settings will be updated.`,
      'Existing Install'
    );
  }

  // ── Step 1: Channels
  const channelDefaults = (existing?.notification_channels?.length)
    ? existing.notification_channels.filter(ch =>
        ch !== 'telegram' || (existing.telegram_bot_token && existing.telegram_chat_id))
    : ['openclaw_gateway'];

  let channels = bail(await multiselect({
    message: 'Where should Shoofly send alerts and block notifications?\n  Press Space to select · Arrow keys to navigate · Enter to confirm',
    options: channelOptions(),
    initialValues: channelDefaults,
    required: true,
  }));

  let telegramCreds = null;
  if (channels.includes('telegram')) {
    telegramCreds = await setupTelegram(existing);
  }

  // ── Step 2: Agent name
  const defaultName = existing?.agent_name || os.hostname().split('.')[0] || 'agent';
  let agentName = bail(await text({
    message: 'Confirm your agent name',
    initialValue: defaultName,
    hint: 'Press Enter to keep as-is, or type a new name',
  }));

  // ── Review
  const answers = [
    {
      label: 'Alert channels',
      display: channels.map(channelLabel).join(', '),
      value: channels,
      edit: async () => {
        const v = bail(await multiselect({
          message: 'Where should Shoofly send alerts?\n  Press Space to select · Arrow keys to navigate · Enter to confirm',
          options: channelOptions(),
          initialValues: channels,
          required: true,
        }));
        if (v.includes('telegram') && !telegramCreds) telegramCreds = await setupTelegram(existing);
        return { value: v, display: v.map(channelLabel).join(', ') };
      },
    },
    {
      label: 'Agent name',
      display: agentName,
      value: agentName,
      edit: async () => {
        const v = bail(await text({
          message: 'Agent name',
          placeholder: agentName,
          hint: 'Press Enter to keep "' + agentName + '", or type a new name',
          validate: () => undefined,
        }));
        const final = v || agentName;
        return { value: final, display: final };
      },
    },
  ];

  await reviewStep(answers);
  channels  = answers[0].value;
  agentName = answers[1].value;

  // ── Write config + install
  const config = {
    tier: 'advanced',
    notification_channels: channels,
    agent_name: agentName,
    installed_at: new Date().toISOString(),
    version: '2.0.0',
    runtime: 'claude-code',
    policy_path: join(SHOOFLY_DIR, 'policy', 'threats.yaml'),
  };

  await installAndFinish(config, telegramCreds);

  // ── Summary
  note(
    [
      `Tier:      Advanced (blocking)`,
      `Channels:  ${channels.map(channelLabel).join(', ')}`,
      `Agent:     ${agentName}`,
      `Log:       ~/.shoofly/logs/alerts.log`,
    ].join('\n'),
    'All systems go'
  );

  outro('⚡🪰⚡  Threats blocked. You\'re protected.\n\nRun  shoofly-status  to see what\'s been stopped.\nRun  shoofly-health  to verify all components.');
}

// ── Main ──────────────────────────────────────────────────────────────────────
(async () => {
  try {
    if (tier === 'basic') await runBasic();
    else await runAdvanced();
  } catch (err) {
    if (err?.name === 'ExitPromptError' || err?.message?.includes('ExitPromptError')) {
      cancel('Setup cancelled.');
      process.exit(0);
    }
    console.error('Setup error:', err.message);
    process.exit(1);
  }
})();
