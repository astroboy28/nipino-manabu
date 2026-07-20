<?php
// backend/api/webpayment.php
// ─── Web coin store: Stripe + PayPal payments (browser-based, not in-app) ────
declare(strict_types=1);

require_once dirname(__DIR__) . '/config/Database.php';
require_once dirname(__DIR__) . '/middleware/Auth.php';
require_once dirname(__DIR__) . '/redis/RateLimiter.php';
require_once dirname(__DIR__) . '/middleware/Monitor.php';

Auth::securityHeaders();
Monitor::register();

$db     = Database::connect();
$method = $_SERVER['REQUEST_METHOD'];
$action = $_GET['action'] ?? '';

match (true) {
    // User-authenticated endpoints
    $method === 'GET'  && $action === 'products'          => handleProducts(),
    $method === 'POST' && $action === 'stripe-create'     => handleStripeCreate($db),
    $method === 'POST' && $action === 'paypal-create'     => handlePayPalCreate($db),
    $method === 'POST' && $action === 'paypal-capture'    => handlePayPalCapture($db),
    $method === 'GET'  && $action === 'order-status'      => handleOrderStatus($db),
    // Browser redirect fallback — paypal-create sets this as PayPal's
    // application_context.return_url, but it 404'd (no action here ever
    // matched it). Normal checkout never hits it: paypal.Buttons() captures
    // client-side via onApprove -> paypal-capture, which already has a real
    // auth token to work with. This only fires if PayPal falls back to a
    // full-page redirect (e.g. a popup-blocking mobile browser), so it
    // can't safely auto-capture (a GET redirect carries no Bearer token) —
    // it just sends the user back to finish in-page instead of 404ing.
    $method === 'GET'  && $action === 'paypal-return'     => handlePayPalReturn(),
    // Webhooks — no auth, verified by signature
    $method === 'POST' && $action === 'stripe-webhook'    => handleStripeWebhook($db),
    $method === 'POST' && $action === 'paypal-webhook'    => handlePayPalWebhook($db),
    default => respond(404, false, 'Endpoint not found'),
};

// ── Coin products catalogue ───────────────────────────────────────────────────
function products(): array {
    return [
        'coins_100'  => ['coins' => 100,  'amount' => 0.99,  'label' => 'Starter Pack',  'popular' => false],
        'coins_500'  => ['coins' => 500,  'amount' => 3.99,  'label' => 'Value Pack',    'popular' => true],
        'coins_1200' => ['coins' => 1200, 'amount' => 7.99,  'label' => 'Premium Pack',  'popular' => false],
        'coins_3000' => ['coins' => 3000, 'amount' => 17.99, 'label' => 'Mega Pack',     'popular' => false],
    ];
}

function handleProducts(): void {
    $list = array_map(fn($k, $v) => array_merge(['id' => $k], $v),
        array_keys(products()), array_values(products()));
    respond(200, true, 'Products fetched.', ['products' => $list]);
}

