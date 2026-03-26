# Shoofly Stripe Service

Handles Shoofly Advanced purchases: Stripe Checkout → webhook → fulfillment email with install command.

Replaces the Railway app at `shoofly-stripe-production.up.railway.app`.

## Env vars

| Variable | Where to find it |
|---|---|
| `STRIPE_SECRET_KEY` | Stripe Dashboard → Developers → API keys |
| `STRIPE_WEBHOOK_SECRET` | Stripe Dashboard → Developers → Webhooks → signing secret |
| `STRIPE_PRICE_ID` | Stripe Dashboard → Products → Shoofly Advanced → Price ID (`price_...`) |
| `RESEND_API_KEY` | Resend dashboard → API Keys |
| `PORT` | Railway sets this automatically — don't set manually |

## Deploy to Railway

```bash
railway login
railway link          # link to the shoofly-stripe-production project
railway up            # deploy
```

Railway will read `railway.toml` for build/deploy config.

## DNS records

For `shoofly.dev` to proxy through this service, Evan needs:

| Type | Name | Value | Notes |
|---|---|---|---|
| CNAME | `stripe` | `shoofly-stripe-production.up.railway.app` | If using a subdomain |

Or configure Railway's custom domain to serve on the existing `shoofly-stripe-production.up.railway.app` URL (already in use — no DNS change needed if redeploying to the same Railway project).

## Stripe webhook setup

1. Go to [Stripe Dashboard → Developers → Webhooks](https://dashboard.stripe.com/webhooks)
2. Click **Add endpoint**
3. Endpoint URL: `https://shoofly-stripe-production.up.railway.app/webhook`
4. Select events:
   - `checkout.session.completed`
   - `customer.subscription.deleted`
5. Copy the **Signing secret** (`whsec_...`) into Railway env as `STRIPE_WEBHOOK_SECRET`

## Test locally with Stripe CLI

```bash
# Install Stripe CLI: https://stripe.com/docs/stripe-cli
stripe login
stripe listen --forward-to localhost:3000/webhook

# In another terminal:
cp .env.example .env   # fill in real test keys
npm install
npm run dev

# Trigger a test event:
stripe trigger checkout.session.completed
```

## Flip to live mode

1. In Stripe Dashboard, toggle to **Live mode**
2. Swap env vars:
   - `STRIPE_SECRET_KEY`: `sk_test_...` → `sk_live_...`
   - `STRIPE_PRICE_ID`: create/copy the live price ID
3. Re-register the webhook endpoint in live mode (Stripe keeps test/live webhooks separate)
4. Copy the new live webhook signing secret into `STRIPE_WEBHOOK_SECRET`

## Billing portal link

The fulfillment email includes a "Manage billing" link. To get the real URL:

1. Go to [Stripe Dashboard → Settings → Billing → Customer portal](https://dashboard.stripe.com/settings/billing/portal)
2. Enable the portal and copy the link
3. Update the placeholder `https://billing.stripe.com/p/login/your_portal_link` in `email.js`
