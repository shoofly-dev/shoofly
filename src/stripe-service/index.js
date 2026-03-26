import express from "express";
import Stripe from "stripe";
import { randomBytes } from "node:crypto";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const Database = require("better-sqlite3");
import { sendFulfillmentEmail } from "./email.js";

const app = express();
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);
const PORT = process.env.PORT || 3000;

// ---------- Token store (SQLite, persistent volume) ----------

const DB_PATH = process.env.TOKENS_DB_PATH || "/data/tokens.db";
// Ensure the directory exists (Railway volume may not pre-create subdirs)
try { mkdirSync(dirname(DB_PATH), { recursive: true }); } catch {}
const db = new Database(DB_PATH);
db.exec(`
  CREATE TABLE IF NOT EXISTS tokens (
    token TEXT PRIMARY KEY,
    email TEXT NOT NULL,
    session_id TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    used_at INTEGER
  )
`);

function createToken(email, sessionId) {
  const token = randomBytes(24).toString("hex");
  db.prepare(
    "INSERT INTO tokens (token, email, session_id, created_at) VALUES (?, ?, ?, ?)"
  ).run(token, email, sessionId, Date.now());
  return token;
}

function validateToken(token) {
  const row = db.prepare("SELECT * FROM tokens WHERE token = ?").get(token);
  if (!row) return { valid: false, reason: "unknown_token" };
  if (row.used_at) return { valid: false, reason: "already_used" };
  // Tokens expire after 48h
  if (Date.now() - row.created_at > 48 * 60 * 60 * 1000) {
    return { valid: false, reason: "expired" };
  }
  // Mark used
  db.prepare("UPDATE tokens SET used_at = ? WHERE token = ?").run(Date.now(), token);
  return { valid: true, email: row.email };
}

// ---------- GET / — Landing page ----------