// ════════════════════════════════════════════════════════════════════════════
// STRIPE — create Payment Intent
// ════════════════════════════════════════════════════════════════════════════
function handleStripeCreate(PDO $db): void {
    $claims   = Auth::requireAuth();
    $userId   = (int) $claims['sub'];
    $ip       = $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';
    RateLimiter::enforce($ip, 'web_payment_create', 10, 3600);

    $body      = Auth::getJsonBody();
    $productId = Auth::sanitizeString($body['product_id'] ?? '', 50);
    $prods     = products();

    if (!isset($prods[$productId]))
        { respond(422, false, 'Invalid product.'); return; }

    $prod      = $prods[$productId];
    $amountCents = (int) round($prod['amount'] * 100);

    $cfg = require dirname(__DIR__) . '/config/config.php';
    $stripeKey = $_ENV['STRIPE_SECRET_KEY'] ?? '';
    if (!$stripeKey) { respond(500, false, 'Stripe not configured.'); return; }

    // Create Stripe PaymentIntent via cURL (no SDK required)
    $ch = curl_init('https://api.stripe.com/v1/payment_intents');
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST           => true,
        CURLOPT_POSTFIELDS     => http_build_query([
            'amount'                    => $amountCents,
            'currency'                  => 'usd',
            'automatic_payment_methods' => ['enabled' => 'true'],
            'metadata'                  => [
                'user_id'    => $userId,
                'product_id' => $productId,
                'coins'      => $prod['coins'],
            ],
            'description' => "Nipino-Manabu {$prod['label']} — {$prod['coins']} coins",
            'receipt_email' => $claims['email'] ?? '',
        ]),
        CURLOPT_USERPWD        => "$stripeKey:",
        CURLOPT_SSL_VERIFYPEER => true,
        CURLOPT_TIMEOUT        => 15,
    ]);
    $res  = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($code !== 200) {
        Monitor::error('stripe_create', "PaymentIntent failed: $res", ['user_id' => $userId]);
        respond(502, false, 'Payment provider error. Please try again.'); return;
    }

    $intent = json_decode($res, true);

    // Save pending order
    $db->prepare(
        'INSERT INTO web_payment_orders
         (user_id, gateway, gateway_order_id, product_id, coins_to_grant, amount_usd)
         VALUES (?,?,?,?,?,?)'
    )->execute([
        $userId, 'stripe', $intent['id'],
        $productId, $prod['coins'], $prod['amount'],
    ]);

    respond(200, true, 'Payment intent created.', [
        'client_secret'      => $intent['client_secret'],
        'payment_intent_id'  => $intent['id'],
        'amount'             => $prod['amount'],
        'coins'              => $prod['coins'],
        'label'              => $prod['label'],
    ]);
}

// ════════════════════════════════════════════════════════════════════════════
// STRIPE WEBHOOK — called by Stripe when payment succeeds or fails
// ════════════════════════════════════════════════════════════════════════════
function handleStripeWebhook(PDO $db): void {
    $payload   = file_get_contents('php://input');
    $sigHeader = $_SERVER['HTTP_STRIPE_SIGNATURE'] ?? '';
    $secret    = $_ENV['STRIPE_WEBHOOK_SECRET'] ?? '';

    // Verify Stripe webhook signature
    if (!verifyStripeSignature($payload, $sigHeader, $secret)) {
        http_response_code(400);
        echo json_encode(['error' => 'Invalid signature']);
        return;
    }

    $event = json_decode($payload, true);
    $type  = $event['type'] ?? '';

    if ($type === 'payment_intent.succeeded') {
        $intent    = $event['data']['object'];
        $intentId  = $intent['id'];
        $userId    = (int)($intent['metadata']['user_id'] ?? 0);
        $productId = $intent['metadata']['product_id'] ?? '';
        $coins     = (int)($intent['metadata']['coins'] ?? 0);

        if ($userId && $coins > 0) {
            grantWebCoins($db, $intentId, $userId, $coins, $productId);
        } else {
            Monitor::error('stripe_webhook',
                'payment_intent.succeeded with missing/zero metadata — coins not granted',
                ['intent_id' => $intentId, 'user_id' => $userId, 'coins' => $coins]);
        }
    } elseif ($type === 'payment_intent.payment_failed') {
        $intentId = $event['data']['object']['id'];
        // Must not downgrade an already-completed order — Stripe can
        // redeliver an earlier failed attempt's webhook (retry backoff)
        // after a later retry on the same intent actually succeeded and
        // already granted coins. Without this guard, that stale delivery
        // flips status back to 'failed', and the next redelivery of the
        // succeeded event then passes grantWebCoins()'s idempotency check
        // and double-grants.
        $db->prepare(
            "UPDATE web_payment_orders SET status='failed', updated_at=NOW()
             WHERE gateway_order_id=? AND status <> 'completed'"
        )->execute([$intentId]);
    }

    http_response_code(200);
    echo json_encode(['received' => true]);
}

