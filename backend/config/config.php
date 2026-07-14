<?php
// backend/config/config.php
// ─── Central configuration — load from environment, NEVER hardcode secrets ────

declare(strict_types=1);

// ── Load .env if present (use vlucas/phpdotenv in production) ─────────────────
$envFile = dirname(__DIR__) . '/.env';
if (file_exists($envFile)) {
    $lines = file($envFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    foreach ($lines as $line) {
        if (str_starts_with(trim($line), '#')) continue;
        [$k, $v] = explode('=', $line, 2) + [1 => ''];
        $_ENV[trim($k)] = trim($v);
        putenv(trim($k) . '=' . trim($v));
    }
}

return [
    // ── Database (PostgreSQL) ─────────────────────────────────────────────────
    'db' => [
        'host'    => $_ENV['DB_HOST']     ?? 'localhost',
        'port'    => $_ENV['DB_PORT']     ?? '5432',
        'name'    => $_ENV['DB_NAME']     ?? 'nipino_manabu',
        'user'    => $_ENV['DB_USER']     ?? 'nipino_user',
        'pass'    => $_ENV['DB_PASS']     ?? '',
        'sslmode' => $_ENV['DB_SSLMODE']  ?? 'require',   // ALWAYS require in prod
    ],

    // ── JWT ───────────────────────────────────────────────────────────────────
    'jwt' => [
        'secret'           => $_ENV['JWT_SECRET']    ?? '',  // 256-bit minimum
        'access_ttl'       => (int)($_ENV['JWT_ACCESS_TTL']  ?? 900),   // 15 min
        'refresh_ttl'      => (int)($_ENV['JWT_REFRESH_TTL'] ?? 2592000),// 30 days
        'algorithm'        => 'HS256',
        'issuer'           => 'nipino-manabu',
        'audience'         => 'nipino-manabu-app',
    ],

    // ── App ───────────────────────────────────────────────────────────────────
    'app' => [
        'env'          => $_ENV['APP_ENV']   ?? 'production',
        'debug'        => ($_ENV['APP_DEBUG'] ?? 'false') === 'true',
        'url'          => $_ENV['APP_URL']   ?? 'https://api.nipino-manabu.com',
        'version'      => '1.0.0',
        'bcrypt_cost'  => 12,
    ],

    // ── Rate limiting (using Redis in prod, file-based fallback) ──────────────
    'rate_limit' => [
        'login'           => ['requests' => 5,   'window' => 300],  // 5/5min
        'register'        => ['requests' => 3,   'window' => 3600], // 3/hr
        'quiz_submit'     => ['requests' => 60,  'window' => 3600], // 60/hr
        'general'         => ['requests' => 100, 'window' => 60],   // 100/min
    ],

    // ── Coins per correct answer by level ─────────────────────────────────────
    'coins' => [
        'N5' => 10, 'N4' => 15, 'N3' => 20, 'N2' => 25, 'N1' => 30,
        'streak_bonus'   => 10,
        'perfect_bonus'  => 25,
        'wrong_answer_penalty' => 10,
    ],

    // ── IAP product → coins mapping ───────────────────────────────────────────
    // 'type' defaults to 'consumable' when absent. 'subscription' products are
    // verified against the Play/App Store subscription APIs (not the one-time
    // product APIs) and get a subscription_expires_at written to the user row.
    'iap_products' => [
        'coins_100'  => ['coins' => 100,  'price' => 0.99],
        'coins_500'  => ['coins' => 500,  'price' => 3.99],
        'coins_1200' => ['coins' => 1200, 'price' => 7.99],
        'premium_monthly' => ['coins' => 500, 'price' => 4.99, 'type' => 'subscription'],
    ],
];
