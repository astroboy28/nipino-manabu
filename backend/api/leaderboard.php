<?php
// backend/api/leaderboard.php
declare(strict_types=1);

require_once dirname(__DIR__) . '/config/Database.php';
require_once dirname(__DIR__) . '/middleware/Auth.php';

Auth::securityHeaders();
$db     = Database::connect();
$method = $_SERVER['REQUEST_METHOD'];
$action = $_GET['action'] ?? '';

match (true) {
    $method === 'GET' && $action === 'list' => handleList($db),
    default => respond(404, false, 'Endpoint not found'),
};

function handleList(PDO $db): void {
    $claims  = Auth::requireAuth();
    $userId  = (int)$claims['sub'];
    $period  = in_array($_GET['period'] ?? '', ['weekly','alltime'], true)
               ? $_GET['period'] : 'weekly';
    $level   = isset($_GET['level']) && in_array($_GET['level'],
               ['N1','N2','N3','N4','N5'], true)
               ? $_GET['level'] : null;
    $limit   = min((int)($_GET['limit'] ?? 50), 100);

    if ($level) {
        $stmt = $db->prepare(
            'SELECT ls.rank_pos AS rank, ls.user_id, u.username,
                    u.current_level AS level, ls.total_score,
                    u.streak_days, ls.accuracy,
                    (ls.user_id = ?) AS is_current_user
             FROM leaderboard_snapshots ls
             JOIN users u ON u.id = ls.user_id
             WHERE ls.period=? AND ls.level=?
             ORDER BY ls.rank_pos ASC
             LIMIT ?'
        );
        // Params must match placeholder POSITION in the SQL text, not the
        // order they're declared above: (user_id=?) comes first, then
        // period, then level, then LIMIT. This was previously
        // [$period,$limit,$userId,$level] — completely scrambled, binding
        // $period (a string like "weekly") to the user_id=? integer
        // comparison. That's a hard Postgres type error, so this branch
        // fatally crashed (500) on every real request — confirmed live in
        // production error logs pre-dating this fix.
        $stmt->execute([$userId, $period, $level, $limit]);
    } else {
        $stmt = $db->prepare(
            'SELECT ls.rank_pos AS rank, ls.user_id, u.username,
                    u.current_level AS level, ls.total_score,
                    u.streak_days, ls.accuracy,
                    (ls.user_id = ?) AS is_current_user
             FROM leaderboard_snapshots ls
             JOIN users u ON u.id = ls.user_id
             WHERE ls.period=? AND ls.level IS NULL
             ORDER BY ls.rank_pos ASC
             LIMIT ?'
        );
        // Same fix as the branch above — (user_id=?), then period, then LIMIT.
        $stmt->execute([$userId, $period, $limit]);
    }

    $entries = $stmt->fetchAll();

    // Ensure current user appears even if outside top N
    $userInList = array_filter($entries, fn($e) => (int)$e['user_id'] === $userId);
    if (empty($userInList)) {
        $mySql = $level
            ? 'SELECT rank_pos AS rank, user_id, ? AS level, total_score, accuracy
               FROM leaderboard_snapshots WHERE period=? AND level=? AND user_id=?'
            : 'SELECT rank_pos AS rank, user_id, NULL AS level, total_score, accuracy
               FROM leaderboard_snapshots WHERE period=? AND level IS NULL AND user_id=?';
        // The level branch has 4 placeholders in order: "? AS level",
        // period=?, level=?, user_id=? — this previously passed only 3
        // params, so PDO threw "Invalid parameter number" on every
        // fallback lookup (a user checking the leaderboard while ranked
        // outside the top N).
        $myParams = $level ? [$level, $period, $level, $userId] : [$period, $userId];
        $myStmt = $db->prepare($mySql);
        $myStmt->execute($myParams);
        $myRow = $myStmt->fetch();
        if ($myRow) {
            $myRow['username']        = $claims['username'];
            $myRow['streak_days']     = 0;
            $myRow['is_current_user'] = true;
            $entries[]                = $myRow;
        }
    }

    $entries = array_map(function (array $e): array {
        $e['rank']        = (int)$e['rank'];
        $e['total_score'] = (int)$e['total_score'];
        $e['streak_days'] = (int)$e['streak_days'];
        $e['accuracy']    = round((float)$e['accuracy'], 1);
        $e['is_current_user'] = (bool)$e['is_current_user'];
        return $e;
    }, $entries);

    respond(200, true, 'Leaderboard fetched.', ['entries' => $entries]);
}

function respond(int $code, bool $success, string $message, array $data = []): void {
    http_response_code($code);
    echo json_encode(array_merge(['success' => $success, 'message' => $message], $data),
        JSON_UNESCAPED_UNICODE);
}