function verifyStripeSignature(string $payload, string $sigHeader, string $secret): bool {
    if (!$secret || !$sigHeader) return false;
    $parts = [];
    foreach (explode(',', $sigHeader) as $part) {
        [$k, $v] = explode('=', $part, 2);
        $parts[$k][] = $v;
    }
    $timestamp = $parts['t'][0] ?? '';
    // Reject stale timestamps — without this, a captured valid payload +
    // signature is replayable indefinitely by anyone who intercepts it.
    if (!$timestamp || abs(time() - (int)$timestamp) > 300) return false;
    $expected  = hash_hmac('sha256', "$timestamp.$payload", $secret);
    foreach ($parts['v1'] ?? [] as $sig) {
        if (hash_equals($expected, $sig)) return true;
    }
    return false;
}

// ════════════════════════════════════════════════════════════════════════════
// PAYPAL — full-page redirect fallback (see routing comment above)
// ════════════════════════════════════════════════════════════════════════════
function handlePayPalReturn(): void {
    $cfg     = require dirname(__DIR__) . '/config/config.php';
    $baseUrl = rtrim($cfg['app']['url'], '/');
    header("Location: $baseUrl/store?resume=1");
    http_response_code(302);
}

// ════════════════════════════════════════════════════════════════════════════
// PAYPAL — create order
// ════════════════════════════════════════════════════════════════════════════
function handlePayPalCreate(PDO $db): void {
    $claims   = Auth::requireAuth();
    $userId   = (int) $claims['sub'];
    $ip       = $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';
    RateLimiter::enforce($ip, 'web_payment_create', 10, 3600);

    $body      = Auth::getJsonBody();
    $productId = Auth::sanitizeString($body['product_id'] ?? '', 50);
    $prods     = products();

    if (!isset($prods[$productId]))
        { respond(422, false, 'Invalid product.'); return; }

    $prod = $prods[$productId];

    $accessToken = getPayPalAccessToken();
    if (!$accessToken) { respond(502, false, 'PayPal not configured.'); return; }

    $cfg       = require dirname(__DIR__) . '/config/config.php';
    $baseUrl   = $cfg['app']['url'];
    $returnUrl = "$baseUrl/v1/webpayment/paypal-return?user_id=$userId&product_id=$productId";
    $cancelUrl = "https://nipino-manabu.com/store?cancelled=1";
    $isLive    = ($cfg['app']['env'] === 'production');
    $ppBase    = $isLive
        ? 'https://api-m.paypal.com'
        : 'https://api-m.sandbox.paypal.com';

    $orderPayload = json_encode([
        'intent' => 'CAPTURE',
        'purchase_units' => [[
            'amount'      => ['currency_code' => 'USD', 'value' => number_format($prod['amount'], 2)],
            'description' => "Nipino-Manabu {$prod['label']} — {$prod['coins']} coins",
            'custom_id'   => "$userId|$productId|{$prod['coins']}",
        ]],
        'application_context' => [
            'return_url'          => $returnUrl,
            'cancel_url'          => $cancelUrl,
            'brand_name'          => 'Nipino-Manabu',
            'landing_page'        => 'BILLING',
            'user_action'         => 'PAY_NOW',
            'shipping_preference' => 'NO_SHIPPING',
        ],
    ]);

    $ch = curl_init("$ppBase/v2/checkout/orders");
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST           => true,
        CURLOPT_POSTFIELDS     => $orderPayload,
        CURLOPT_HTTPHEADER     => [
            "Authorization: Bearer $accessToken",
            'Content-Type: application/json',
            'Prefer: return=representation',
        ],
        CURLOPT_SSL_VERIFYPEER => true,
        CURLOPT_TIMEOUT        => 15,
    ]);
    $res  = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($code !== 201) {
        Monitor::error('paypal_create', "Order create failed: $res", ['user_id' => $userId]);
        respond(502, false, 'PayPal error. Please try again.'); return;
    }

    $order    = json_decode($res, true);
    $orderId  = $order['id'];

    // Find approval URL
    $approveUrl = '';
    foreach ($order['links'] ?? [] as $link) {
        if ($link['rel'] === 'approve') { $approveUrl = $link['href']; break; }
    }

    // Save pending order
    $db->prepare(
        'INSERT INTO web_payment_orders
         (user_id, gateway, gateway_order_id, product_id, coins_to_grant, amount_usd)
         VALUES (?,?,?,?,?,?)'
    )->execute([
        $userId, 'paypal', $orderId,
        $productId, $prod['coins'], $prod['amount'],
    ]);

    respond(200, true, 'PayPal order created.', [
        'order_id'    => $orderId,
        'approve_url' => $approveUrl,
        'amount'      => $prod['amount'],
        'coins'       => $prod['coins'],
        'label'       => $prod['label'],
    ]);
}

