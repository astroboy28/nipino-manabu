<?php
// backend/api/store.php
// ─── In-App Purchase receipt validation (iOS + Android) ──────────────────────
declare(strict_types=1);

require_once dirname(__DIR__) . '/config/Database.php';
require_once dirname(__DIR__) . '/middleware/Auth.php';

// Guarded so backend/cron/subscription_renewal_check.php can safely
// require_once this file to reuse verifyAppleReceipt()/verifyGoogleReceipt()
// directly (rather than duplicating payment-critical verification logic)
// without also running the HTTP routing below against a nonexistent request.
if (PHP_SAPI !== 'cli') {
    Auth::securityHeaders();
    $db     = Database::connect();
    $method = $_SERVER['REQUEST_METHOD'];
    $action = $_GET['action'] ?? '';

    match (true) {
        $method === 'POST' && $action === 'validate-purchase'    => handleValidate($db),
        $method === 'GET'  && $action === 'products'             => handleProducts(),
        $method === 'GET'  && $action === 'subscription-status'  => handleSubscriptionStatus($db),
        default => respond(404, false, 'Endpoint not found'),
    };
}

// ════════════════════════════════════════════════════════════════════════════
// VALIDATE IAP RECEIPT
// ════════════════════════════════════════════════════════════════════════════
function handleValidate(PDO $db): void {
    $claims  = Auth::requireAuth();
    $userId  = (int)$claims['sub'];
    $body    = Auth::getJsonBody();

    $productId   = Auth::sanitizeString($body['product_id']   ?? '', 100);
    $receiptData = $body['receipt_data'] ?? '';
    $platform    = Auth::sanitizeString($body['platform']     ?? '', 10);

    if (!$productId || !$receiptData || !in_array($platform, ['ios','android'], true)) {
        respond(422, false, 'Invalid purchase data.'); return;
    }

    $cfg      = require dirname(__DIR__) . '/config/config.php';
    $products = $cfg['iap_products'];

    if (!isset($products[$productId])) {
        respond(422, false, 'Unknown product ID.'); return;
    }

    // ── Replay-attack prevention ──────────────────────────────────────────────
    $receiptHash = hash('sha256', $receiptData);
    $dupChk = $db->prepare('SELECT id FROM iap_purchases WHERE receipt_hash=?');
    $dupChk->execute([$receiptHash]);
    if ($dupChk->fetch()) {
        respond(409, false, 'This purchase has already been applied.'); return;
    }

    $isSubscription = ($products[$productId]['type'] ?? 'consumable') === 'subscription';

    // ── Verify with platform ──────────────────────────────────────────────────
    // Subscriptions and one-time products live behind different Play/App
    // Store APIs — calling the one-time-product API for a subscription token
    // (or vice versa) fails, so the product's configured type picks the path.
    $verification = $platform === 'ios'
        ? verifyAppleReceipt($receiptData, $productId, $isSubscription)
        : verifyGoogleReceipt($receiptData, $productId, $isSubscription);

    if (!$verification['valid']) {
        respond(402, false, 'Purchase verification failed. Contact support.'); return;
    }

    // ── Grant coins + (for subscriptions) record entitlement expiry ───────────
    $coinsToGrant = $products[$productId]['coins'];
    $expiresAt    = $verification['expires_at'] ?? null; // 'Y-m-d H:i:s' UTC or null

    $db->beginTransaction();
    try {
        $db->prepare(
            'INSERT INTO iap_purchases
             (user_id, product_id, platform, receipt_hash, coins_granted)
             VALUES (?,?,?,?,?)'
        )->execute([$userId, $productId, $platform, $receiptHash, $coinsToGrant]);

        $db->prepare(
            'UPDATE users SET coins=coins+? WHERE id=?'
        )->execute([$coinsToGrant, $userId]);

        if ($isSubscription && $expiresAt) {
            // Also store what's needed to re-check this subscription later
            // (backend/cron/subscription_renewal_check.php) — without this,
            // entitlement only ever updated when the client happened to
            // resubmit a fresh receipt, which doesn't happen automatically
            // on renewal.
            if ($platform === 'ios') {
                $db->prepare(
                    'UPDATE users
                     SET subscription_product_id=?, subscription_platform=?, subscription_expires_at=?,
                         subscription_apple_original_txn_id=?
                     WHERE id=?'
                )->execute([$productId, $platform, $expiresAt, $verification['original_txn_id'] ?? null, $userId]);
            } else {
                $db->prepare(
                    'UPDATE users
                     SET subscription_product_id=?, subscription_platform=?, subscription_expires_at=?,
                         subscription_google_purchase_token=?
                     WHERE id=?'
                )->execute([$productId, $platform, $expiresAt, $receiptData, $userId]);
            }
        }

        $db->commit();
    } catch (Exception $e) {
        $db->rollBack();
        error_log('IAP grant failed: ' . $e->getMessage());
        respond(500, false, 'Failed to apply purchase. Contact support.'); return;
    }

    // Return updated coin balance
    $coinStmt = $db->prepare('SELECT coins FROM users WHERE id=?');
    $coinStmt->execute([$userId]);
    $updated = $coinStmt->fetch();

    respond(200, true, 'Purchase verified and coins granted!', [
        'coins_granted'           => $coinsToGrant,
        'total_coins'             => (int)$updated['coins'],
        'product_id'              => $productId,
        'subscription_expires_at' => $isSubscription ? $expiresAt : null,
    ]);
}

