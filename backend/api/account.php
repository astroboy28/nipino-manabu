<?php
// backend/api/account.php
// ─── Account deletion + GDPR data export ─────────────────────────────────────
declare(strict_types=1);

require_once dirname(__DIR__) . '/config/Database.php';
require_once dirname(__DIR__) . '/middleware/Auth.php';
require_once dirname(__DIR__) . '/redis/RateLimiter.php';
require_once dirname(__DIR__) . '/email/Mailer.php';
require_once dirname(__DIR__) . '/middleware/Monitor.php';

Auth::securityHeaders();
Monitor::register();

$db     = Database::connect();
$method = $_SERVER['REQUEST_METHOD'];
$action = $_GET['action'] ?? '';
$ip     = $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';

if (RateLimiter::isBlacklisted($ip)) {
    http_response_code(403);
    echo json_encode(['success' => false, 'message' => 'Access denied.']);
    exit;
}

match (true) {
    $method === 'POST'   && $action === 'request-deletion'  => handleRequestDeletion($db, $ip),
    $method === 'POST'   && $action === 'confirm-deletion'  => handleConfirmDeletion($db),
    $method === 'DELETE' && $action === 'cancel-deletion'   => handleCancelDeletion($db),
    // Unauthenticated — reached from the emailed "Cancel Deletion" link,
    // which by definition must work even when the session that requested
    // deletion has long since expired (see migration 012).
    $method === 'POST'   && $action === 'confirm-cancel-deletion' => handleConfirmCancelDeletion($db, $ip),
    $method === 'GET'    && $action === 'export'            => handleExport($db),
    default => respond(404, false, 'Endpoint not found'),
};

// ════════════════════════════════════════════════════════════════════════════
// REQUEST DELETION  — schedules deletion 30 days out, sends confirmation email
// POST /v1/account/request-deletion
// ════════════════════════════════════════════════════════════════════════════
function handleRequestDeletion(PDO $db, string $ip): void {
    $claims = Auth::requireAuth();
    $userId = (int) $claims['sub'];
    RateLimiter::enforce($ip, 'request_deletion', 3, 3600);

    $body     = Auth::getJsonBody();
    $password = $body['password'] ?? '';

    // Require password confirmation before scheduling deletion
    $stmt = $db->prepare(
        'SELECT id, email, username, password_hash
         FROM users WHERE id = ? AND is_active = TRUE'
    );
    $stmt->execute([$userId]);
    $user = $stmt->fetch();

    if (!$user) {
        respond(404, false, 'User not found.'); return;
    }
    if (!Auth::verifyPassword($password, $user['password_hash'])) {
        respond(401, false, 'Incorrect password. Deletion not scheduled.'); return;
    }

    // Check not already scheduled
    $chk = $db->prepare(
        'SELECT deletion_scheduled_at FROM users
         WHERE id = ? AND deletion_scheduled_at IS NOT NULL'
    );
    $chk->execute([$userId]);
    if ($chk->fetch()) {
        respond(409, false,
            'Account deletion is already scheduled. '
          . 'Use /account/cancel-deletion to undo.'); return;
    }

    // Schedule deletion 30 days from now (as per Privacy Policy)
    $deleteAt = date('Y-m-d H:i:s', strtotime('+30 days'));
    $db->prepare(
        'UPDATE users
         SET deletion_scheduled_at = ?,
             is_active             = FALSE   -- immediately prevents login
         WHERE id = ?'
    )->execute([$deleteAt, $userId]);

    // Revoke all sessions immediately
    $db->prepare(
        'UPDATE refresh_tokens
         SET revoked_at = NOW()
         WHERE user_id = ? AND revoked_at IS NULL'
    )->execute([$userId]);

    // Token-based cancel link, valid the full 30-day grace period —
    // is_active=FALSE above blocks login/refresh immediately, so the
    // already-live access token (15 min TTL) is otherwise the only way
    // back in. Same pattern as password_reset_tokens.
    $cancelToken = bin2hex(random_bytes(32));
    $db->prepare(
        "INSERT INTO deletion_cancel_tokens (user_id, token_hash, expires_at)
         VALUES (?, ?, ?)"
    )->execute([$userId, hash('sha256', $cancelToken), $deleteAt]);

    // Email confirmation with cancel link
    Mailer::sendDeletionScheduled(
        $user['email'],
        $user['username'],
        $deleteAt,
        $cancelToken
    );

    Monitor::info('account_deletion', 'Deletion scheduled', [
        'user_id' => $userId,
        'delete_at' => $deleteAt,
    ], $userId);

    respond(200, true,
        'Account deletion scheduled. Your data will be permanently deleted '
      . 'in 30 days. Check your email for details.',
        ['deletion_date' => $deleteAt]);
}

