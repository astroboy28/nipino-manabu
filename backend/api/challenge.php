<?php
// backend/api/challenge.php
// ─── Admin challenge events: timed quizzes, prize coins, home-screen feature ─
declare(strict_types=1);

require_once dirname(__DIR__) . '/config/Database.php';
require_once dirname(__DIR__) . '/middleware/Auth.php';
require_once dirname(__DIR__) . '/redis/RateLimiter.php';
require_once dirname(__DIR__) . '/middleware/Monitor.php';
require_once dirname(__DIR__) . '/email/FCM.php';

Auth::securityHeaders();
Monitor::register();

$db     = Database::connect();
$method = $_SERVER['REQUEST_METHOD'];
$action = $_GET['action'] ?? '';

match (true) {
    // Admin-only
    $method === 'POST' && $action === 'create'           => handleCreate($db),
    $method === 'POST' && $action === 'invite-all'       => handleInviteAll($db),
    $method === 'POST' && $action === 'invite-user'      => handleInviteUser($db),
    $method === 'POST' && $action === 'finalize'         => handleAdminFinalize($db),
    $method === 'PUT'  && $action === 'update'           => handleUpdate($db),
    // Public
    $method === 'GET'  && $action === 'list'             => handleList($db),
    $method === 'GET'  && $action === 'get'              => handleGet($db),
    $method === 'GET'  && $action === 'featured'         => handleFeatured($db),
    $method === 'GET'  && $action === 'leaderboard'      => handleChallengeLeaderboard($db),
    // User
    $method === 'POST' && $action === 'join'             => handleJoin($db),
    $method === 'POST' && $action === 'submit-result'    => handleSubmitResult($db),
    default => respond(404, false, 'Endpoint not found'),
};

// ── Admin guard ───────────────────────────────────────────────────────────────
function requireAdmin(PDO $db): array {
    $claims = Auth::requireAuth();
    $userId = (int) $claims['sub'];
    // Check is_admin flag (add this column: ALTER TABLE users ADD COLUMN is_admin BOOLEAN DEFAULT FALSE)
    $stmt = $db->prepare('SELECT is_admin FROM users WHERE id=?');
    $stmt->execute([$userId]);
    $user = $stmt->fetch();
    if (!$user || !$user['is_admin']) {
        respond(403, false, 'Admin access required.');
        exit;
    }
    return $claims;
}

// ════════════════════════════════════════════════════════════════════════════
// ADMIN: CREATE CHALLENGE EVENT
// ════════════════════════════════════════════════════════════════════════════
function handleCreate(PDO $db): void {
    $claims = requireAdmin($db);
    $userId = (int) $claims['sub'];
    $body   = Auth::getJsonBody();

    $title       = Auth::sanitizeString($body['title']       ?? '', 200);
    $description = Auth::sanitizeString($body['description'] ?? '', 2000);
    $level       = Auth::sanitizeString($body['level']       ?? '', 2);
    $category    = Auth::sanitizeString($body['category']    ?? '', 20);
    $prizeCoins  = (int)($body['prize_coins']     ?? 0);
    $secsPerQ    = (int)($body['seconds_per_q']   ?? 20);
    $questionCnt = (int)($body['question_count']  ?? 15);
    $maxPart     = (int)($body['max_participants']?? 100);
    $featured    = (bool)($body['featured']       ?? false);
    $startsAt    = Auth::sanitizeString($body['starts_at']   ?? '', 30);
    $endsAt      = Auth::sanitizeString($body['ends_at']     ?? '', 30);
    $badgeName   = Auth::sanitizeString($body['prize_badge_name']  ?? '', 100);
    $badgeEmoji  = Auth::sanitizeString($body['prize_badge_emoji'] ?? '', 10);

    $validLevels = ['N1','N2','N3','N4','N5'];
    $validCats   = ['kanji','vocabulary','grammar','listening'];
    if (!$title)                               { respond(422, false, 'Title required.'); return; }
    if (!in_array($level, $validLevels, true)) { respond(422, false, 'Invalid level.'); return; }
    if (!in_array($category, $validCats, true)){ respond(422, false, 'Invalid category.'); return; }
    if ($prizeCoins <= 0)                      { respond(422, false, 'Prize coins must be > 0.'); return; }
    if ($secsPerQ < 5 || $secsPerQ > 60)       { respond(422, false, 'Seconds per question: 5–60.'); return; }
    if (!$startsAt || !$endsAt)                { respond(422, false, 'starts_at and ends_at required.'); return; }
    if (strtotime($endsAt) <= strtotime($startsAt)) { respond(422, false, 'ends_at must be after starts_at.'); return; }

    $questionCnt = max(5, min(30, $questionCnt));

    $stmt = $db->prepare(
        'INSERT INTO challenge_events
         (title, description, created_by_id, level, category,
          question_count, seconds_per_q, prize_coins, prize_badge_name,
          prize_badge_emoji, featured, max_participants, starts_at, ends_at)
         VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
         RETURNING id, uuid'
    );
    $stmt->execute([
        $title, $description, $userId, $level, $category,
        $questionCnt, $secsPerQ, $prizeCoins,
        $badgeName ?: null, $badgeEmoji ?: null,
        $featured ? 'true' : 'false', $maxPart, $startsAt, $endsAt,
    ]);
    $event = $stmt->fetch();

    Monitor::info('challenge_create', "Challenge created: $title", ['event_id' => $event['id']], $userId);
    respond(201, true, 'Challenge created.', ['event_id' => $event['id'], 'uuid' => $event['uuid']]);
}

