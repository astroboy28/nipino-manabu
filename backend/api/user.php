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
    default => respond(404, false, 'Endpoint not found'),
};

// ── GET /user/profile ─────────────────────────────────────────────────────────
function handleProfile(PDO $db): void {
    $claims = Auth::requireAuth();
    $userId = (int)$claims['sub'];

    $stmt = $db->prepare(
        'SELECT id, uuid, username, email, coins, streak_days,
                current_level, total_score, avatar_url, created_at
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