// ════════════════════════════════════════════════════════════════════════════
// PAYPAL — capture approved order
// ════════════════════════════════════════════════════════════════════════════
function handlePayPalCapture(PDO $db): void {
    $claims  = Auth::requireAuth();
    $userId  = (int) $claims['sub'];
    $body    = Auth::getJsonBody();
    $orderId = Auth::sanitizeString($body['order_id'] ?? '', 100);

    if (!$orderId) { respond(422, false, 'Order ID required.'); return; }

    // Verify order belongs to this user
    $orderStmt = $db->prepare(
        "SELECT id, coins_to_grant, product_id, status
         FROM web_payment_orders
         WHERE gateway_order_id=? AND user_id=? AND gateway='paypal'"
    );
    $orderStmt->execute([$orderId, $userId]);
    $order = $orderStmt->fetch();

    if (!$order) { respond(404, false, 'Order not found.'); return; }
    if ($order['status'] === 'completed') { respond(409, false, 'Already captured.'); return; }

    $accessToken = getPayPalAccessToken();
    if (!$accessToken) { respond(502, false, 'PayPal error.'); return; }

    $cfg   = require dirname(__DIR__) . '/config/config.php';
    $isLive = ($cfg['app']['env'] === 'production');
    $ppBase = $isLive
        ? 'https://api-m.paypal.com'
        : 'https://api-m.sandbox.paypal.com';

    $ch = curl_init("$ppBase/v2/checkout/orders/$orderId/capture");
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST           => true,
        CURLOPT_POSTFIELDS     => '{}',
        CURLOPT_HTTPHEADER     => [
            "Authorization: Bearer $accessToken",
            'Content-Type: application/json',
        ],
        CURLOPT_SSL_VERIFYPEER => true,
        CURLOPT_TIMEOUT        => 15,
    ]);
    $res  = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    $captured = json_decode($res, true);

    if ($code !== 201 || ($captured['status'] ?? '') !== 'COMPLETED') {
        Monitor::error('paypal_capture', "Capture failed: $res", ['user_id' => $userId]);
        respond(502, false, 'Payment capture failed. Contact support.'); return;
    }

    // Grant coins
    $coins = (int) $order['coins_to_grant'];
    grantWebCoins($db, $orderId, $userId, $coins, $order['product_id']);

    // Fetch updated balance
    $balStmt = $db->prepare('SELECT coins FROM users WHERE id=?');
    $balStmt->execute([$userId]);
    $newBal = (int)($balStmt->fetch()['coins'] ?? 0);

    respond(200, true, "Payment successful! $coins coins added.", [
        'coins_granted' => $coins,
        'total_coins'   => $newBal,
    ]);
}