// ════════════════════════════════════════════════════════════════════════════
// SUBSCRIPTION STATUS — client checks whether the user currently has an
// active premium subscription (expiry-based; no server-push notifications
// yet, so cancellations are only reflected once the current period lapses).
// ════════════════════════════════════════════════════════════════════════════
function handleSubscriptionStatus(PDO $db): void {
    $claims = Auth::requireAuth();
    $userId = (int)$claims['sub'];

    $stmt = $db->prepare(
        'SELECT subscription_product_id, subscription_platform, subscription_expires_at
         FROM users WHERE id=?'
    );
    $stmt->execute([$userId]);
    $row = $stmt->fetch();

    $expiresAt = $row['subscription_expires_at'] ?? null;
    $isActive  = $expiresAt !== null && strtotime($expiresAt) > time();

    respond(200, true, 'Subscription status fetched.', [
        'is_subscribed' => $isActive,
        'product_id'    => $isActive ? $row['subscription_product_id'] : null,
        'platform'      => $isActive ? $row['subscription_platform']   : null,
        'expires_at'    => $expiresAt,
    ]);
}

// ════════════════════════════════════════════════════════════════════════════
// LIST PRODUCTS
// ════════════════════════════════════════════════════════════════════════════
function handleProducts(): void {
    Auth::requireAuth();
    $cfg = require dirname(__DIR__) . '/config/config.php';

    $products = array_map(fn($k, $v) => array_merge(['id' => $k], $v),
        array_keys($cfg['iap_products']),
        array_values($cfg['iap_products'])
    );

    respond(200, true, 'Products fetched.', ['products' => $products]);
}

// ── Apple receipt verification ─────────────────────────────────────────────────
// Returns ['valid' => bool, 'expires_at' => ?string ('Y-m-d H:i:s' UTC, subscriptions only)]
function verifyAppleReceipt(string $receiptData, string $productId, bool $isSubscription): array {
    // Production: https://buy.itunes.apple.com/verifyReceipt
    // Sandbox:    https://sandbox.itunes.apple.com/verifyReceipt
    $cfg = require dirname(__DIR__) . '/config/config.php';
    $env = $cfg['app']['env'];
    $url = $env === 'production'
        ? 'https://buy.itunes.apple.com/verifyReceipt'
        : 'https://sandbox.itunes.apple.com/verifyReceipt';

    $payload = json_encode([
        'receipt-data' => $receiptData,
        'password'     => $_ENV['APPLE_SHARED_SECRET'] ?? '',
        'exclude-old-transactions' => true,
    ]);

    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST           => true,
        CURLOPT_POSTFIELDS     => $payload,
        CURLOPT_HTTPHEADER     => ['Content-Type: application/json'],
        CURLOPT_SSL_VERIFYPEER => true,
        CURLOPT_TIMEOUT        => 10,
    ]);
    $res  = curl_exec($ch);
    $err  = curl_error($ch);
    curl_close($ch);

    if ($err || !$res) {
        error_log("Apple IAP curl error: $err");
        return ['valid' => false, 'expires_at' => null];
    }

    $data   = json_decode($res, true);
    $status = $data['status'] ?? -1;

    // Status 0 = valid, 21007 = sandbox receipt sent to prod (retry sandbox)
    if ($status === 21007) {
        return verifyAppleSandbox($receiptData, $productId, $isSubscription);
    }
    if ($status !== 0) return ['valid' => false, 'expires_at' => null];

    return _appleResultFor($data, $productId, $isSubscription);
}