const landingPage = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <meta name="description" content="Shoofly Advanced — pre-execution blocking for AI agents. $19/mo." />
  <title>Shoofly Advanced</title>
  <link rel="icon" href="data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 100 100%22><text y=%22.9em%22 font-size=%2290%22>🪰</text></svg>">
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;700&family=JetBrains+Mono:wght@400;700&display=swap" rel="stylesheet" />
  <style>
    :root {
      --bg: #0a0a0a;
      --bg-card: #111118;
      --border: #2d2d3d;
      --text: #e5e5e5;
      --text-muted: #a3a3a3;
      --accent: #6ee7b7;
      --highlight: #3b82f6;
      --danger: #f87171;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { background: var(--bg); color: var(--text); font-family: 'Inter', sans-serif; min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 24px; }
    .card { background: var(--bg-card); border: 1px solid var(--border); border-radius: 16px; padding: 48px; max-width: 520px; width: 100%; text-align: center; }
    .logo { font-size: 40px; margin-bottom: 8px; }
    h1 { font-size: 28px; font-weight: 700; color: var(--accent); margin-bottom: 8px; }
    .tagline { color: var(--text-muted); font-size: 14px; margin-bottom: 32px; }
    .price { font-size: 48px; font-weight: 700; color: #fff; }
    .price span { font-size: 16px; color: var(--text-muted); font-weight: 400; }
    .features { list-style: none; text-align: left; margin: 24px 0 32px; background: rgba(255,255,255,0.03); border-radius: 10px; padding: 16px 20px; }
    .features li { padding: 8px 0; font-size: 14px; color: var(--text-muted); border-bottom: 1px solid rgba(255,255,255,0.05); display: flex; align-items: center; gap: 10px; }
    .features li:last-child { border-bottom: none; }
    .features li::before { content: "✓"; color: var(--accent); font-weight: 700; flex-shrink: 0; }
    .btn { display: inline-block; padding: 14px 40px; background: var(--accent); color: #000; text-decoration: none; border-radius: 8px; font-weight: 700; font-size: 16px; cursor: pointer; border: none; width: 100%; transition: opacity 0.2s; }
    .btn:hover { opacity: 0.85; }
    .fine { font-size: 12px; color: #555; margin-top: 16px; }
  </style>
</head>
<body>
  <div class="card">
    <div class="logo">🪰⚡</div>
    <h1>Shoofly Advanced</h1>
    <p class="tagline">Pre-execution blocking for OpenClaw AI agents.</p>
    <div class="price">$19<span>/mo</span></div>
    <ul class="features">
      <li>Intercepts tool calls before they execute</li>
      <li>Automatic threat blocking (not just detection)</li>
      <li>Unix socket daemon + shoofly-hook extension</li>
      <li>Unified alert + block timeline</li>
      <li>Telegram, WhatsApp & macOS alerts</li>
      <li>Priority support</li>
    </ul>
    <a href="/upgrade" class="btn">Subscribe now →</a>
    <p class="fine">Billed monthly. Cancel anytime.</p>
  </div>
</body>
</html>`;

app.get("/", (_req, res) => {
  res.setHeader("Content-Type", "text/html");
  res.send(landingPage);
});

// ---------- GET /upgrade — Create Stripe Checkout session ----------

app.get("/upgrade", async (_req, res) => {
  try {
    const session = await stripe.checkout.sessions.create({
      mode: "subscription",
      line_items: [{ price: process.env.STRIPE_PRICE_ID, quantity: 1 }],
      after_completion: {
        type: "hosted_confirmation",
        hosted_confirmation: {
          custom_message: "You're all set! 🎉 Check your email for instructions to download and install Shoofly Advanced. If you don't see it within a few minutes, check your spam folder. Questions? Email us at hello@shoofly.dev",
        },
      },
      cancel_url: "https://shoofly.dev/advanced",
      customer_email: undefined,
      metadata: { source: "shoofly-advanced" },
    });
    res.redirect(303, session.url);
  } catch (err) {
    console.error("[upgrade] checkout session failed:", err.message);
    res.status(500).send("Something went wrong. Please try again.");
  }
});

// ---------- GET /validate — Token validation endpoint ----------

app.get("/validate", (req, res) => {
  const { token } = req.query;
  if (!token || typeof token !== "string") {
    return res.status(400).json({ valid: false, reason: "missing_token" });
  }
  const result = validateToken(token);
  if (result.valid) {
    console.log(`[validate] token used successfully`);
    return res.json({ valid: true });
  } else {
    console.warn(`[validate] rejected — ${result.reason}`);
    return res.status(403).json({ valid: false, reason: result.reason });
  }
});

// ---------- POST /webhook — Stripe webhook ----------

app.post("/webhook", express.raw({ type: "application/json" }), async (req, res) => {
  const sig = req.headers["stripe-signature"];

  let event;
  try {
    event = stripe.webhooks.constructEvent(req.body, sig, process.env.STRIPE_WEBHOOK_SECRET);
  } catch (err) {
    console.error("[webhook] signature verification failed:", err.message);
    return res.status(400).send("Webhook signature verification failed.");
  }

  switch (event.type) {
    case "checkout.session.completed": {
      const session = event.data.object;
      const email = session.customer_details?.email;
      if (email) {
        try {
          const token = createToken(email, session.id);
          await sendFulfillmentEmail(email, token);
          console.log(`[fulfillment] sent to ${email.replace(/(?<=.{3}).(?=.*@)/g, "*")} session=${session.id}`);
        } catch (err) {
          console.error(`[fulfillment] email send failed for session=${session.id}:`, err.message);
        }
      } else {
        console.warn(`[fulfillment] no email on session=${session.id}`);
      }
      break;
    }
    case "customer.subscription.deleted": {
      console.log(`[cancellation] subscription=${event.data.object.id}`);
      break;
    }
    default:
      console.log(`[webhook] unhandled event type: ${event.type}`);
  }

  res.json({ received: true });
});

// ---------- GET /admin/token — create a token manually (admin only) ----------

app.get("/admin/token", (req, res) => {
  const secret = req.query.secret;
  const email = req.query.email || "admin@shoofly.dev";
  if (!secret || secret !== process.env.ADMIN_SECRET) {
    return res.status(403).json({ error: "forbidden" });
  }
  const token = createToken(email, "admin-" + Date.now());
  console.log(`[admin] token created for ${email}`);
  const ts = Date.now();
  res.json({ token, install: `rm -f /tmp/shoofly-install.sh && curl -fsSL "https://shoofly.dev/install-advanced.sh?v=${ts}" -o /tmp/shoofly-install.sh && SHOOFLY_TOKEN=${token} bash /tmp/shoofly-install.sh` });
});

// ---------- GET /health ----------

app.get("/health", (_req, res) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

// ---------- Start ----------

app.listen(PORT, () => {
  console.log(`shoofly-stripe-service listening on :${PORT}`);
  console.log(`Upgrade:  https://shoofly-stripe-production.up.railway.app/upgrade`);
  console.log(`Webhook:  https://shoofly-stripe-production.up.railway.app/webhook`);
  console.log(`Validate: https://shoofly-stripe-production.up.railway.app/validate?token=<token>`);
});