// ════════════════════════════════════════════════════════════════════════════
// PAYPAL WEBHOOK (IPN-style for server-initiated events)
// ════════════════════════════════════════════════════════════════════════════
function handlePayPalWebhook(PDO $db): void {
    $payload    = file_get_contents('php://input');
    $webhookId  = $_ENV['PAYPAL_WEBHOOK_ID'] ?? '';
    $headers    = getallheaders();

    // Fail closed: an unset PAYPAL_WEBHOOK_ID must NOT be treated as "skip
    // verification" — that would let anyone POST a forged webhook and grant
    // themselves coins. Misconfiguration is a 500 to fix, not an open door.
    if (!$webhookId) {
        error_log('PayPal webhook rejected: PAYPAL_WEBHOOK_ID is not configured.');
        http_response_code(500);
        echo json_encode(['error' => 'Webhook not configured']);
        return;
    }
    if (!verifyPayPalWebhook($payload, $headers, $webhookId)) {
        http_response_code(400);
        echo json_encode(['error' => 'Invalid webhook']);
        return;
    }

    $event     = json_decode($payload, true);
    $eventType = $event['event_type'] ?? '';

    if ($eventType === 'PAYMENT.CAPTURE.COMPLETED') {
        $resource  = $event['resource'] ?? [];
        $customId  = $resource['custom_id'] ?? '';   // user_id|product_id|coins
        $captureId = $resource['id'] ?? '';
        $parts     = explode('|', $customId);

        if (count($parts) === 3) {
            [$userId, $productId, $coins] = $parts;
            $orderId = $resource['supplementary_data']['related_ids']['order_id'] ?? null;

            if (!$orderId) {
                // PayPal didn't include the order ID on this capture event.
                // Previously this fell back to the (unrelated) capture ID,
                // which never matches the gateway_order_id stored at
                // paypal-create time — grantWebCoins would then credit coins
                // without ever marking an order 'completed', so every retry
                // of the same webhook re-granted coins. Resolve the real
                // order from our own pending row instead.
                $pendingStmt = $db->prepare(
                    "SELECT gateway_order_id FROM web_payment_orders
                     WHERE user_id=? AND product_id=? AND gateway='paypal' AND status='pending'
                     ORDER BY created_at DESC LIMIT 1"
                );
                $pendingStmt->execute([(int)$userId, $productId]);
                $orderId = $pendingStmt->fetch()['gateway_order_id'] ?? null;
            }

            if ($orderId) {
                grantWebCoins($db, $orderId, (int)$userId, (int)$coins, $productId);
            } else {
                Monitor::error('paypal_webhook', 'Could not resolve order_id for capture', [
                    'capture_id' => $captureId, 'custom_id' => $customId,
                ]);
            }
        }
    }

    http_response_code(200);
    echo json_encode(['received' => true]);
}

function verifyPayPalWebhook(string $payload, array $headers, string $webhookId): bool {
    $accessToken = getPayPalAccessToken();
    if (!$accessToken) return false;

    $cfg    = require dirname(__DIR__) . '/config/config.php';
    $isLive = ($cfg['app']['env'] === 'production');
    $ppBase = $isLive ? 'https://api-m.paypal.com' : 'https://api-m.sandbox.paypal.com';

    $verifyBody = json_encode([
        'auth_algo'         => $headers['PAYPAL-AUTH-ALGO'] ?? '',
        'cert_url'          => $headers['PAYPAL-CERT-URL'] ?? '',
        'transmission_id'   => $headers['PAYPAL-TRANSMISSION-ID'] ?? '',
        'transmission_sig'  => $headers['PAYPAL-TRANSMISSION-SIG'] ?? '',
        'transmission_time' => $headers['PAYPAL-TRANSMISSION-TIME'] ?? '',
        'webhook_id'        => $webhookId,
        'webhook_event'     => json_decode($payload, true),
    ]);

    $ch = curl_init("$ppBase/v1/notifications/verify-webhook-signature");
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST           => true,
        CURLOPT_POSTFIELDS     => $verifyBody,
        CURLOPT_HTTPHEADER     => ["Authorization: Bearer $accessToken", 'Content-Type: application/json'],
        CURLOPT_TIMEOUT        => 10,
    ]);
    $res = curl_exec($ch);
    curl_close($ch);
    $data = json_decode($res, true);
    return ($data['verification_status'] ?? '') === 'SUCCESS';
}

// ════════════════════════════════════════════════════════════════════════════
// ORDER STATUS — poll from frontend after payment
// ════════════════════════════════════════════════════════════════════════════
function handleOrderStatus(PDO $db): void {
    $claims  = Auth::requireAuth();
    $userId  = (int) $claims['sub'];
    $orderId = $_GET['order_id'] ?? '';

    $stmt = $db->prepare(
        'SELECT status, coins_to_grant, coins_granted_at
         FROM web_payment_orders
         WHERE gateway_order_id=? AND user_id=?'
    );
    $stmt->execute([$orderId, $userId]);
    $order = $stmt->fetch();
    if (!$order) { respond(404, false, 'Order not found.'); return; }

    $balStmt = $db->prepare('SELECT coins FROM users WHERE id=?');
    $balStmt->execute([$userId]);
    $bal = (int)($balStmt->fetch()['coins'] ?? 0);

    respond(200, true, 'Order status fetched.', [
        'status'        => $order['status'],
        'coins_granted' => (int) $order['coins_to_grant'],
        'total_coins'   => $bal,
    ]);
}