// ════════════════════════════════════════════════════════════════════════════
// ADMIN: INVITE ALL USERS (mass push notification)
// ════════════════════════════════════════════════════════════════════════════
function handleInviteAll(PDO $db): void {
    $claims  = requireAdmin($db);
    $ip      = $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';
    // Mass-notifies up to 10,000 users per call — cap how often that can
    // be triggered (repeat/compromised-admin protection), separate from
    // the per-user invite limit on handleInviteUser.
    RateLimiter::enforce($ip, 'challenge_invite_all', 5, 3600);
    $body    = Auth::getJsonBody();
    $eventId = (int)($body['event_id'] ?? 0);

    $evtStmt = $db->prepare('SELECT id, title, prize_coins, starts_at FROM challenge_events WHERE id=?');
    $evtStmt->execute([$eventId]);
    $event = $evtStmt->fetch();
    if (!$event) { respond(404, false, 'Challenge not found.'); return; }

    // Fetch all active users with FCM tokens
    $usersStmt = $db->prepare(
        'SELECT id, fcm_token FROM users WHERE is_active=TRUE AND fcm_token IS NOT NULL LIMIT 10000'
    );
    $usersStmt->execute();
    $users = $usersStmt->fetchAll();

    $sent = 0; $failed = 0;
    $title  = "🏆 New challenge: {$event['title']}";
    $body_t = "Prize: {$event['prize_coins']} coins. Tap to join!";

    foreach ($users as $u) {
        $ok = FCM::sendToToken($u['fcm_token'], $title, $body_t, [
            'type'     => 'challenge_invite',
            'event_id' => (string)$eventId,
            'screen'   => 'challenge',
        ]);
        if ($ok) $sent++; else $failed++;
    }

    // Bulk create invitations
    if (!empty($users)) {
        $invStmt = $db->prepare(
            "INSERT INTO invitations (type, from_user_id, to_user_id, reference_id, message)
             VALUES ('challenge', NULL, ?, ?, 'Admin challenge invitation')
             ON CONFLICT DO NOTHING"
        );
        foreach ($users as $u) {
            $invStmt->execute([$u['id'], $eventId]);
        }
    }

    respond(200, true, "Notified {$sent} users ({$failed} failed).",
        ['sent' => $sent, 'failed' => $failed]);
}