// ════════════════════════════════════════════════════════════════════════════
// CONFIRM / IMMEDIATE DELETION
// POST /v1/account/confirm-deletion   (admin or user within grace period)
// ════════════════════════════════════════════════════════════════════════════
function handleConfirmDeletion(PDO $db): void {
    $claims = Auth::requireAuth();
    $callerId = (int) $claims['sub'];

    $callerStmt = $db->prepare('SELECT is_admin FROM users WHERE id = ?');
    $callerStmt->execute([$callerId]);
    $caller = $callerStmt->fetch();
    $isAdmin = (bool) ($caller['is_admin'] ?? false);

    $body   = Auth::getJsonBody();
    $userId = $isAdmin && isset($body['user_id']) ? (int) $body['user_id'] : $callerId;

    if ($isAdmin) {
        // Admin-triggered immediate deletion (e.g. compliance request) —
        // doesn't require the target's password, but does require the
        // deletion to have actually been requested first.
        $stmt = $db->prepare(
            'SELECT id FROM users WHERE id = ? AND deletion_scheduled_at IS NOT NULL'
        );
        $stmt->execute([$userId]);
        if (!$stmt->fetch()) {
            respond(409, false, 'No deletion request is scheduled for this account.'); return;
        }
    } else {
        // Self-service: caller must already be within the grace period
        // (i.e. actually called request-deletion) AND re-confirm their
        // password, so a bare stolen/leaked access token alone can't nuke
        // the account instantly with no grace period.
        $password = (string) ($body['password'] ?? '');
        $stmt = $db->prepare(
            'SELECT password_hash FROM users
             WHERE id = ? AND deletion_scheduled_at IS NOT NULL'
        );
        $stmt->execute([$userId]);
        $user = $stmt->fetch();
        if (!$user) {
            respond(409, false,
                'No deletion request is scheduled. Call /account/request-deletion first.'); return;
        }
        if (!$password || !Auth::verifyPassword($password, $user['password_hash'])) {
            respond(401, false, 'Incorrect password. Deletion not confirmed.'); return;
        }
    }

    // Hard delete — cascade removes all related rows via FK ON DELETE CASCADE
    $db->beginTransaction();
    try {
        // 1. Anonymise quiz_results (keep for aggregate stats, remove PII)
        $db->prepare(
            'UPDATE quiz_results SET user_id = NULL
             WHERE user_id = ?'
        )->execute([$userId]);

        // 2. Delete all user-linked data (FK cascade handles most)
        $db->prepare('DELETE FROM user_badges         WHERE user_id = ?')->execute([$userId]);
        $db->prepare('DELETE FROM user_level_progress WHERE user_id = ?')->execute([$userId]);
        $db->prepare('DELETE FROM refresh_tokens      WHERE user_id = ?')->execute([$userId]);
        $db->prepare('DELETE FROM password_reset_tokens WHERE user_id = ?')->execute([$userId]);
        $db->prepare('DELETE FROM leaderboard_snapshots WHERE user_id = ?')->execute([$userId]);
        $db->prepare('DELETE FROM notification_log    WHERE user_id = ?')->execute([$userId]);
        $db->prepare('DELETE FROM iap_purchases       WHERE user_id = ?')->execute([$userId]);

        // 3. GDPR-compliant anonymisation of error_log (keep for security audit, remove identity)
        $db->prepare(
            'UPDATE error_log SET user_id = NULL, ip_address = NULL
             WHERE user_id = ?'
        )->execute([$userId]);

        // 4. Delete the user record itself
        $db->prepare('DELETE FROM users WHERE id = ?')->execute([$userId]);

        $db->commit();
    } catch (\Exception $e) {
        $db->rollBack();
        Monitor::error('account_deletion', 'Hard delete failed: ' . $e->getMessage(),
            [], $userId);
        respond(500, false, 'Deletion failed. Our team has been notified.'); return;
    }

    Monitor::info('account_deletion', 'Account hard-deleted', ['user_id' => $userId]);
    respond(200, true, 'Your account and all associated data have been permanently deleted.');
}