// ════════════════════════════════════════════════════════════════════════════
// SHARED: grant coins safely (idempotent — safe to call twice)
// ════════════════════════════════════════════════════════════════════════════
function grantWebCoins(PDO $db, string $gatewayOrderId, int $userId,
    int $coins, string $productId): void
{
    $db->beginTransaction();
    try {
        // Lock the order row for the rest of this transaction so a
        // concurrent duplicate delivery (webhook retry racing the client
        // capture call, or two webhook deliveries) can't both pass the
        // status check before either commits.
        $orderStmt = $db->prepare(
            "SELECT id, status FROM web_payment_orders WHERE gateway_order_id=? FOR UPDATE"
        );
        $orderStmt->execute([$gatewayOrderId]);
        $order = $orderStmt->fetch();

        if (!$order) {
            // Unknown/unresolved order ID — do NOT blindly credit coins for
            // an ID we can't tie to a real order row (this previously
            // happened whenever the caller passed an ID that didn't match
            // any row, silently re-granting coins on every retry since no
            // row ever transitioned to 'completed').
            $db->rollBack();
            Monitor::error('web_payment', 'grantWebCoins: no matching order row', [
                'order_id' => $gatewayOrderId, 'user_id' => $userId,
            ], $userId);
            return;
        }
        if ($order['status'] === 'completed') {
            $db->rollBack(); // already granted — idempotent no-op
            return;
        }

        $db->prepare(
            "UPDATE web_payment_orders
             SET status='completed', coins_granted_at=NOW(), updated_at=NOW()
             WHERE id=?"
        )->execute([$order['id']]);

        $db->prepare(
            'UPDATE users SET coins=coins+? WHERE id=?'
        )->execute([$coins, $userId]);

        $balStmt = $db->prepare('SELECT coins FROM users WHERE id=?');
        $balStmt->execute([$userId]);
        $newBal = (int)($balStmt->fetch()['coins'] ?? 0);

        $db->prepare(
            "INSERT INTO coin_transactions
             (user_id, amount, balance_after, type, description)
             VALUES (?,?,?,'iap_purchase',?)"
        )->execute([
            $userId, $coins, $newBal,
            "Web purchase: $productId ($coins coins)",
        ]);

        $db->commit();
        Monitor::info('web_payment', "Granted $coins coins to user $userId", [
            'order_id' => $gatewayOrderId, 'product' => $productId,
        ], $userId);
    } catch (\Exception $e) {
        $db->rollBack();
        Monitor::error('web_payment', 'grantWebCoins failed: ' . $e->getMessage(),
            ['order_id' => $gatewayOrderId], $userId);
    }
}

// ── PayPal OAuth2 token ───────────────────────────────────────────────────────
function getPayPalAccessToken(): ?string {
    $clientId = $_ENV['PAYPAL_CLIENT_ID']     ?? '';
    $secret   = $_ENV['PAYPAL_CLIENT_SECRET'] ?? '';
    if (!$clientId || !$secret) return null;

    $cfg    = require dirname(__DIR__) . '/config/config.php';
    $isLive = ($cfg['app']['env'] === 'production');
    $ppBase = $isLive
        ? 'https://api-m.paypal.com'
        : 'https://api-m.sandbox.paypal.com';

    $ch = curl_init("$ppBase/v1/oauth2/token");
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST           => true,
        CURLOPT_POSTFIELDS     => 'grant_type=client_credentials',
        CURLOPT_USERPWD        => "$clientId:$secret",
        CURLOPT_SSL_VERIFYPEER => true,
        CURLOPT_TIMEOUT        => 10,
    ]);
    $res = curl_exec($ch);
    curl_close($ch);
    $data = json_decode($res, true);
    return $data['access_token'] ?? null;
}

function respond(int $code, bool $ok, string $msg, array $data = []): void {
    http_response_code($code);
    echo json_encode(array_merge(['success' => $ok, 'message' => $msg], $data),
        JSON_UNESCAPED_UNICODE);
}