// ════════════════════════════════════════════════════════════════════════════
// ADMIN: INVITE SPECIFIC USER
// ════════════════════════════════════════════════════════════════════════════
function handleInviteUser(PDO $db): void {
    $claims     = requireAdmin($db);
    $ip         = $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';
    RateLimiter::enforce($ip, 'challenge_invite_user', 30, 3600);
    $body       = Auth::getJsonBody();
    $eventId    = (int)($body['event_id']   ?? 0);
    $inviteeId  = (int)($body['user_id']    ?? 0);
    $message    = Auth::sanitizeString($body['message'] ?? 'You have been selected for a challenge!', 200);

    $evtStmt = $db->prepare('SELECT title, prize_coins FROM challenge_events WHERE id=?');
    $evtStmt->execute([$eventId]);
    $event = $evtStmt->fetch();
    if (!$event) { respond(404, false, 'Challenge not found.'); return; }

    $uStmt = $db->prepare('SELECT id, username, fcm_token FROM users WHERE id=? AND is_active=TRUE');
    $uStmt->execute([$inviteeId]);
    $user = $uStmt->fetch();
    if (!$user) { respond(404, false, 'User not found.'); return; }

    $db->prepare(
        "INSERT INTO invitations (type, from_user_id, to_user_id, reference_id, message)
         VALUES ('challenge', NULL, ?, ?, ?)
         ON CONFLICT DO NOTHING"
    )->execute([$inviteeId, $eventId, $message]);

    if ($user['fcm_token']) {
        FCM::sendToToken($user['fcm_token'],
            "🏆 You're invited: {$event['title']}",
            "{$message} Prize: {$event['prize_coins']} coins.",
            ['type' => 'challenge_invite', 'event_id' => (string)$eventId, 'screen' => 'challenge']
        );
    }

    respond(200, true, "Invitation sent to {$user['username']}.");
}

// ════════════════════════════════════════════════════════════════════════════
// USER: JOIN CHALLENGE
// ════════════════════════════════════════════════════════════════════════════
function handleJoin(PDO $db): void {
    $claims  = Auth::requireAuth();
    $userId  = (int) $claims['sub'];
    $body    = Auth::getJsonBody();
    $eventId = (int)($body['event_id'] ?? 0);

    $evtStmt = $db->prepare(
        "SELECT id, status, max_participants, starts_at, ends_at,
           (SELECT COUNT(*) FROM challenge_participants WHERE event_id=ce.id) AS joined
         FROM challenge_events ce WHERE id=?"
    );
    $evtStmt->execute([$eventId]);
    $event = $evtStmt->fetch();

    if (!$event)                              { respond(404, false, 'Challenge not found.'); return; }
    if (!in_array($event['status'], ['upcoming','active'], true))
                                              { respond(409, false, 'Challenge is not accepting participants.'); return; }
    if ((int)$event['joined'] >= (int)$event['max_participants'])
                                              { respond(409, false, 'Challenge is full.'); return; }
    if (strtotime($event['ends_at']) < time()) { respond(410, false, 'Challenge has ended.'); return; }

    $db->beginTransaction();
    try {
        // Lock the event row so concurrent joins serialize instead of both
        // reading the same stale "joined < max_participants" snapshot — same
        // race class as duel_rooms joins (see duel.php handleJoin): without
        // this, joiners racing for the last slot(s) could overfill the event.
        $lockStmt = $db->prepare(
            'SELECT ce.max_participants,
               (SELECT COUNT(*) FROM challenge_participants WHERE event_id=ce.id) AS joined
             FROM challenge_events ce WHERE ce.id=? FOR UPDATE'
        );
        $lockStmt->execute([$eventId]);
        $locked = $lockStmt->fetch();
        if (!$locked || (int)$locked['joined'] >= (int)$locked['max_participants']) {
            $db->rollBack();
            respond(409, false, 'Challenge is full.'); return;
        }

        $db->prepare(
            'INSERT INTO challenge_participants (event_id, user_id) VALUES (?,?)
             ON CONFLICT DO NOTHING'
        )->execute([$eventId, $userId]);

        $db->commit();
    } catch (\Exception $e) {
        $db->rollBack();
        Monitor::error('challenge_join', $e->getMessage(), [], $userId);
        respond(500, false, 'Failed to join challenge.'); return;
    }

    respond(200, true, 'Joined challenge.', ['event_id' => $eventId]);
}

