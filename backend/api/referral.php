<?php
// backend/api/referral.php
// ─── App referral links: invite friends, earn coins on signup ────────────────
declare(strict_types=1);

require_once dirname(__DIR__) . '/config/Database.php';
require_once dirname(__DIR__) . '/middleware/Auth.php';
require_once dirname(__DIR__) . '/middleware/Monitor.php';

Auth::securityHeaders();

$db     = Database::connect();
$method = $_SERVER['REQUEST_METHOD'];
$action = $_GET['action'] ?? '';

match (true) {
    $method === 'GET'  && $action === 'my-link'   => handleMyLink($db),
    $method === 'POST' && $action === 'claim'     => handleClaim($db),
    $method === 'GET'  && $action === 'stats'     => handleStats($db),
    default => respond(404, false, 'Endpoint not found'),
};

// ════════════════════════════════════════════════════════════════════════════
// GET MY REFERRAL LINK
// ════════════════════════════════════════════════════════════════════════════
function handleMyLink(PDO $db): void {
    $claims = Auth::requireAuth();
    $userId = (int) $claims['sub'];

    $stmt = $db->prepare('SELECT referral_code, referral_coins FROM users WHERE id=?');
    $stmt->execute([$userId]);
    $user = $stmt->fetch();

    $code       = $user['referral_code'];
    $deepLink   = "nipinomanabu://invite/{$code}";
    $webLink    = "https://nipino-manabu.com/invite/{$code}";
    $shareText  = "Join me on Nipino-Manabu and learn Japanese! 🇯🇵 Use my invite link to get 50 bonus coins: {$webLink}";

    respond(200, true, 'Referral link fetched.', [
        'referral_code'  => $code,
        'deep_link'      => $deepLink,
        'web_link'       => $webLink,
        'share_text'     => $shareText,
        'coins_earned'   => (int)($user['referral_coins'] ?? 0),
        'reward_per_ref' => 50,  // coins you earn when someone uses your link
        'new_user_bonus' => 50,  // coins new user gets for using a referral
    ]);
}

// ════════════════════════════════════════════════════════════════════════════
// CLAIM REFERRAL (called on first login after install via referral link)
// ════════════════════════════════════════════════════════════════════════════
function handleClaim(PDO $db): void {
    $claims      = Auth::requireAuth();
    $newUserId   = (int) $claims['sub'];
    $body        = Auth::getJsonBody();
    $refCode     = strtoupper(Auth::sanitizeString($body['referral_code'] ?? '', 12));

    if (!$refCode) { respond(422, false, 'Referral code required.'); return; }

    // Find referrer
    $refStmt = $db->prepare(
        'SELECT id, username FROM users WHERE referral_code=? AND is_active=TRUE'
    );
    $refStmt->execute([$refCode]);
    $referrer = $refStmt->fetch();
    if (!$referrer)               { respond(404, false, 'Invalid referral code.'); return; }
    if ((int)$referrer['id'] === $newUserId) { respond(409, false, 'Cannot use your own code.'); return; }

    $newUserBonus  = 50;
    $referrerBonus = 50;

    $db->beginTransaction();
    try {
        // Lock the new user's row and re-check referred_by_id inside the
        // transaction — the earlier plain SELECT could go stale under
        // concurrency (e.g. a double-tap or client retry firing two claim
        // requests together), letting both pass the check and double-grant
        // coins to both the new user and the referrer.
        $lockStmt = $db->prepare('SELECT referred_by_id FROM users WHERE id=? FOR UPDATE');
        $lockStmt->execute([$newUserId]);
        $locked = $lockStmt->fetch();
        if ($locked['referred_by_id']) {
            $db->rollBack();
            respond(409, false, 'Referral already claimed.'); return;
        }

        // Mark new user as referred
        $db->prepare(
            'UPDATE users SET referred_by_id=? WHERE id=?'
        )->execute([$referrer['id'], $newUserId]);

        // Grant coins to new user
        $db->prepare(
            'UPDATE users SET coins=coins+? WHERE id=?'
        )->execute([$newUserBonus, $newUserId]);

        // Grant coins to referrer
        $db->prepare(
            'UPDATE users SET coins=coins+?, referral_coins=referral_coins+? WHERE id=?'
        )->execute([$referrerBonus, $referrer['id']]);

        // Transaction records
        foreach ([
            [$newUserId,        $newUserBonus,  'referral_bonus', 'Joined via referral link'],
            [$referrer['id'],   $referrerBonus, 'referral_bonus', "Friend joined using your referral code"],
        ] as [$uid, $amt, $type, $desc]) {
            $balStmt = $db->prepare('SELECT coins FROM users WHERE id=?');
            $balStmt->execute([$uid]);
            $bal = (int)($balStmt->fetch()['coins'] ?? 0);
            $db->prepare(
                'INSERT INTO coin_transactions (user_id, amount, balance_after, type, description)
                 VALUES (?,?,?,?,?)'
            )->execute([$uid, $amt, $bal, $type, $desc]);
        }

        $db->commit();
    } catch (\Exception $e) {
        $db->rollBack();
        Monitor::error('referral_claim', $e->getMessage(), [], $newUserId);
        respond(500, false, 'Failed to apply referral.'); return;
    }

    respond(200, true, "Referral applied! You received {$newUserBonus} bonus coins.", [
        'coins_granted' => $newUserBonus,
        'referred_by'   => $referrer['username'],
    ]);
}

// ════════════════════════════════════════════════════════════════════════════
// REFERRAL STATS
// ════════════════════════════════════════════════════════════════════════════
function handleStats(PDO $db): void {
    $claims = Auth::requireAuth();
    $userId = (int) $claims['sub'];

    $stmt = $db->prepare(
        'SELECT referral_coins,
           (SELECT COUNT(*) FROM users WHERE referred_by_id=?) AS total_referrals
         FROM users WHERE id=?'
    );
    $stmt->execute([$userId]);
    $stats = $stmt->fetch();

    respond(200, true, 'Referral stats fetched.', [
        'total_referrals' => (int)($stats['total_referrals'] ?? 0),
        'total_coins_earned' => (int)($stats['referral_coins'] ?? 0),
    ]);
}

function respond(int $code, bool $ok, string $msg, array $data = []): void {
    http_response_code($code);
    echo json_encode(array_merge(['success'=>$ok,'message'=>$msg],$data),
        JSON_UNESCAPED_UNICODE);
}