function verifyAppleSandbox(string $receiptData, string $productId, bool $isSubscription): array {
    // Same as above but forced sandbox URL
    $payload = json_encode([
        'receipt-data' => $receiptData,
        'password'     => $_ENV['APPLE_SHARED_SECRET'] ?? '',
    ]);
    $ch = curl_init('https://sandbox.itunes.apple.com/verifyReceipt');
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST           => true,
        CURLOPT_POSTFIELDS     => $payload,
        CURLOPT_HTTPHEADER     => ['Content-Type: application/json'],
        CURLOPT_SSL_VERIFYPEER => true,
        CURLOPT_TIMEOUT        => 10,
    ]);
    $res  = curl_exec($ch);
    curl_close($ch);
    $data = json_decode($res, true);
    if (($data['status'] ?? -1) !== 0) return ['valid' => false, 'expires_at' => null];
    return _appleResultFor($data, $productId, $isSubscription);
}

// Confirm product_id matches, and for subscriptions pull the latest expiry
// out of latest_receipt_info (Apple's per-transaction renewal history).
function _appleResultFor(array $data, string $productId, bool $isSubscription): array {
    if ($isSubscription) {
        $latestExpiryMs = 0;
        $originalTxnId  = null;
        foreach ($data['latest_receipt_info'] ?? [] as $txn) {
            if (($txn['product_id'] ?? '') !== $productId) continue;
            $expiryMs = (int)($txn['expires_date_ms'] ?? 0);
            if ($expiryMs > $latestExpiryMs) {
                $latestExpiryMs = $expiryMs;
                // Stable across renewals — this is what the App Store Server
                // API needs to re-check status later, unlike the receipt
                // blob itself (which represents a point-in-time snapshot).
                $originalTxnId = $txn['original_transaction_id'] ?? null;
            }
        }
        if ($latestExpiryMs <= 0) return ['valid' => false, 'expires_at' => null];
        return [
            'valid'                => true,
            'expires_at'           => gmdate('Y-m-d H:i:s', (int)($latestExpiryMs / 1000)),
            'original_txn_id'      => $originalTxnId,
        ];
    }
    $inApp = $data['receipt']['in_app'] ?? [];
    foreach ($inApp as $item) {
        if ($item['product_id'] === $productId) return ['valid' => true, 'expires_at' => null];
    }
    return ['valid' => false, 'expires_at' => null];
}

// ── Apple App Store Server API — periodic subscription re-check ──────────────
// NOT used for the initial purchase (that's verifyAppleReceipt() above, the
// legacy /verifyReceipt endpoint). This is what
// backend/cron/subscription_renewal_check.php calls to find out whether a
// subscription has renewed/lapsed since the app last submitted a receipt —
// without this, entitlement only ever updated when the client happened to
// resubmit a fresh receipt, which doesn't happen automatically on renewal.
// Needs APPLE_ASA_KEY_ID / APPLE_ASA_ISSUER_ID / APPLE_ASA_PRIVATE_KEY in
// .env (App Store Connect → Users and Access → Integrations → App Store
// Connect API → generate a key).
// Returns ['valid' => bool, 'expires_at' => ?string] like the verify* functions.
function checkAppleSubscriptionStatus(string $originalTransactionId): array {
    $keyId    = $_ENV['APPLE_ASA_KEY_ID']      ?? '';
    $issuerId = $_ENV['APPLE_ASA_ISSUER_ID']   ?? '';
    $bundleId = $_ENV['APPLE_BUNDLE_ID']       ?? 'com.nipino.manabu';
    // .env is line-based, so a multi-line PEM key is stored with literal
    // \n instead of real newlines (same trick GOOGLE_SERVICE_ACCOUNT_JSON's
    // embedded private_key already relies on, just without JSON to decode
    // it automatically) — convert back before handing it to openssl.
    $privKey  = str_replace('\n', "\n", $_ENV['APPLE_ASA_PRIVATE_KEY'] ?? '');
    if (!$keyId || !$issuerId || !$privKey) {
        error_log('Apple App Store Server API not configured (APPLE_ASA_* missing from .env)');
        return ['valid' => false, 'expires_at' => null];
    }

    $jwt = buildAppleServerApiJwt($keyId, $issuerId, $bundleId, $privKey);
    if (!$jwt) return ['valid' => false, 'expires_at' => null];

    $cfg    = require dirname(__DIR__) . '/config/config.php';
    $isLive = ($cfg['app']['env'] === 'production');
    $base   = $isLive
        ? 'https://api.storekit.itunes.apple.com'
        : 'https://api.storekit-sandbox.itunes.apple.com';

    $ch = curl_init("$base/inApps/v1/subscriptions/$originalTransactionId");
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPHEADER     => ["Authorization: Bearer $jwt"],
        CURLOPT_SSL_VERIFYPEER => true,
        CURLOPT_TIMEOUT        => 10,
    ]);
    $res  = curl_exec($ch);
    $err  = curl_error($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($err || !$res || $code !== 200) {
        error_log("Apple App Store Server API error (HTTP $code): " . ($err ?: $res));
        return ['valid' => false, 'expires_at' => null];
    }

    $data = json_decode($res, true);
    $latestExpiryMs = 0;
    foreach ($data['data'] ?? [] as $group) {
        foreach ($group['lastTransactions'] ?? [] as $txn) {
            $signed = $txn['signedTransactionInfo'] ?? null;
            if (!$signed) continue;
            // Decoding the JWS payload WITHOUT verifying its signature is
            // safe here specifically because this response arrived over an
            // HTTPS connection this server initiated directly to Apple's
            // real API host — TLS already authenticates the server. That
            // is NOT true of a webhook (an inbound POST claiming to be
            // Apple), which is why this app doesn't implement one.
            $payload  = decodeJwsPayloadUnverified($signed);
            $expiryMs = (int)($payload['expiresDate'] ?? 0);
            if ($expiryMs > $latestExpiryMs) $latestExpiryMs = $expiryMs;
        }
    }
    if ($latestExpiryMs <= 0) return ['valid' => false, 'expires_at' => null];
    return [
        'valid'      => $latestExpiryMs > (int)(microtime(true) * 1000),
        'expires_at' => gmdate('Y-m-d H:i:s', (int)($latestExpiryMs / 1000)),
    ];
}