// ════════════════════════════════════════════════════════════════════════════
// USER: SUBMIT CHALLENGE QUIZ RESULT
// ════════════════════════════════════════════════════════════════════════════
function handleSubmitResult(PDO $db): void {
    $claims      = Auth::requireAuth();
    $userId      = (int) $claims['sub'];
    $body        = Auth::getJsonBody();
    $eventId     = (int)($body['event_id']      ?? 0);
    $timeTakenMs = (int)($body['time_taken_ms'] ?? 0);
    $rawAnswers  = is_array($body['answers'] ?? null) ? $body['answers'] : [];

    // Verify participant
    $partStmt = $db->prepare(
        'SELECT cp.id, cp.completed_at, ce.level, ce.prize_coins, ce.prize_badge_name,
                ce.prize_badge_emoji, ce.ends_at, ce.status
         FROM challenge_participants cp
         JOIN challenge_events ce ON ce.id=cp.event_id
         WHERE cp.event_id=? AND cp.user_id=?'
    );
    $partStmt->execute([$eventId, $userId]);
    $part = $partStmt->fetch();

    if (!$part)             { respond(403, false, 'You have not joined this challenge.'); return; }
    if ($part['completed_at']) { respond(409, false, 'You have already submitted results.'); return; }
    if ($part['status'] === 'finished') { respond(410, false, 'Challenge has already ended.'); return; }

    // Never trust a client-submitted score — re-derive correct_count
    // server-side from the real answer key, same fix as quiz.php. Dedupe by
    // question_id so a question can't be replayed to inflate the score.
    $byQuestion = [];
    foreach ($rawAnswers as $a) {
        if (!is_array($a) || !isset($a['question_id'])) continue;
        $qid = (int)$a['question_id'];
        if ($qid <= 0 || isset($byQuestion[$qid])) continue;
        $byQuestion[$qid] = isset($a['chosen_index']) && $a['chosen_index'] !== null
            ? (int)$a['chosen_index'] : null;
    }
    $totalCount = count($byQuestion);
    if ($totalCount < 1 || $totalCount > 50) { respond(422, false, 'Invalid result data.'); return; }

    $ids = array_keys($byQuestion);
    $placeholders = implode(',', array_fill(0, count($ids), '?'));
    $qStmt = $db->prepare("SELECT id, level, correct_index FROM quiz_questions WHERE id IN ($placeholders)");
    $qStmt->execute($ids);
    $realQuestions = $qStmt->fetchAll();
    if (count($realQuestions) !== $totalCount) { respond(422, false, 'Invalid question data.'); return; }

    $correctCount = 0;
    foreach ($realQuestions as $rq) {
        if ((string)$rq['level'] !== (string)$part['level']) {
            respond(422, false, 'Question/level mismatch.'); return;
        }
        $chosen = $byQuestion[(int)$rq['id']];
        if ($chosen !== null && $chosen === (int)$rq['correct_index']) $correctCount++;
    }

    $score = $correctCount * 10;

    $db->prepare(
        'UPDATE challenge_participants
         SET score=?, correct_count=?, time_taken_ms=?, completed_at=NOW()
         WHERE event_id=? AND user_id=?'
    )->execute([$score, $correctCount, $timeTakenMs, $eventId, $userId]);

    respond(200, true, 'Result submitted.', [
        'score'         => $score,
        'correct_count' => $correctCount,
    ]);
}

