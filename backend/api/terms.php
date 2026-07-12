<?php
// backend/api/terms.php
// ─── Terms of Service — required for App Store Connect + Google Play Console ──
header('Content-Type: text/html; charset=utf-8');
header('X-Content-Type-Options: nosniff');
$updated = '10 May 2026';
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Terms of Service — Nipino-Manabu</title>
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
       color:#111;background:#fff;line-height:1.7}
  .header{background:#CC0000;padding:24px 32px;color:white}
  .header h1{font-size:22px;font-weight:700}
  .header p{font-size:13px;opacity:.8;margin-top:4px}
  .content{max-width:720px;margin:0 auto;padding:40px 24px}
  h2{font-size:16px;font-weight:700;color:#CC0000;margin:28px 0 8px;
     padding-bottom:4px;border-bottom:2px solid #CC0000}
  p,li{font-size:14px;color:#333;margin-bottom:10px}
  ul{padding-left:20px;margin-bottom:12px}
  a{color:#CC0000}
  .contact-box{background:#FFF0F0;border-left:4px solid #CC0000;
    padding:16px;border-radius:0 6px 6px 0;margin-top:24px}
  .important{background:#FFF8E6;border-left:4px solid #D4920A;
    padding:12px 16px;border-radius:0 6px 6px 0;margin:16px 0}
</style>
</head>
<body>
<div class="header">
  <h1>Nipino-Manabu — Terms of Service</h1>
  <p>Last updated: <?= htmlspecialchars($updated) ?></p>
</div>
<div class="content">

<p>Please read these Terms of Service ("Terms") carefully before using
the Nipino-Manabu mobile application ("App") operated by
<strong>Nipino-Manabu</strong> ("we", "us", "our").</p>

<p>By downloading or using the App you agree to be bound by these Terms.
If you do not agree, do not use the App.</p>

<h2>1. Eligibility</h2>
<p>You must be at least 13 years old to use the App. Users under 18 must
have parental or guardian consent. By using the App you represent that
you meet these age requirements.</p>

<h2>2. Account Registration</h2>
<ul>
  <li>You must provide accurate, current information when creating an account.</li>
  <li>You are responsible for maintaining the confidentiality of your password.</li>
  <li>You must notify us immediately of any unauthorised use of your account.</li>
  <li>We reserve the right to suspend accounts that violate these Terms.</li>
</ul>

<h2>3. Acceptable Use</h2>
<p>You agree not to:</p>
<ul>
  <li>Use the App for any unlawful purpose or in violation of any regulations.</li>
  <li>Attempt to reverse engineer, decompile, or extract the App's source code.</li>
  <li>Use automated tools (bots, scrapers) to interact with the App.</li>
  <li>Attempt to gain unauthorised access to any part of the service.</li>
  <li>Harass, abuse, or harm other users.</li>
  <li>Submit false, misleading, or fraudulent information.</li>
  <li>Circumvent any in-app purchase mechanisms.</li>
</ul>

<h2>4. Intellectual Property</h2>
<p>All content in the App — including quiz questions, lesson materials,
graphics, logos, and software — is owned by Nipino-Manabu or its licensors
and is protected by copyright and intellectual property laws.</p>
<p>The JLPT (Japanese Language Proficiency Test) is a trademark of the
Japan Foundation and Japan Educational Exchanges and Services (JEES).
Nipino-Manabu is an independent learning tool and is not affiliated with,
endorsed by, or officially associated with the JLPT examination body.</p>
<p>All quiz content in this App is original and independently created.</p>

<h2>5. In-App Purchases and Coins</h2>
<div class="important">
  <strong>All in-app purchases are processed by Apple App Store or Google
  Play Store</strong> and are subject to their respective terms and refund
  policies.
</div>
<ul>
  <li>Coins are virtual currency with no monetary value outside the App.</li>
  <li>Coins cannot be transferred, sold, or redeemed for cash.</li>
  <li>We reserve the right to modify coin prices and values at any time.</li>
  <li>Coins may be forfeited if your account is terminated for violations
      of these Terms.</li>
  <li>For refund requests, contact the platform (Apple/Google) where you
      made the purchase, as all billing is handled by them.</li>
</ul>

<h2>6. Subscriptions</h2>
<p>Monthly Pass subscriptions auto-renew unless cancelled at least 24 hours
before the end of the current billing period. Manage subscriptions via your
App Store or Google Play account settings.</p>

<h2>7. User-Generated Content</h2>
<p>If you submit content (e.g., usernames, profile photos), you grant us a
non-exclusive, worldwide licence to use, display, and distribute that content
in connection with the App. You represent that you own or have the right to
submit such content.</p>

<h2>8. Disclaimers</h2>
<p>The App is provided "AS IS" and "AS AVAILABLE" without warranties of any
kind. We do not warrant that the App will be error-free, uninterrupted, or
that specific quiz results guarantee JLPT exam success. The App is a
supplemental learning tool only.</p>

<h2>9. Limitation of Liability</h2>
<p>To the maximum extent permitted by law, Nipino-Manabu shall not be liable
for any indirect, incidental, special, consequential, or punitive damages,
including loss of data, profits, or goodwill, arising out of your use of the
App.</p>
<p>Our total liability to you for any claim shall not exceed the amount you
paid us in the twelve months preceding the claim, or USD 10, whichever
is greater.</p>

<h2>10. Account Termination</h2>
<p>You may delete your account at any time through Settings → Delete Account.
We reserve the right to suspend or terminate accounts that violate these Terms,
with or without notice. Upon termination, your right to use the App ceases
immediately.</p>
<p>Following account deletion, your data is permanently removed within 30 days
as described in our <a href="/privacy">Privacy Policy</a>.</p>

<h2>11. Changes to Terms</h2>
<p>We may update these Terms from time to time. We will notify you of material
changes via the App or by email. Continued use after changes constitutes
acceptance of the revised Terms.</p>

<h2>12. Governing Law</h2>
<p>These Terms are governed by the laws of the Republic of the Philippines,
without regard to conflict of law principles. Any disputes shall be subject
to the exclusive jurisdiction of the courts of Manila, Philippines.</p>
<p>For users in the European Union: nothing in these Terms limits your rights
under applicable EU consumer protection law.</p>

<h2>13. Severability</h2>
<p>If any provision of these Terms is held invalid or unenforceable, the
remaining provisions shall continue in full force.</p>

<div class="contact-box">
  <strong>Contact us</strong><br>
  For questions about these Terms:<br>
  Email: <a href="mailto:legal@nipino-manabu.com">legal@nipino-manabu.com</a><br>
  Privacy: <a href="/privacy">Privacy Policy</a><br>
  Website: <a href="https://nipino-manabu.com">nipino-manabu.com</a>
</div>

</div>
</body>
</html>
