<?php
// backend/api/user.php
// ─── User profile & progress endpoints ───────────────────────────────────────
declare(strict_types=1);

require_once dirname(__DIR__) . '/config/Database.php';
require_once dirname(__DIR__) . '/middleware/Auth.php';
require_once dirname(__DIR__) . '/middleware/Monitor.php';
require_once dirname(__DIR__) . '/redis/RateLimiter.php';

Auth::securityHeaders();
Monitor::register();
$db     = Database::connect();
$method = $_SERVER['REQUEST_METHOD'];
$action = $_GET['action'] ?? '';

match (true) {
    $method === 'GET'  && $action === 'profile'  => handleProfile($db),
    $method === 'GET'  && $action === 'progress' => handleProgress($db),
    $method === 'GET'  && $action === 'badges'   => handleBadges($db),
    $method === 'GET'  && $action === 'history'  => handleHistory($db),
    $method === 'GET'  && $action === 'search'   => handleSearch($db),
    $method === 'PUT'  && $action === 'profile'  => handleUpdateProfile($db),
    $method === 'POST' && $action === 'daily-bonus' => handleDailyBonus($db),
    default => respond(404, false, 'Endpoint not found'),
};

// ── POST /user/daily-bonus ────────────────────────────────────────────────────
// Idempotent — safe to call on every app launch. Only the first call each
// calendar day actually awards coins; the WHERE clause on the UPDATE makes
// the "already claimed today" check and the award atomic, so two requests
// racing on app resume can't both succeed.
function handleDailyBonus(PDO $db): void {
    $claims = Auth::requireAuth();
    $userId = (int)$claims['sub'];
    $cfg    = require dirname(__DIR__) . '/config/config.php';
    $bonus  = (int)($cfg['coins']['daily_login_bonus'] ?? 10);

    $db->beginTransaction();
    try {
        $stmt = $db->prepare(
            'UPDATE users SET coins=coins+?, last_login_bonus_date=CURRENT_DATE
             WHERE id=? AND is_active=TRUE
               AND (last_login_bonus_date IS NULL OR last_login_bonus_date<CURRENT_DATE)
             RETURNING coins'
        );
        $stmt->execute([$bonus, $userId]);
        $row = $stmt->fetch();

        if ($row) {
            $db->prepare(
                "INSERT INTO coin_transactions (user_id,amount,balance_after,type,description)
                 VALUES (?,?,?,'daily_login_bonus','Daily login bonus')"
            )->execute([$userId, $bonus, (int)$row['coins']]);
            $db->commit();
            respond(200, true, 'Daily bonus claimed!',
                ['awarded' => true, 'coins_earned' => $bonus, 'total_coins' => (int)$row['coins']]);
            return;
        }

        $db->rollBack();
        $curStmt = $db->prepare('SELECT coins FROM users WHERE id=?');
        $curStmt->execute([$userId]);
        respond(200, true, 'Already claimed today.',
            ['awarded' => false, 'coins_earned' => 0, 'total_coins' => (int)($curStmt->fetch()['coins'] ?? 0)]);
    } catch (\Throwable $e) {
        $db->rollBack();
        Monitor::error('daily_bonus', $e->getMessage(), [], $userId);
        respond(500, false, 'Failed to claim daily bonus.');
    }
}

// ── GET /user/profile ─────────────────────────────────────────────────────────
function handleProfile(PDO $db): void {
    $claims = Auth::requireAuth();
    $userId = (int)$claims['sub'];

    $stmt = $db->prepare(
        'SELECT id, uuid, username, email, coins, streak_days,
                current_level, total_score, avatar_url, is_verified, is_admin, created_at
         FROM users WHERE id=? AND is_active=TRUE'
    );
    $stmt->execute([$userId]);
    $user = $stmt->fetch();

    if (!$user) { respond(404, false, 'User not found.'); return; }

    respond(200, true, 'Profile fetched.', ['user' => $user]);
}

// ── GET /user/progress ────────────────────────────────────────────────────────
function handleProgress(PDO $db): void {
    $claims = Auth::requireAuth();
    $userId = (int)$claims['sub'];

    $stmt = $db->prepare(
        'SELECT level, completed_topics, total_topics, exam_unlocked
         FROM user_level_progress
         WHERE user_id=?
         ORDER BY CASE level
           WHEN \'N5\' THEN 1 WHEN \'N4\' THEN 2 WHEN \'N3\' THEN 3
           WHEN \'N2\' THEN 4 WHEN \'N1\' THEN 5 END'
    );
    $stmt->execute([$userId]);
    $rows = $stmt->fetchAll();

    $progress = array_map(function (array $r): array {
        $r['percent']          = $r['total_topics'] > 0
            ? round($r['completed_topics'] / $r['total_topics'], 2)
            : 0;
        $r['completed_topics'] = (int)$r['completed_topics'];
        $r['total_topics']     = (int)$r['total_topics'];
        $r['exam_unlocked']    = (bool)$r['exam_unlocked'];
        return $r;
    }, $rows);

    respond(200, true, 'Progress fetched.', ['progress' => $progress]);
}

