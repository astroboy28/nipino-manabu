<?php
// backend/tests/integration_test.php
// ─── Black-box regression suite — runs against staging over HTTP ─────────────
// No framework/Composer dependency on purpose: this backend has neither, and
// pulling in PHPUnit just to run a handful of HTTP assertions would be more
// tooling than the tests are worth. Run with:
//   ssh nipino "php /var/www/nipino-manabu-staging/backend/tests/integration_test.php"
// Never point BASE_URL at production — every test here creates/mutates real
// rows, and /auth/register is rate-limited to 3/hour per IP (RateLimiter::
// register()), so this deliberately registers only ONE fresh account per
// run (the referee) — a fixed fixture account is reused for everything
// else via login, so re-running this often doesn't burn the quota.
declare(strict_types=1);

$BASE = getenv('NIPINO_TEST_BASE_URL') ?: 'http://localhost:8080/v1';
if (str_contains($BASE, 'api.nipino-manabu.com')) {
    fwrite(STDERR, "Refusing to run against production. Set NIPINO_TEST_BASE_URL to staging.\n");
    exit(1);
}

$pass = 0; $fail = 0;

function req(string $base, string $method, string $path, ?array $body = null, ?string $token = null): array {
    $ch = curl_init(rtrim($base, '/') . $path);
    $headers = ['Content-Type: application/json'];
    if ($token) $headers[] = "Authorization: Bearer $token";
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_CUSTOMREQUEST  => $method,
        CURLOPT_HTTPHEADER     => $headers,
        CURLOPT_TIMEOUT        => 15,
    ]);
    if ($body !== null) curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($body));
    $res  = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    return [$code, json_decode((string)$res, true) ?? []];
}

function check(string $name, bool $ok, string $detail = ''): void {
    global $pass, $fail;
    if ($ok) { $pass++; echo "  PASS  $name\n"; }
    else     { $fail++; echo "  FAIL  $name" . ($detail ? " — $detail" : '') . "\n"; }
}

// Persistent fixture account, reused across runs via login-or-register-once
// so steady-state runs don't touch the registration rate limit at all.
function fixtureUser(string $base): array {
    $email = 'fixture_referrer@nipino-manabu-test.local';
    $pass  = 'FixtureTestPass123';
    [$code, $login] = req($base, 'POST', '/auth/login', ['email' => $email, 'password' => $pass]);
    if (($login['success'] ?? false) && !empty($login['access_token'])) {
        return [$login['user']['id'], $login['access_token']];
    }
    [, $reg] = req($base, 'POST', '/auth/register', [
        'username' => 'fixture_referrer', 'email' => $email, 'password' => $pass,
    ]);
    return [$reg['user']['id'] ?? null, $reg['access_token'] ?? null];
}

echo "Nipino-Manabu integration tests — $BASE\n\n";

echo "Fixture account\n";
[$uid1, $tok1] = fixtureUser($BASE);
check('fixture account usable', $tok1 !== null);

// ── 1. /user/profile returns full field set ───────────────────────────────────
// Regression: this endpoint silently omitted is_verified/is_admin, so every
// app restart showed a verified user as unverified and could never surface
// an admin-only menu entry.
echo "\nProfile fields\n";
[, $profile] = req($BASE, 'GET', '/user/profile', null, $tok1);
check('/user/profile returns is_admin', array_key_exists('is_admin', $profile['user'] ?? []));
check('/user/profile returns is_verified', array_key_exists('is_verified', $profile['user'] ?? []));
$baseline = (int)($profile['user']['coins'] ?? 0);

// ── 2. Duel lobby leave refunds immediately and cancels the room ─────────────
// Regression: leaving before the duel started was always treated as a
// mid-game forfeit (coins lost), even though the UI promised an immediate
// refund — the coins only came back ~30 min later via the stale-room cron.
echo "\nDuel lobby leave\n";
[, $create] = req($BASE, 'POST', '/duel/create', [
    'level' => 'N5', 'category' => 'vocabulary', 'coin_bet' => 50, 'max_players' => 2,
], $tok1);
$roomId = $create['room_id'] ?? null;
check('duel room created', $roomId !== null, json_encode($create));
check('bet debited on create', ($create['new_balance'] ?? null) === $baseline - 50,
    'got ' . ($create['new_balance'] ?? 'null') . ", expected " . ($baseline - 50));

if ($roomId !== null) {
    [, $leave] = req($BASE, 'POST', '/duel/forfeit', ['room_id' => $roomId], $tok1);
    check('leave succeeds', $leave['success'] ?? false, json_encode($leave));
    [, $after] = req($BASE, 'GET', '/user/profile', null, $tok1);
    check('coins refunded immediately (not just via 30-min cron)',
        ($after['user']['coins'] ?? null) === $baseline,
        'got ' . ($after['user']['coins'] ?? 'null') . ", expected $baseline");
}

// ── 3. Referral claim actually grants both sides ──────────────────────────────
// Regression: the referrer UPDATE had 3 placeholders but only 2 bound
// values ("coins=coins+?, referral_coins=referral_coins+? WHERE id=?" with
// only [$bonus, $id]) — every claim on a valid code threw and rolled back.
echo "\nReferral claim\n";
$refereeEmail = 'itest_referee_' . bin2hex(random_bytes(4)) . '@example.com';
[, $reg2] = req($BASE, 'POST', '/auth/register', [
    'username' => 'itest_r' . substr(md5($refereeEmail), 0, 8),
    'email'    => $refereeEmail,
    'password' => 'TestPass123',
]);
$tok2 = $reg2['access_token'] ?? null;
check('referee registered', $tok2 !== null, json_encode($reg2));
check('referee starting balance is 250 coins', ($reg2['user']['coins'] ?? null) === 250);

[, $myLink] = req($BASE, 'GET', '/referral/my-link', null, $tok1);
$refCode = $myLink['referral_code'] ?? null;
check('could read referral code', $refCode !== null, json_encode($myLink));

if ($refCode && $tok2) {
    [, $claim] = req($BASE, 'POST', '/referral/claim', ['referral_code' => $refCode], $tok2);
    check('claim succeeds', $claim['success'] ?? false, json_encode($claim));
    [, $referrerAfter] = req($BASE, 'GET', '/user/profile', null, $tok1);
    [, $refereeAfter]  = req($BASE, 'GET', '/user/profile', null, $tok2);
    check('referrer received bonus coins',
        ($referrerAfter['user']['coins'] ?? 0) === $baseline + 50,
        'got ' . ($referrerAfter['user']['coins'] ?? 'null') . ", expected " . ($baseline + 50));
    check('referee received bonus coins',
        ($refereeAfter['user']['coins'] ?? 0) === 300,
        'got ' . ($refereeAfter['user']['coins'] ?? 'null'));
}

// ── 4. GDPR export includes the newer data categories ────────────────────────
// Regression: export previously omitted every table added after the
// original 2024-era schema — coin ledger, duel/challenge history,
// subscription state, referral relationships.
echo "\nGDPR export scope\n";
[, $export] = req($BASE, 'GET', '/account/export', null, $tok1);
foreach (['coin_transactions', 'duel_history', 'challenge_history', 'subscription', 'referral'] as $key) {
    check("export includes '$key'", array_key_exists($key, $export));
}

echo "\n" . str_repeat('─', 40) . "\n";
echo "$pass passed, $fail failed\n";
exit($fail > 0 ? 1 : 0);