// ════════════════════════════════════════════════════════════════════════════
// ADMIN: FINALIZE CHALLENGE (award winner, feature on home screen)
// ════════════════════════════════════════════════════════════════════════════
function handleAdminFinalize(PDO $db): void {
    $claims  = requireAdmin($db);
    $body    = Auth::getJsonBody();
    $eventId = (int)($body['event_id'] ?? 0);

    $evtStmt = $db->prepare(
        'SELECT id, title, prize_coins, prize_badge_name, prize_badge_emoji, status
         FROM challenge_events WHERE id=?'
    );
    $evtStmt->execute([$eventId]);
    $event = $evtStmt->fetch();

    if (!$event || $event['status'] === 'finished') {
        respond(409, false, 'Challenge not found or already finalised.'); return;
    }

    // Find winner: highest score, then fastest time
    $winnerStmt = $db->prepare(
        'SELECT cp.user_id, u.username, u.fcm_token, cp.score, cp.correct_count, cp.time_taken_ms
         FROM challenge_participants cp
         JOIN users u ON u.id=cp.user_id
         WHERE cp.event_id=? AND cp.completed_at IS NOT NULL
         ORDER BY cp.score DESC, cp.time_taken_ms ASC
         LIMIT 1'
    );
    $winnerStmt->execute([$eventId]);
    $winner = $winnerStmt->fetch();

    if (!$winner) { respond(404, false, 'No completed submissions found.'); return; }

    $db->beginTransaction();
    try {
        // Award prize coins to winner
        $db->prepare('UPDATE users SET coins=coins+? WHERE id=?')
           ->execute([$event['prize_coins'], $winner['user_id']]);

        // Coin transaction record
        $balStmt = $db->prepare('SELECT coins FROM users WHERE id=?');
        $balStmt->execute([$winner['user_id']]);
        $newBal = (int)($balStmt->fetch()['coins'] ?? 0);
        $db->prepare(
            "INSERT INTO coin_transactions
             (user_id, amount, balance_after, type, reference_id, description)
             VALUES (?,?,?,'challenge_prize',?,?)"
        )->execute([
            $winner['user_id'], $event['prize_coins'], $newBal, $eventId,
            "Challenge winner: {$event['title']}",
        ]);

        // Award badge if configured
        if ($event['prize_badge_name']) {
            // Insert a one-off badge for this winner
            $badgeStmt = $db->prepare(
                "INSERT INTO badges (name, description, icon_emoji, condition)
                 VALUES (?, ?, ?, '{\"type\":\"manual\"}'::jsonb)
                 ON CONFLICT DO NOTHING RETURNING id"
            );
            $badgeStmt->execute([
                $event['prize_badge_name'],
                "Won the '{$event['title']}' challenge",
                $event['prize_badge_emoji'] ?? '🏆',
            ]);
            $badge = $badgeStmt->fetch();
            if ($badge) {
                $db->prepare(
                    'INSERT INTO user_badges (user_id, badge_id) VALUES (?,?) ON CONFLICT DO NOTHING'
                )->execute([$winner['user_id'], $badge['id']]);
            }
        }

        // Update ranks for all participants
        $rankStmt = $db->prepare(
            'SELECT user_id FROM challenge_participants
             WHERE event_id=? AND completed_at IS NOT NULL
             ORDER BY score DESC, time_taken_ms ASC'
        );
        $rankStmt->execute([$eventId]);
        $rankRows = $rankStmt->fetchAll();
        $updRank  = $db->prepare(
            'UPDATE challenge_participants SET rank_pos=?, coins_awarded=?
             WHERE event_id=? AND user_id=?'
        );
        foreach ($rankRows as $rank => $row) {
            $award = $rank === 0 ? (int)$event['prize_coins'] : 0;
            $updRank->execute([$rank + 1, $award, $eventId, $row['user_id']]);
        }

        // Mark event finished, set winner, feature on home screen
        $db->prepare(
            'UPDATE challenge_events
             SET status=\'finished\', winner_user_id=?, featured=TRUE, finished_at=NOW()
             WHERE id=?'
        )->execute([$winner['user_id'], $eventId]);

        $db->commit();
    } catch (\Exception $e) {
        $db->rollBack();
        Monitor::error('challenge_finalize', $e->getMessage(), [], null);
        respond(500, false, 'Finalization failed.'); return;
    }

    // Notify winner
    if ($winner['fcm_token']) {
        FCM::sendToToken(
            $winner['fcm_token'],
            "🏆 You won the {$event['title']} challenge!",
            "Congratulations! {$event['prize_coins']} coins have been added to your account.",
            ['type' => 'challenge_win', 'event_id' => (string)$eventId, 'screen' => 'challenge']
        );
    }

    respond(200, true, "Challenge finalised. Winner: {$winner['username']}.", [
        'winner'       => ['username' => $winner['username'], 'score' => $winner['score']],
        'prize_coins'  => $event['prize_coins'],
    ]);
}