// ── GET /user/badges ──────────────────────────────────────────────────────────
function handleBadges(PDO $db): void {
    $claims = Auth::requireAuth();
    $userId = (int)$claims['sub'];

    $stmt = $db->prepare(
        'SELECT b.id, b.name, b.description, b.icon_emoji,
                (ub.user_id IS NOT NULL) AS earned,
                ub.earned_at
         FROM badges b
         LEFT JOIN user_badges ub ON ub.badge_id=b.id AND ub.user_id=?
         ORDER BY b.id'
    );
    $stmt->execute([$userId]);
    $badges = $stmt->fetchAll();

    $badges = array_map(function (array $b): array {
        $b['earned'] = (bool)$b['earned'];
        return $b;
    }, $badges);

    respond(200, true, 'Badges fetched.', ['badges' => $badges]);
}

// ── GET /user/history ─────────────────────────────────────────────────────────
function handleHistory(PDO $db): void {
    $claims = Auth::requireAuth();
    $userId = (int)$claims['sub'];
    $limit  = min((int)($_GET['limit'] ?? 20), 50);
    $offset = max((int)($_GET['offset'] ?? 0), 0);

    $stmt = $db->prepare(
        'SELECT level, category, correct_count, total_count,
                score_percent, time_taken_seconds, coins_earned, taken_at
         FROM quiz_results
         WHERE user_id=?
         ORDER BY taken_at DESC
         LIMIT ? OFFSET ?'
    );
    $stmt->execute([$userId, $limit, $offset]);
    $history = $stmt->fetchAll();

    respond(200, true, 'History fetched.', [
        'history' => $history,
        'limit'   => $limit,
        'offset'  => $offset,
    ]);
}

// ── GET /user/search ──────────────────────────────────────────────────────────
function handleSearch(PDO $db): void {
    $claims = Auth::requireAuth();
    $userId = (int)$claims['sub'];
    $ip     = $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';
    RateLimiter::enforce($ip, 'user_search', 30, 60);

    $q = Auth::sanitizeString($_GET['q'] ?? '', 50);
    if (mb_strlen($q) < 2) { respond(200, true, 'Query too short.', ['users' => []]); return; }

    // Escape ILIKE wildcards in the user-supplied query so '%'/'_' in a
    // search term aren't interpreted as pattern metacharacters.
    $escaped = str_replace(['\\', '%', '_'], ['\\\\', '\\%', '\\_'], $q);

    $stmt = $db->prepare(
        "SELECT id, username, avatar_url FROM users
         WHERE username ILIKE ? ESCAPE '\\' AND id != ? AND is_active = TRUE
         ORDER BY username LIMIT 10"
    );
    $stmt->execute(['%' . $escaped . '%', $userId]);
    $users = $stmt->fetchAll();

    respond(200, true, 'Users found.', ['users' => $users]);
}

// ── PUT /user/profile ─────────────────────────────────────────────────────────
function handleUpdateProfile(PDO $db): void {
    $claims  = Auth::requireAuth();
    $userId  = (int)$claims['sub'];
    $body    = Auth::getJsonBody();
    $updates = [];
    $params  = [];

    if (isset($body['username'])) {
        $username = Auth::sanitizeString($body['username'], 50);
        if (strlen($username) < 3) {
            respond(422, false, 'Username too short.'); return;
        }
        if (!preg_match('/^[a-zA-Z0-9_.-]+$/', $username)) {
            respond(422, false, 'Username contains invalid characters.'); return;
        }
        // Check not taken
        $chk = $db->prepare('SELECT id FROM users WHERE username=? AND id!=?');
        $chk->execute([$username, $userId]);
        if ($chk->fetch()) { respond(409, false, 'Username already taken.'); return; }
        $updates[] = 'username=?'; $params[] = $username;
    }

    if (isset($body['fcm_token'])) {
        $token = Auth::sanitizeString($body['fcm_token'], 500);
        $updates[] = 'fcm_token=?'; $params[] = $token;
    }

    // Client PUTs these two fields from the quiz-preferences screen, but
    // they were never in this whitelist — the DB columns exist (migration
    // 004) and the request itself "succeeds" with 422 "Nothing to update"
    // being silently ignored client-side, so the setting only ever lived in
    // local SharedPreferences and never synced across devices/reinstalls.
    // The client's "Relaxed" preset sends {timed_mode: false, seconds_per_q:
    // 0} — 0 is just a placeholder for "timer off" and would violate the
    // column's BETWEEN 5 AND 60 check, so skip writing seconds_per_q
    // whenever this same request is turning timed mode off.
    $timedModeVal = isset($body['quiz_timed_mode']) ? (bool)$body['quiz_timed_mode'] : null;
    if (isset($body['quiz_timed_mode'])) {
        $updates[] = 'quiz_timed_mode=?';
        $params[]  = $timedModeVal ? 'true' : 'false';
    }
    if (isset($body['quiz_seconds_per_q']) && $timedModeVal !== false) {
        $secs = (int)$body['quiz_seconds_per_q'];
        if ($secs < 5 || $secs > 60) { respond(422, false, 'Seconds per question must be 5–60.'); return; }
        $updates[] = 'quiz_seconds_per_q=?';
        $params[]  = $secs;
    }

    if (empty($updates)) { respond(422, false, 'Nothing to update.'); return; }

    $params[] = $userId;
    $sql = 'UPDATE users SET ' . implode(', ', $updates) . ' WHERE id=?';
    $db->prepare($sql)->execute($params);

    respond(200, true, 'Profile updated.');
}

function respond(int $code, bool $success, string $message, array $data = []): void {
    http_response_code($code);
    echo json_encode(array_merge(
        ['success' => $success, 'message' => $message],
        $data
    ), JSON_UNESCAPED_UNICODE);
}
