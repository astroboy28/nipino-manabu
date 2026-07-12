<?php
// backend/email/Mailer.php
// ─── Transactional email service using PHPMailer-compatible SMTP ─────────────
declare(strict_types=1);

class Mailer {
    private static array $cfg;

    private static function cfg(): array {
        if (!isset(self::$cfg)) {
            self::$cfg = [
                'host'     => $_ENV['SMTP_HOST']     ?? 'smtp.sendgrid.net',
                'port'     => (int)($_ENV['SMTP_PORT'] ?? 587),
                'user'     => $_ENV['SMTP_USER']     ?? 'apikey',
                'pass'     => $_ENV['SMTP_PASS']     ?? '',
                'from'     => $_ENV['SMTP_FROM']     ?? 'noreply@nipino-manabu.com',
                'fromName' => $_ENV['SMTP_FROM_NAME'] ?? 'Nipino-Manabu',
            ];
        }
        return self::$cfg;
    }

    // ── Core SMTP send (cURL-based, no external lib required) ────────────────
    private static function send(string $to, string $toName,
        string $subject, string $html, string $text): bool
    {
        // Defense-in-depth: $to/$toName are interpolated raw into a "To:"
        // MIME header and into CURLOPT_MAIL_RCPT below. Nothing upstream
        // guarantees a caller always passed an already-validated address —
        // strip CR/LF (header injection) and reject anything that isn't a
        // plausible email address outright rather than sending to it.
        $to = str_replace(["\r", "\n"], '', $to);
        $toName = str_replace(["\r", "\n"], '', $toName);
        if (!filter_var($to, FILTER_VALIDATE_EMAIL)) {
            error_log("Mailer: refused to send to invalid address: $to");
            return false;
        }

        $c = self::cfg();

        // Build RFC 2822 message
        $boundary = '----=_Part_' . bin2hex(random_bytes(8));
        $msgId    = '<' . bin2hex(random_bytes(12)) . '@nipino-manabu.com>';
        $date     = date('r');

        $headers  = "Date: $date\r\n";
        $headers .= "Message-ID: $msgId\r\n";
        $headers .= "From: =?UTF-8?B?" . base64_encode($c['fromName']) . "?= <{$c['from']}>\r\n";
        $headers .= "To: =?UTF-8?B?" . base64_encode($toName) . "?= <$to>\r\n";
        $headers .= "Subject: =?UTF-8?B?" . base64_encode($subject) . "?=\r\n";
        $headers .= "MIME-Version: 1.0\r\n";
        $headers .= "Content-Type: multipart/alternative; boundary=\"$boundary\"\r\n";
        $headers .= "X-Mailer: Nipino-Manabu/1.0\r\n";

        $body  = "--$boundary\r\n";
        $body .= "Content-Type: text/plain; charset=UTF-8\r\n";
        $body .= "Content-Transfer-Encoding: base64\r\n\r\n";
        $body .= chunk_split(base64_encode($text)) . "\r\n";
        $body .= "--$boundary\r\n";
        $body .= "Content-Type: text/html; charset=UTF-8\r\n";
        $body .= "Content-Transfer-Encoding: base64\r\n\r\n";
        $body .= chunk_split(base64_encode($html)) . "\r\n";
        $body .= "--$boundary--\r\n";

        $raw = $headers . "\r\n" . $body;

        // SMTP via cURL
        $ch = curl_init();
        curl_setopt_array($ch, [
            CURLOPT_URL            => "smtp://{$c['host']}:{$c['port']}",
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_MAIL_FROM      => "<{$c['from']}>",
            CURLOPT_MAIL_RCPT      => ["<$to>"],
            CURLOPT_READDATA       => fopen('data://text/plain,' . urlencode($raw), 'r'),
            CURLOPT_UPLOAD         => true,
            CURLOPT_USE_SSL        => CURLUSESSL_ALL,
            CURLOPT_USERNAME       => $c['user'],
            CURLOPT_PASSWORD       => $c['pass'],
            CURLOPT_TIMEOUT        => 15,
            CURLOPT_SSL_VERIFYPEER => true,
        ]);

        curl_exec($ch);
        $err  = curl_error($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($err) {
            error_log("Mailer SMTP error to $to: $err");
            return false;
        }
        return true;
    }

    // ── Shared HTML wrapper (nipino.com red brand) ─────────────────────────
    private static function wrap(string $content, string $preheader = ''): string {
        return <<<HTML
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light">
<title>Nipino-Manabu</title>
</head>
<body style="margin:0;padding:0;background:#F2F2F2;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;">
<!-- Preheader -->
<span style="display:none;max-height:0;overflow:hidden;">{$preheader}</span>

<table width="100%" cellpadding="0" cellspacing="0" style="background:#F2F2F2;padding:32px 0;">
<tr><td align="center">
<table width="560" cellpadding="0" cellspacing="0" style="max-width:560px;width:100%;">

  <!-- Header -->
  <tr>
    <td style="background:#CC0000;padding:24px 32px;border-radius:8px 8px 0 0;">
      <table width="100%" cellpadding="0" cellspacing="0">
        <tr>
          <td>
            <span style="display:inline-block;background:white;border-radius:8px;
              width:36px;height:36px;text-align:center;line-height:36px;
              font-size:18px;font-weight:700;color:#CC0000;font-family:serif;">日</span>
            <span style="color:white;font-size:16px;font-weight:700;
              vertical-align:middle;margin-left:8px;">Nipino-Manabu</span>
          </td>
        </tr>
      </table>
    </td>
  </tr>

  <!-- Content -->
  <tr>
    <td style="background:#FFFFFF;padding:32px;border-left:1px solid #E5E5E5;
      border-right:1px solid #E5E5E5;">
      {$content}
    </td>
  </tr>

  <!-- Footer -->
  <tr>
    <td style="background:#F8F8F8;padding:20px 32px;border:1px solid #E5E5E5;
      border-top:none;border-radius:0 0 8px 8px;text-align:center;">
      <p style="margin:0;font-size:11px;color:#999;">
        Nipino-Manabu · Japanese Learning App<br>
        <a href="https://nipino-manabu.com/privacy" style="color:#CC0000;">Privacy Policy</a>
        &nbsp;·&nbsp;
        <a href="https://nipino-manabu.com" style="color:#CC0000;">Website</a>
      </p>
    </td>
  </tr>

</table>
</td></tr>
</table>
</body>
</html>
HTML;
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 1. EMAIL VERIFICATION
    // ══════════════════════════════════════════════════════════════════════════
    public static function sendVerification(
        string $to, string $username, string $token
    ): bool {
        $url  = "https://api.nipino-manabu.com/v1/auth/verify-email?token=" . urlencode($token);
        $html = self::wrap(<<<HTML
<h1 style="margin:0 0 8px;font-size:22px;font-weight:700;color:#111;">
  Verify your email</h1>
<p style="margin:0 0 24px;font-size:14px;color:#555;line-height:1.6;">
  こんにちは {$username}! Welcome to Nipino-Manabu. Click the button below
  to verify your email address and activate your account.</p>
<table width="100%" cellpadding="0" cellspacing="0">
  <tr><td align="center" style="padding:8px 0 28px;">
    <a href="{$url}" style="display:inline-block;background:#CC0000;color:white;
      text-decoration:none;font-size:14px;font-weight:700;padding:14px 36px;
      border-radius:6px;">Verify Email Address</a>
  </td></tr>
</table>
<p style="margin:0 0 8px;font-size:12px;color:#888;">
  This link expires in <strong>24 hours</strong>. If you did not create an account,
  you can safely ignore this email.</p>
<p style="margin:0;font-size:11px;color:#bbb;word-break:break-all;">
  Or paste: {$url}</p>
HTML, 'Verify your Nipino-Manabu email address');

        $text = "Verify your Nipino-Manabu email\n\n"
              . "Hello $username,\n\n"
              . "Click the link below to verify your email:\n$url\n\n"
              . "This link expires in 24 hours.\n";

        return self::send($to, $username, 'Verify your email — Nipino-Manabu', $html, $text);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 2. PASSWORD RESET
    // ══════════════════════════════════════════════════════════════════════════
    public static function sendPasswordReset(
        string $to, string $username, string $token
    ): bool {
        $url  = "https://nipino-manabu.com/reset-password?token=" . urlencode($token);
        $html = self::wrap(<<<HTML
<h1 style="margin:0 0 8px;font-size:22px;font-weight:700;color:#111;">
  Reset your password</h1>
<p style="margin:0 0 8px;font-size:14px;color:#555;line-height:1.6;">
  Hello {$username},</p>
<p style="margin:0 0 24px;font-size:14px;color:#555;line-height:1.6;">
  We received a request to reset the password for your Nipino-Manabu account.
  Click the button below to choose a new password.</p>
<table width="100%" cellpadding="0" cellspacing="0">
  <tr><td align="center" style="padding:8px 0 28px;">
    <a href="{$url}" style="display:inline-block;background:#CC0000;color:white;
      text-decoration:none;font-size:14px;font-weight:700;padding:14px 36px;
      border-radius:6px;">Reset Password</a>
  </td></tr>
</table>
<p style="margin:0 0 8px;font-size:12px;color:#888;">
  This link expires in <strong>1 hour</strong>. If you did not request a password
  reset, no action is needed — your password remains unchanged.</p>
<div style="background:#FFF0F0;border-left:3px solid #CC0000;padding:12px 16px;
  border-radius:0 4px 4px 0;margin:16px 0 0;">
  <p style="margin:0;font-size:12px;color:#CC0000;font-weight:600;">
    Security notice: Never share this link with anyone.</p>
</div>
HTML, 'Reset your Nipino-Manabu password');

        $text = "Reset your Nipino-Manabu password\n\n"
              . "Hello $username,\n\n"
              . "Reset your password here:\n$url\n\n"
              . "This link expires in 1 hour.\n"
              . "If you did not request this, ignore this email.\n";

        return self::send($to, $username,
            'Reset your password — Nipino-Manabu', $html, $text);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 3. STREAK REMINDER (sent by cron when streak is at risk)
    // ══════════════════════════════════════════════════════════════════════════
    public static function sendStreakReminder(
        string $to, string $username, int $streak
    ): bool {
        $html = self::wrap(<<<HTML
<h1 style="margin:0 0 8px;font-size:22px;font-weight:700;color:#111;">
  🔥 Don't break your streak!</h1>
<p style="margin:0 0 16px;font-size:14px;color:#555;line-height:1.6;">
  Hello {$username},</p>
<p style="margin:0 0 24px;font-size:14px;color:#555;line-height:1.6;">
  You have an impressive <strong>{$streak}-day learning streak</strong>!
  You haven't quizzed today — take 5 minutes to keep it alive.</p>
<table width="100%" cellpadding="0" cellspacing="0">
  <tr><td align="center" style="padding:8px 0 28px;">
    <a href="nipinomanabu://quiz" style="display:inline-block;background:#CC0000;
      color:white;text-decoration:none;font-size:14px;font-weight:700;
      padding:14px 36px;border-radius:6px;">Study Now</a>
  </td></tr>
</table>
<p style="margin:0;font-size:12px;color:#888;">
  Keep going — every day of practice brings you closer to fluency!</p>
HTML, "You have a $streak-day streak — don't lose it!");

        $text = "Your $streak-day streak is at risk!\n\n"
              . "Hello $username, quiz today to keep your streak alive.\n"
              . "Open Nipino-Manabu and take a quick practice.\n";

        return self::send($to, $username,
            "🔥 {$streak}-day streak at risk — Nipino-Manabu", $html, $text);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 4. WELCOME (after email verified)
    // ══════════════════════════════════════════════════════════════════════════
    public static function sendWelcome(string $to, string $username): bool {
        $html = self::wrap(<<<HTML
<h1 style="margin:0 0 8px;font-size:22px;font-weight:700;color:#111;">
  ようこそ, {$username}!</h1>
<p style="margin:0 0 16px;font-size:14px;color:#555;line-height:1.6;">
  Your account is verified and ready. Here's what you can do:</p>
<table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:24px;">
  <tr>
    <td style="padding:8px 0;border-bottom:1px solid #F0F0F0;">
      <span style="color:#CC0000;font-weight:700;">N5–N1 Levels</span>
      <span style="color:#555;font-size:13px;"> — progress through all JLPT levels</span>
    </td>
  </tr>
  <tr>
    <td style="padding:8px 0;border-bottom:1px solid #F0F0F0;">
      <span style="color:#CC0000;font-weight:700;">Kanji, Vocab, Grammar</span>
      <span style="color:#555;font-size:13px;"> — targeted practice per category</span>
    </td>
  </tr>
  <tr>
    <td style="padding:8px 0;border-bottom:1px solid #F0F0F0;">
      <span style="color:#CC0000;font-weight:700;">Leaderboards</span>
      <span style="color:#555;font-size:13px;"> — compete weekly with other learners</span>
    </td>
  </tr>
  <tr>
    <td style="padding:8px 0;">
      <span style="color:#CC0000;font-weight:700;">100 starting coins</span>
      <span style="color:#555;font-size:13px;"> — already in your account!</span>
    </td>
  </tr>
</table>
<table width="100%" cellpadding="0" cellspacing="0">
  <tr><td align="center">
    <a href="nipinomanabu://home" style="display:inline-block;background:#CC0000;
      color:white;text-decoration:none;font-size:14px;font-weight:700;
      padding:14px 36px;border-radius:6px;">Start Learning</a>
  </td></tr>
</table>
HTML, 'Your account is ready — let\'s learn Japanese!');

        $text = "ようこそ $username!\n\n"
              . "Your Nipino-Manabu account is active.\n"
              . "Open the app to start your Japanese learning journey.\n";

        return self::send($to, $username,
            'ようこそ! Your account is ready — Nipino-Manabu', $html, $text);
    }
}