// ════════════════════════════════════════════════════════════════════════════
// PUBLIC: LIST CHALLENGES
// ════════════════════════════════════════════════════════════════════════════
function handleList(PDO $db): void {
    $claims = Auth::requireAuth();
    $userId = (int) $claims['sub'];
    $status = Auth::sanitizeString($_GET['status'] ?? 'active', 20);
    $validStatuses = ['upcoming','active','finished'];
    if (!in_array($status, $validStatuses, true)) $status = 'active';

    // user_joined / user_completed were missing here (only handleGet had
    // them) — the app's list/detail screens never call handleGet, so
    // ChallengeEvent.userCompleted was always false client-side, letting a
    // user who already finished an active challenge "rejoin" and retake it.
    $stmt = $db->prepare(
        "SELECT ce.id, ce.uuid, ce.title, ce.description,
                ce.level, ce.category, ce.prize_coins,
                ce.prize_badge_emoji, ce.seconds_per_q, ce.question_count,
                ce.status, ce.featured, ce.starts_at, ce.ends_at,
                ce.max_participants,
                (SELECT COUNT(*) FROM challenge_participants WHERE event_id=ce.id) AS joined_count,
                wu.username AS winner_username,
                (SELECT id FROM challenge_participants WHERE event_id=ce.id AND user_id=?) AS user_joined,
                (SELECT completed_at IS NOT NULL FROM challenge_participants
                 WHERE event_id=ce.id AND user_id=? LIMIT 1) AS user_completed
         FROM challenge_events ce
         LEFT JOIN users wu ON wu.id=ce.winner_user_id
         WHERE ce.status=?
         ORDER BY ce.featured DESC, ce.starts_at ASC
         LIMIT 20"
    );
    $stmt->execute([$userId, $userId, $status]);
    $events = $stmt->fetchAll();
    respond(200, true, 'Challenges fetched.', ['events' => $events]);
}

// ════════════════════════════════════════════════════════════════════════════
// PUBLIC: GET FEATURED CHALLENGE (for home screen)
// ════════════════════════════════════════════════════════════════════════════
function handleFeatured(PDO $db): void {
    $claims = Auth::requireAuth();
    $userId = (int) $claims['sub'];
    $stmt = $db->prepare(
        "SELECT ce.id, ce.uuid, ce.title, ce.description,
                ce.level, ce.prize_coins, ce.prize_badge_emoji,
                ce.status, ce.starts_at, ce.ends_at,
                ce.seconds_per_q, ce.question_count,
                wu.username AS winner_username,
                wu.id AS winner_id,
                (SELECT id FROM challenge_participants WHERE event_id=ce.id AND user_id=?) AS user_joined,
                (SELECT completed_at IS NOT NULL FROM challenge_participants
                 WHERE event_id=ce.id AND user_id=? LIMIT 1) AS user_completed
         FROM challenge_events ce
         LEFT JOIN users wu ON wu.id=ce.winner_user_id
         WHERE ce.featured=TRUE
         ORDER BY
           CASE ce.status WHEN 'active' THEN 0 WHEN 'upcoming' THEN 1 ELSE 2 END,
           ce.starts_at DESC
         LIMIT 1"
    );
    $stmt->execute([$userId, $userId]);
    $event = $stmt->fetch();
    respond(200, true, 'Featured challenge fetched.',
        ['event' => $event ?: null]);
}