// ════════════════════════════════════════════════════════════════════════════
// CANCEL DELETION — while within 30-day grace period
// DELETE /v1/account/cancel-deletion
// ════════════════════════════════════════════════════════════════════════════
function handleCancelDeletion(PDO $db): void {
    $claims = Auth::requireAuth();
    $userId = (int) $claims['sub'];

    $stmt = $db->prepare(
        'UPDATE users
         SET deletion_scheduled_at = NULL,
             is_active             = TRUE
         WHERE id = ?
           AND deletion_scheduled_at IS NOT NULL
         RETURNING email, username'
    );
    $stmt->execute([$userId]);
    $user = $stmt->fetch();

    if (!$user) {
        respond(404, false, 'No pending deletion found for this account.'); return;
    }

    // Invalidate any outstanding emailed cancel token — this session-based
    // path already did the job it would have done.
    $db->prepare('UPDATE deletion_cancel_tokens SET used=TRUE WHERE user_id=? AND used=FALSE')
       ->execute([$userId]);

    // Notify by email that deletion was cancelled
    Mailer::sendDeletionCancelled($user['email'], $user['username']);

    Monitor::info('account_deletion', 'Deletion cancelled', [], $userId);
    respond(200, true,
        'Account deletion cancelled. Your account has been fully restored.');
}

// ════════════════════════════════════════════════════════════════════════════
// CONFIRM CANCEL DELETION (via emailed token) — no session required
// POST /v1/account/confirm-cancel-deletion  { "token": "..." }
// ════════════════════════════════════════════════════════════════════════════
function handleConfirmCancelDeletion(PDO $db, string $ip): void {
    RateLimiter::enforce($ip, 'confirm_cancel_deletion', 10, 3600);

    $body  = Auth::getJsonBody();
    $token = (string) ($body['token'] ?? '');
    if (!$token) { respond(422, false, 'Token required.'); return; }

    $tokHash = hash('sha256', $token);
    $stmt = $db->prepare(
        'SELECT dct.id, dct.user_id, u.email, u.username
         FROM deletion_cancel_tokens dct
         JOIN users u ON u.id = dct.user_id
         WHERE dct.token_hash = ? AND dct.expires_at > NOW() AND dct.used = FALSE
         LIMIT 1'
    );
    $stmt->execute([$tokHash]);
    $row = $stmt->fetch();
    if (!$row) { respond(400, false, 'Link invalid or expired.'); return; }

    $db->beginTransaction();
    try {
        $db->prepare(
            'UPDATE users
             SET deletion_scheduled_at = NULL,
                 is_active             = TRUE
             WHERE id = ? AND deletion_scheduled_at IS NOT NULL'
        )->execute([$row['user_id']]);

        $db->prepare('UPDATE deletion_cancel_tokens SET used=TRUE WHERE id=?')
           ->execute([$row['id']]);

        $db->commit();
    } catch (\Exception $e) {
        $db->rollBack();
        Monitor::error('account_deletion', 'Token cancel failed: ' . $e->getMessage(),
            [], $row['user_id']);
        respond(500, false, 'Cancellation failed. Try again.'); return;
    }

    Mailer::sendDeletionCancelled($row['email'], $row['username']);

    Monitor::info('account_deletion', 'Deletion cancelled via emailed token', [], $row['user_id']);
    respond(200, true,
        'Account deletion cancelled. Your account has been fully restored — sign in normally.');
}

