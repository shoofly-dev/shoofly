import { Resend } from "resend";

const resend = new Resend(process.env.RESEND_API_KEY);

export async function sendFulfillmentEmail(toEmail) {
  await resend.emails.send({
    from: "Shoofly <no-reply@shoofly.dev>",
    to: toEmail,
    subject: "Your Shoofly Advanced install command",
    html: buildHtml(),
    text: buildText(),
  });
}

function buildHtml() {
  return `<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8" /></head>
<body style="margin:0;padding:0;background:#0a0a0a;font-family:'JetBrains Mono','Fira Code','Courier New',monospace;color:#e5e5e5;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background:#0a0a0a;">
    <tr><td align="center" style="padding:40px 20px;">
      <table width="560" cellpadding="0" cellspacing="0" style="max-width:560px;width:100%;">

        <!-- Logo -->
        <tr><td style="padding-bottom:32px;font-size:20px;font-weight:700;color:#6ee7b7;">
          &#x1FAF0;&#x26A1; Shoofly Advanced
        </td></tr>

        <!-- Headline -->
        <tr><td style="padding-bottom:24px;font-size:22px;font-weight:700;color:#ffffff;line-height:1.3;">
          You're set. Here's your install command.
        </td></tr>

        <!-- Code block -->
        <tr><td style="padding-bottom:28px;">
          <table width="100%" cellpadding="0" cellspacing="0">
            <tr><td style="background:#1a1a2e;border:1px solid #2d2d3d;border-radius:6px;padding:16px 20px;font-size:14px;color:#6ee7b7;line-height:1.5;">
              <code style="font-family:'JetBrains Mono','Fira Code','Courier New',monospace;">curl -fsSL https://shoofly.dev/install-advanced.sh | bash</code>
            </td></tr>
          </table>
        </td></tr>

        <!-- What it installs -->
        <tr><td style="padding-bottom:8px;font-size:14px;font-weight:700;color:#ffffff;">
          What it installs:
        </td></tr>
        <tr><td style="padding-bottom:28px;font-size:13px;color:#a3a3a3;line-height:1.8;">
          &#x2713; shoofly-daemon (Advanced)<br/>
          &#x2713; shoofly-hook (pre-execution blocking)<br/>
          &#x2713; shoofly-check<br/>
          &#x2713; shoofly-status / shoofly-health / shoofly-log
        </td></tr>

        <!-- Divider -->
        <tr><td style="padding-bottom:24px;border-bottom:1px solid #2d2d3d;"></td></tr>

        <!-- Footer -->
        <tr><td style="padding-top:24px;font-size:12px;color:#666;line-height:1.8;">
          <a href="https://shoofly.dev/docs/advanced" style="color:#6ee7b7;text-decoration:none;">Docs</a> &nbsp;|&nbsp;
          <a href="mailto:support@shoofly.dev" style="color:#6ee7b7;text-decoration:none;">Support</a> &nbsp;|&nbsp;
          <a href="https://billing.stripe.com/p/login/your_portal_link" style="color:#6ee7b7;text-decoration:none;">Manage billing</a>
          <br/>Billed monthly. Cancel anytime.
        </td></tr>

      </table>
    </td></tr>
  </table>
</body>
</html>`;
}

function buildText() {
  return `Shoofly Advanced

You're set. Here's your install command.

    curl -fsSL https://shoofly.dev/install-advanced.sh | bash

What it installs:
  - shoofly-daemon (Advanced)
  - shoofly-hook (pre-execution blocking)
  - shoofly-check
  - shoofly-status / shoofly-health / shoofly-log

---

Docs: https://shoofly.dev/docs/advanced
Support: support@shoofly.dev
Manage billing: https://billing.stripe.com/p/login/your_portal_link

Billed monthly. Cancel anytime.`;
}
