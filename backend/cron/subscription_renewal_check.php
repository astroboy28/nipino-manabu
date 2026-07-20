#!/usr/bin/env php
<?php
// backend/cron/subscription_renewal_check.php
// Crontab: 30 3 * * * /usr/bin/php /var/www/nipino-manabu/backend/cron/subscription_renewal_check.php >> /var/log/nipino_cron.log 2>&1
//
// Without this, a subscriber's entitlement only ever updated when their
// client happened to resubmit a fresh receipt — which doesn't happen
// automatically on renewal, so a real paying subscriber who didn't reopen
// the Store screen around their renewal date could silently lose access
// despite being charged. This re-checks anyone whose subscription is near
// its stored expiry directly against Apple/Google and updates the DB.
//
// Apple needs APPLE_ASA_KEY_ID/APPLE_ASA_ISSUER_ID/APPLE_ASA_PRIVATE_KEY in
// .env — if absent, Apple subscriptions are skipped (logged, not fatal).
// Google needs GOOGLE_SERVICE_ACCOUNT_JSON, already configured for
// purchase validation, so no extra setup there.
declare(strict_types=1);

if (PHP_SAPI !== 'cli') { http_response_code(403); exit('Forbidden'); }

$envFile = dirname(__DIR__) . '/.env';
if (file_exists($envFile)) {
    foreach (file($envFile, FILE_IGNORE_NEW_LINES|FILE_SKIP_EMPTY_LINES) as $line) {
        if (str_starts_with(trim($line), '#')) continue;
        [$k, $v] = explode('=', $line, 2) + [1 => ''];
        $_ENV[trim($k)] = trim($v);
        putenv(trim($k) . '=' . trim($v));
    }
}

require_once dirname(__DIR__) . '/middleware/Auth.php';
require_once __DIR__ . '/../api/store.php'; // guarded — see the PHP_SAPI check in store.php

$db  = Database::connect();
$log = fn(string $m) => print('[' . date('Y-m-d H:i:s') . '] ' . $m . PHP_EOL);
$log('=== Subscription renewal check START ===');

// Window: anyone whose subscription expired in the last 2 days (might have
// renewed since) or expires in the next day (catch it before it lapses).
$stmt = $db->query(
    "SELECT id, subscription_platform, subscription_product_id,
            subscription_apple_original_txn_id, subscription_google_purchase_token,
            subscription_expires_at
     FROM users
     WHERE subscription_expires_at IS NOT NULL
       AND subscription_expires_at BETWEEN NOW() - INTERVAL '2 days' AND NOW() + INTERVAL '1 day'"
);
$candidates = $stmt->fetchAll();
$log('Candidates: ' . count($candidates));

$checked = 0; $updated = 0; $skipped = 0; $errors = 0;

foreach ($candidates as $u) {
    $userId   = (int) $u['id'];
    $platform = $u['subscription_platform'];

    try {
        if ($platform === 'ios') {
            $originalTxnId = $u['subscription_apple_original_txn_id'];
            if (!$originalTxnId) { $skipped++; continue; }
            $result = checkAppleSubscriptionStatus($originalTxnId);
        } elseif ($platform === 'android') {
            $token = $u['subscription_google_purchase_token'];
            if (!$token) { $skipped++; continue; }
            $result = verifyGoogleReceipt($token, $u['subscription_product_id'], true);
        } else {
            $skipped++; continue;
        }
        $checked++;

        $newExpiry = $result['expires_at'] ?? null;
        if ($newExpiry && $newExpiry !== $u['subscription_expires_at']) {
            $db->prepare('UPDATE users SET subscription_expires_at=? WHERE id=?')
               ->execute([$newExpiry, $userId]);
            $updated++;
            $log("User $userId ($platform): expires_at {$u['subscription_expires_at']} -> $newExpiry");
        }
    } catch (\Throwable $e) {
        $errors++;
        $log("User $userId ($platform) ERROR: " . $e->getMessage());
    }
}

$log("Checked: $checked, Updated: $updated, Skipped (no token stored): $skipped, Errors: $errors");
$log('=== Subscription renewal check END ===');