function decodeJwsPayloadUnverified(string $jws): array {
    $parts = explode('.', $jws);
    if (count($parts) !== 3) return [];
    $b64 = strtr($parts[1], '-_', '+/') . str_repeat('=', (4 - strlen($parts[1]) % 4) % 4);
    return json_decode((string) base64_decode($b64), true) ?? [];
}

function buildAppleServerApiJwt(string $keyId, string $issuerId, string $bundleId, string $privateKeyPem): ?string {
    $now    = time();
    $header = Auth::base64url(json_encode(['alg' => 'ES256', 'kid' => $keyId, 'typ' => 'JWT']));
    $claims = Auth::base64url(json_encode([
        'iss' => $issuerId,
        'iat' => $now,
        'exp' => $now + 1200, // Apple caps this at 60 min; keep it short
        'aud' => 'appstoreconnect-v1',
        'bid' => $bundleId,
    ]));
    $toSign = "$header.$claims";

    $key = openssl_pkey_get_private($privateKeyPem);
    if (!$key) { error_log('Apple ASA JWT: invalid private key (APPLE_ASA_PRIVATE_KEY)'); return null; }

    $signed = openssl_sign($toSign, $derSig, $key, OPENSSL_ALGO_SHA256);
    if (!$signed) { error_log('Apple ASA JWT: signing failed'); return null; }

    $rawSig = derEcdsaSignatureToRaw($derSig, 32); // P-256 -> 32-byte r + 32-byte s
    if (!$rawSig) { error_log('Apple ASA JWT: DER->raw signature conversion failed'); return null; }

    return "$toSign." . Auth::base64url($rawSig);
}

// ECDSA signatures from openssl_sign() come out DER-encoded (ASN.1 SEQUENCE
// of two INTEGERs); JWS ES256 requires the raw concatenated r||s, each
// zero-padded to $len bytes. Pure format conversion — no cryptographic
// operation happens in this function.
function derEcdsaSignatureToRaw(string $der, int $len): ?string {
    $offset = 0;
    if (($der[$offset] ?? '') !== "\x30") return null; // SEQUENCE
    $offset++;
    $seqLen = ord($der[$offset] ?? "\x00");
    $offset++;
    if ($seqLen & 0x80) { $offset += $seqLen & 0x7F; } // skip long-form length bytes

    $parts = [];
    for ($i = 0; $i < 2; $i++) {
        if (($der[$offset] ?? '') !== "\x02") return null; // INTEGER
        $offset++;
        $intLen = ord($der[$offset] ?? "\x00");
        $offset++;
        $val = substr($der, $offset, $intLen);
        $offset += $intLen;
        if (strlen($val) > 0 && $val[0] === "\x00") $val = substr($val, 1);
        $parts[] = str_pad($val, $len, "\x00", STR_PAD_LEFT);
    }
    return $parts[0] . $parts[1];
}