// ════════════════════════════════════════════════════════════════════════════
// PUBLIC: CHALLENGE LEADERBOARD
// ════════════════════════════════════════════════════════════════════════════
function handleChallengeLeaderboard(PDO $db): void {
    $claims  = Auth::requireAuth();
    $userId  = (int) $claims['sub'];
    $eventId = (int)($_GET['event_id'] ?? 0);
    if (!$eventId) { respond(422, false, 'event_id required.'); return; }

    $stmt = $db->prepare(
        'SELECT cp.rank_pos, cp.user_id, u.username, cp.score,
                cp.correct_count, cp.time_taken_ms, cp.coins_awarded,
                (cp.user_id=?) AS is_current_user
         FROM challenge_participants cp
         JOIN users u ON u.id=cp.user_id
         WHERE cp.event_id=? AND cp.completed_at IS NOT NULL
         ORDER BY cp.score DESC, cp.time_taken_ms ASC
         LIMIT 50'
    );
    $stmt->execute([$eventId, $userId]);
    $entries = $stmt->fetchAll();
    respond(200, true, 'Leaderboard fetched.', ['entries' => $entries]);
}

// ════════════════════════════════════════════════════════════════════════════
// GET SINGLE CHALLENGE
// ════════════════════════════════════════════════════════════════════════════
function handleGet(PDO $db): void {
    $claims  = Auth::requireAuth();
    $userId  = (int) $claims['sub'];
    $eventId = (int)($_GET['event_id'] ?? 0);
    if (!$eventId) { respond(422, false, 'event_id required.'); return; }

    $stmt = $db->prepare(
        'SELECT ce.*,
           (SELECT COUNT(*) FROM challenge_participants WHERE event_id=ce.id) AS joined_count,
           (SELECT completed_at IS NOT NULL FROM challenge_participants
            WHERE event_id=ce.id AND user_id=? LIMIT 1) AS user_completed,
           (SELECT id FROM challenge_participants WHERE event_id=ce.id AND user_id=?) AS user_joined
         FROM challenge_events ce WHERE ce.id=?'
    );
    $stmt->execute([$eventId, $userId]);
    $event = $stmt->fetch();
    if (!$event) { respond(404, false, 'Challenge not found.'); return; }
    respond(200, true, 'Challenge fetched.', ['event' => $event]);
}

// ════════════════════════════════════════════════════════════════════════════
// ADMIN: UPDATE CHALLENGE (toggle featured, update details)
// ════════════════════════════════════════════════════════════════════════════
function handleUpdate(PDO $db): void {
    requireAdmin($db);
    $body    = Auth::getJsonBody();
    $eventId = (int)($body['event_id'] ?? 0);
    $updates = [];
    $params  = [];
    $i       = 1;

    if (isset($body['featured'])) {
        $updates[] = "featured=\${$i}";
        $params[]  = (bool)$body['featured'] ? 'true' : 'false';
        $i++;
    }
    if (isset($body['title'])) {
        $updates[] = "title=\${$i}";
        $params[]  = Auth::sanitizeString($body['title'], 200);
        $i++;
    }
    if (isset($body['status'])) {
        $valid = ['upcoming','active','finished','cancelled'];
        if (in_array($body['status'], $valid, true)) {
            $updates[] = "status=\${$i}";
            $params[]  = $body['status'];
            $i++;
        }
    }
    if (empty($updates)) { respond(422, false, 'Nothing to update.'); return; }
    $params[] = $eventId;
    $db->prepare('UPDATE challenge_events SET ' . implode(',', $updates) . " WHERE id=\${$i}")
       ->execute($params);
    respond(200, true, 'Challenge updated.');
}

function respond(int $code, bool $ok, string $msg, array $data = []): void {
    http_response_code($code);
    echo json_encode(array_merge(['success'=>$ok,'message'=>$msg],$data),
        JSON_UNESCAPED_UNICODE);
}
