<?php
// backend/api/privacy.php
// ─── Privacy Policy — required for App Store & Play Store approval ─────────────
// Serve at: https://nipino-manabu.com/privacy
header('Content-Type: text/html; charset=utf-8');
header('X-Content-Type-Options: nosniff');
$updated = '10 May 2026';
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Privacy Policy — Nipino-Manabu</title>
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
</style>
</head>
<body>
<div class="header">
  <h1>Nipino-Manabu — Privacy Policy</h1>
  <p>Last updated: <?= htmlspecialchars($updated) ?></p>
</div>
<div class="content">

<p>This Privacy Policy describes how <strong>Nipino-Manabu</strong>
("we", "us", "our") collects, uses, and protects your personal information
when you use our Japanese language learning application ("App").</p>

<h2>1. Information We Collect</h2>
<ul>
  <li><strong>Account data:</strong> username, email address, and bcrypt-hashed password.</li>
  <li><strong>Learning data:</strong> quiz results, level progress, scores, streaks, and coin balance.</li>
  <li><strong>Device data:</strong> Firebase device token for push notifications (optional).</li>
  <li><strong>Purchase data:</strong> in-app purchase receipts (hashed) for coin top-ups.
      We never store full payment card details.</li>
</ul>

<h2>2. How We Use Your Information</h2>
<ul>
  <li>To provide and personalise the learning experience.</li>
  <li>To maintain leaderboards and track progress across sessions.</li>
  <li>To send optional push notifications about streak reminders and new content.</li>
  <li>To verify in-app purchases with Apple App Store and Google Play.</li>
  <li>To comply with legal obligations and prevent fraud.</li>
</ul>

<h2>3. Data Storage and Security</h2>
<p>Your data is stored on servers protected by TLS 1.3 encryption in transit and
AES-256 encryption at rest. Passwords are hashed using bcrypt (cost factor 12).
Authentication uses short-lived JWT access tokens (15 minutes) and rotating
refresh tokens stored hashed with SHA-256. We implement rate limiting, SQL injection
prevention via prepared statements, and strict input validation.</p>

<h2>4. Data Sharing</h2>
<p>We do <strong>not</strong> sell, rent, or share your personal data with third
parties for marketing purposes. We share data only with:</p>
<ul>
  <li><strong>Apple / Google:</strong> IAP receipt validation only.</li>
  <li><strong>Firebase (Google):</strong> push notification delivery.</li>
  <li><strong>Law enforcement:</strong> when required by applicable law.</li>
</ul>

<h2>5. Your Rights (GDPR / Philippine Data Privacy Act)</h2>
<p>You have the right to: access your personal data, correct inaccurate data,
request deletion of your account and all associated data, withdraw consent for
push notifications at any time, and lodge a complaint with your local data
protection authority.</p>
<p>To exercise these rights, contact us at the address below.</p>

<h2>6. Data Retention</h2>
<p>We retain your account data for as long as your account is active. Quiz history
is retained for 24 months for leaderboard and progress calculation. You may delete
your account at any time from the Profile screen, which permanently removes all
personal data within 30 days.</p>

<h2>7. Children's Privacy</h2>
<p>Nipino-Manabu is suitable for all ages. We do not knowingly collect personal
information from children under 13 without verifiable parental consent. If you
believe a child has provided us with personal data without consent, please contact
us immediately.</p>

<h2>8. Push Notifications</h2>
<p>Notifications are optional and can be disabled at any time in your device
Settings. We only send study reminders and achievement alerts.</p>

<h2>9. In-App Purchases</h2>
<p>All payments are processed by Apple (App Store) or Google (Play Store) and are
subject to their respective privacy policies. We receive only a transaction receipt
hash to verify the purchase; full payment details never reach our servers.</p>

<h2>10. Changes to This Policy</h2>
<p>We may update this policy periodically. We will notify you of significant
changes via the App or by email. Continued use after changes constitutes acceptance.</p>

<div class="contact-box">
  <strong>Contact us</strong><br>
  Email: <a href="mailto:privacy@nipino-manabu.com">privacy@nipino-manabu.com</a><br>
  Website: <a href="https://nipino-manabu.com">nipino-manabu.com</a>
</div>

</div>
</body>
</html>