// ── Google Play receipt verification ─────────────────────────────────────────
// Returns ['valid' => bool, 'expires_at' => ?string ('Y-m-d H:i:s' UTC, subscriptions only)]
function verifyGoogleReceipt(string $purchaseToken, string $productId, bool $isSubscription): array {
    // Requires Google Play Developer API service account
    $packageName = $_ENV['ANDROID_PACKAGE_NAME'] ?? 'com.nipino.manabu';
    $serviceKey  = $_ENV['GOOGLE_SERVICE_ACCOUNT_JSON'] ?? '';

    if (!$serviceKey) {
        error_log('Google service account JSON not configured');
        return ['valid' => false, 'expires_at' => null];
    }

    // Get OAuth2 access token for service account
    $accessToken = getGoogleAccessToken($serviceKey);
    if (!$accessToken) return ['valid' => false, 'expires_at' => null];

    // Subscriptions and one-time products are two entirely different Play
    // Developer API resources — calling "purchases/products" for a
    // subscription purchaseToken (or vice versa) returns a 4xx error.
    $url = $isSubscription
        ? "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/"
          . "$packageName/purchases/subscriptions/$productId/tokens/$purchaseToken"
        : "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/"
          . "$packageName/purchases/products/$productId/tokens/$purchaseToken";

    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPHEADER     => ["Authorization: Bearer $accessToken"],
        CURLOPT_SSL_VERIFYPEER => true,
        CURLOPT_TIMEOUT        => 10,
    ]);
    $res = curl_exec($ch);
    $err = curl_error($ch);
    curl_close($ch);

    if ($err || !$res) {
        error_log("Google Play purchase verification curl error: $err");
        return ['valid' => false, 'expires_at' => null];
    }
    $data = json_decode($res, true);

    if ($isSubscription) {
        // expiryTimeMillis is present whenever Google has a record of the
        // subscription, active or not — being past-expiry means "invalid"
        // here, since a lapsed subscription grants no entitlement.
        $expiryMs = (int)($data['expiryTimeMillis'] ?? 0);
        if ($expiryMs <= 0) return ['valid' => false, 'expires_at' => null];
        $expiresAt = gmdate('Y-m-d H:i:s', (int)($expiryMs / 1000));
        if ($expiryMs <= (int)(microtime(true) * 1000)) {
            return ['valid' => false, 'expires_at' => $expiresAt];
        }
        return ['valid' => true, 'expires_at' => $expiresAt];
    }

    // purchaseState 0 = purchased
    $valid = isset($data['purchaseState']) && (int)$data['purchaseState'] === 0;
    return ['valid' => $valid, 'expires_at' => null];
}

function getGoogleAccessToken(string $serviceKeyJson): ?string {
    $key = json_decode($serviceKeyJson, true);
    if (!$key || empty($key['private_key']) || empty($key['client_email'])) {
        error_log('Google service account JSON missing client_email/private_key');
        return null;
    }

    $now = time();
    // JWT segments MUST be base64url (unpadded, no +/), not base64 — Google's
    // token endpoint rejects the assertion otherwise. Reuse Auth's helper
    // rather than base64_encode() so this can't drift out of sync again.
    $header = Auth::base64url(json_encode(['alg' => 'RS256', 'typ' => 'JWT']));
    $claim  = Auth::base64url(json_encode([
        'iss'   => $key['client_email'],
        'scope' => 'https://www.googleapis.com/auth/androidpublisher',
        'aud'   => 'https://oauth2.googleapis.com/token',
        'iat'   => $now,
        'exp'   => $now + 3600,
    ]));
    $toSign = "$header.$claim";
    $signed = openssl_sign($toSign, $sig, $key['private_key'], 'SHA256');
    if (!$signed) {
        error_log('Google service account JWT signing failed (bad private_key?)');
        return null;
    }
    $jwt = "$toSign." . Auth::base64url($sig);

    $ch = curl_init('https://oauth2.googleapis.com/token');
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST           => true,
        CURLOPT_POSTFIELDS     => http_build_query([
            'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            'assertion'  => $jwt,
        ]),
        CURLOPT_SSL_VERIFYPEER => true,
        CURLOPT_TIMEOUT => 10,
    ]);
    $res = curl_exec($ch);
    $err = curl_error($ch);
    curl_close($ch);

    if ($err || !$res) {
        error_log("Google OAuth2 token exchange curl error: $err");
        return null;
    }
    $data = json_decode($res, true);
    if (!isset($data['access_token'])) {
        error_log('Google OAuth2 token exchange failed: ' . $res);
        return null;
    }
    return $data['access_token'];
}

function respond(int $code, bool $success, string $message, array $data = []): void {
    http_response_code($code);
    echo json_encode(array_merge(['success' => $success, 'message' => $message], $data),
        JSON_UNESCAPED_UNICODE);
}