// ════════════════════════════════════════════════════════════════════════════
// GDPR DATA EXPORT — structured JSON of everything we hold
// GET /v1/account/export
// ════════════════════════════════════════════════════════════════════════════
function handleExport(PDO $db): void {
    $claims = Auth::requireAuth();
    $userId = (int) $claims['sub'];
    $ip     = $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';
    RateLimiter::enforce($ip, 'data_export', 3, 86400); // 3 exports per day

    // ── Collect all user data ─────────────────────────────────────────────────
    // 1. Profile
    $profStmt = $db->prepare(
        'SELECT id, username, email, coins, streak_days, current_level,
                total_score, is_verified, created_at, updated_at
         FROM users WHERE id = ?'
    );
    $profStmt->execute([$userId]);
    $profile = $profStmt->fetch();

    // 2. Level progress
    $progStmt = $db->prepare(
        'SELECT level, completed_topics, total_topics, exam_unlocked, updated_at
         FROM user_level_progress WHERE user_id = ? ORDER BY level'
    );
    $progStmt->execute([$userId]);
    $progress = $progStmt->fetchAll();

    // 3. Quiz history (last 1000 results)
    $histStmt = $db->prepare(
        'SELECT level, category, correct_count, total_count,
                score_percent, time_taken_seconds, coins_earned, taken_at
         FROM quiz_results WHERE user_id = ?
         ORDER BY taken_at DESC LIMIT 1000'
    );
    $histStmt->execute([$userId]);
    $history = $histStmt->fetchAll();

    // 4. Badges earned
    $badgeStmt = $db->prepare(
        'SELECT b.name, b.description, b.icon_emoji, ub.earned_at
         FROM user_badges ub JOIN badges b ON b.id = ub.badge_id
         WHERE ub.user_id = ? ORDER BY ub.earned_at'
    );
    $badgeStmt->execute([$userId]);
    $badges = $badgeStmt->fetchAll();

    // 5. Purchase history (hashed receipts only — no raw payment data)
    $iapStmt = $db->prepare(
        'SELECT product_id, platform, coins_granted, verified_at
         FROM iap_purchases WHERE user_id = ? ORDER BY verified_at'
    );
    $iapStmt->execute([$userId]);
    $purchases = $iapStmt->fetchAll();

    // 6. Notifications sent
    $notifStmt = $db->prepare(
        'SELECT type, title, body, sent_at
         FROM notification_log WHERE user_id = ?
         ORDER BY sent_at DESC LIMIT 200'
    );
    $notifStmt->execute([$userId]);
    $notifications = $notifStmt->fetchAll();

    // ── Build export package ──────────────────────────────────────────────────
    $export = [
        'export_info' => [
            'generated_at'   => date('c'),
            'user_id'        => $userId,
            'data_controller' => 'Nipino-Manabu',
            'contact'        => 'privacy@nipino-manabu.com',
            'format'         => 'JSON',
            'gdpr_article'   => 'Article 20 — Right to data portability',
        ],
        'profile'       => $profile,
        'level_progress' => $progress,
        'quiz_history'  => $history,
        'badges_earned' => $badges,
        'purchases'     => $purchases,
        'notifications' => $notifications,
        'data_categories' => [
            'profile'      => 'Username, email, learning level, coins, streak',
            'quiz_results' => 'Quiz scores, time taken, coins earned per session',
            'progress'     => 'Topic completion per JLPT level',
            'purchases'    => 'IAP product IDs and coin grants (no card data)',
        ],
        'retention_policy' =>
            'Data retained while account is active. '
          . 'Deleted within 30 days of account deletion request.',
    ];

    // Log the export request
    Monitor::info('gdpr_export', 'Data export generated', [], $userId);
    $db->prepare('INSERT INTO gdpr_export_log (user_id, ip_address) VALUES (?,?)')
       ->execute([$userId, $ip]);

    // Set download headers so client can save as file
    header('Content-Type: application/json; charset=utf-8');
    header('Content-Disposition: attachment; filename="nipino_manabu_data_export_' .
        date('Ymd_His') . '.json"');
    http_response_code(200);
    echo json_encode($export, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);
}

function respond(int $code, bool $ok, string $msg, array $data = []): void {
    http_response_code($code);
    echo json_encode(
        array_merge(['success' => $ok, 'message' => $msg], $data),
        JSON_UNESCAPED_UNICODE
    );
}
