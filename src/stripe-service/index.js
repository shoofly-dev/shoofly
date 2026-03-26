import express from "express";
import Stripe from "stripe";
import { sendFulfillmentEmail } from "./email.js";

const app = express();
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);
const PORT = process.env.PORT || 3000;

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
      --font-body: 'Inter', system-ui, sans-serif;
      --font-mono: 'JetBrains Mono', 'Fira Code', monospace;
    }
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    html { scroll-behavior: smooth; }
    body {
      background: var(--bg); color: var(--text); font-family: var(--font-body);
      font-size: 1rem; line-height: 1.6; -webkit-font-smoothing: antialiased;
      min-height: 100vh; display: flex; flex-direction: column;
    }
    a { color: var(--accent); text-decoration: none; }
    a:hover { text-decoration: underline; }

    .container { max-width: 640px; margin: 0 auto; padding: 0 1.5rem; width: 100%; }

    /* Nav */
    .nav { border-bottom: 1px solid var(--border); padding: 1rem 1.5rem; }
    .nav-logo { font-size: 1.1rem; font-weight: 700; color: var(--accent); text-decoration: none; }

    /* Hero */
    .hero { padding: 5rem 0 4rem; text-align: center; }
    .hero-badge {
      display: inline-block; font-family: var(--font-mono); font-size: 0.8rem;
      font-weight: 700; padding: 4px 14px; border-radius: 20px;
      background: #1e3a5f; color: var(--highlight); margin-bottom: 1.5rem;
    }
    .hero h1 {
      font-size: clamp(1.75rem, 5vw, 2.5rem); font-weight: 700;
      line-height: 1.15; letter-spacing: -0.02em; margin-bottom: 1rem;
    }
    .hero p { color: var(--text-muted); font-size: 1.05rem; margin-bottom: 2.5rem; max-width: 520px; margin-left: auto; margin-right: auto; }

    .subscribe-btn {
      display: inline-block; padding: 14px 32px; font-size: 1rem; font-weight: 700;
      font-family: var(--font-body); border-radius: 4px; cursor: pointer;
      background: var(--highlight); color: #fff; border: 1px solid var(--highlight);
      text-decoration: none; transition: opacity 0.15s, transform 0.1s;
    }
    .subscribe-btn:hover { opacity: 0.88; transform: translateY(-1px); text-decoration: none; }

    /* Features */
    .features { padding: 3rem 0 4rem; border-top: 1px solid var(--border); }
    .features h2 { font-size: 1.15rem; font-weight: 700; margin-bottom: 1.25rem; text-align: center; }
    .features ul { list-style: none; max-width: 440px; margin: 0 auto; }
    .features li {
      font-size: 0.95rem; color: var(--text-muted); padding: 0.5rem 0;
      padding-left: 1.75rem; position: relative;
    }
    .features li::before { content: "\\2713"; position: absolute; left: 0; color: var(--accent); font-weight: 700; }

    /* Footer */
    .footer { margin-top: auto; padding: 1.5rem; border-top: 1px solid var(--border); text-align: center; }
    .footer span { color: var(--text-muted); font-size: 0.8rem; }
    .footer a { color: var(--text-muted); font-size: 0.8rem; font-family: var(--font-mono); }

    @media (max-width: 480px) {
      .hero { padding: 3rem 0 2.5rem; }
    }
  </style>
</head>
<body>
  <nav class="nav">
    <a href="https://shoofly.dev" class="nav-logo">🪰 Shoofly</a>
  </nav>

  <section class="hero">
    <div class="container">
      <span class="hero-badge">$19/MO</span>
      <h1>Shoofly Advanced ⚡🪰⚡</h1>
      <p>Automatic blocking before threats reach your agents. Pre-execution intercept. Upgrades seamlessly from Basic.</p>
      <a href="/upgrade" class="subscribe-btn">Subscribe</a>
    </div>
  </section>

  <section class="features">
    <div class="container">
      <h2>What you get</h2>
      <ul>
        <li>Pre-execution intercept — block threats before they run</li>
        <li>Auto-block on detection</li>
        <li>shoofly-daemon (Advanced runtime)</li>
        <li>shoofly-hook (pre-execution blocking)</li>
        <li>shoofly-check, shoofly-status, shoofly-health, shoofly-log</li>
        <li>Everything in Basic</li>
      </ul>
    </div>
  </section>

  <footer class="footer">
    <span>&copy; 2026 Shoofly</span> &nbsp;
    <a href="https://shoofly.dev/terms.html">Terms</a> &nbsp;
    <a href="https://shoofly.dev/privacy.html">Privacy</a>
  </footer>
</body>
</html>`;

app.get("/", (_req, res) => {
  res.type("html").send(landingPage);
});

// ---------- GET /upgrade — Stripe Checkout redirect ----------

app.get("/upgrade", async (_req, res) => {
  try {
    const session = await stripe.checkout.sessions.create({
      mode: "subscription",
      line_items: [{ price: process.env.STRIPE_PRICE_ID, quantity: 1 }],
      success_url: "https://shoofly.dev/advanced?purchased=1",
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
          await sendFulfillmentEmail(email);
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

// ---------- GET /health ----------

app.get("/health", (_req, res) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

// ---------- Start ----------

app.listen(PORT, () => {
  console.log(`shoofly-stripe-service listening on :${PORT}`);
});
