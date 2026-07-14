<?php
// backend/api/duel.php
// ─── Duel rooms: coin-bet quiz battles between 2–3 players ───────────────────
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
    $method === 'POST' && $action === 'create'       => handleCreate($db),
    $method === 'POST' && $action === 'invite'        => handleInvite($db),
    $method === 'POST' && $action === 'join'          => handleJoin($db),
    $method === 'POST' && $action === 'ready'         => handleReady($db),
    $method === 'POST' && $action === 'answer'        => handleAnswer($db),
    $method === 'POST' && $action === 'forfeit'       => handleForfeit($db),
    $method === 'GET'  && $action === 'room'          => handleGetRoom($db),
    $method === 'GET'  && $action === 'list'          => handleList($db),
    $method === 'GET'  && $action === 'invitations'   => handleGetInvitations($db),
    $method === 'POST' && $action === 'respond-invite'=> handleRespondInvite($db),
    default => respond(404, false, 'Endpoint not found'),
};

// ════════════════════════════════════════════════════════════════════════════
// CREATE DUEL ROOM
// ════════════════════════════════════════════════════════════════════════════
function handleCreate(PDO $db): void {
    $claims = Auth::requireAuth();
    $userId = (int) $claims['sub'];
    $ip     = $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';
    RateLimiter::enforce($ip, 'duel_create', 10, 3600);

    $body        = Auth::getJsonBody();
    $level       = Auth::sanitizeString($body['level']       ?? '', 2);
    $category    = Auth::sanitizeString($body['category']    ?? '', 20);
    $coinBet     = (int) ($body['coin_bet']      ?? 0);
    $maxPlayers  = (int) ($body['max_players']   ?? 2);
    $timedMode   = (bool)($body['timed_mode']    ?? true);
    $secsPerQ    = (int) ($body['seconds_per_q'] ?? 15);
    $questionCnt = (int) ($body['question_count']?? 10);

    $validLevels = ['N1','N2','N3','N4','N5'];
    $validCats   = ['kanji','vocabulary','grammar','listening'];

    if (!in_array($level, $validLevels, true))
        { respond(422, false, 'Invalid level.'); return; }
    if (!in_array($category, $validCats, true))
        { respond(422, false, 'Invalid category.'); return; }
    if ($coinBet < 10 || $coinBet > 1000)
        { respond(422, false, 'Coin bet must be between 10 and 1,000.'); return; }
    if ($maxPlayers < 2 || $maxPlayers > 3)
        { respond(422, false, 'Max players must be 2 or 3.'); return; }
    if ($secsPerQ < 5 || $secsPerQ > 60)
        { respond(422, false, 'Seconds per question must be 5–60.'); return; }
    $questionCnt = max(5, min(20, $questionCnt));

    // Check user has enough coins
    $balStmt = $db->prepare('SELECT coins FROM users WHERE id=?');
    $balStmt->execute([$userId]);
    $bal = (int)($balStmt->fetch()['coins'] ?? 0);
    if ($bal < $coinBet) {
        respond(402, false,
            "Not enough coins. You have {$bal} coins but the bet is {$coinBet}."); return;
    }

    // Pre-fetch questions to lock them for this duel
    $qStmt = $db->prepare(
        'SELECT id FROM quiz_questions
         WHERE level=? AND category=? AND is_active=TRUE
         ORDER BY RANDOM() LIMIT ?'
    );
    $qStmt->execute([$level, $category, $questionCnt]);
    $qIds = array_column($qStmt->fetchAll(), 'id');
    if (count($qIds) < $questionCnt) {
        respond(404, false,
            'Not enough questions available for this level/category combination.'); return;
    }

    $db->beginTransaction();
    try {
        // Deduct bet from host — atomic + re-checked inside the
        // transaction (not just the earlier SELECT) so two concurrent
        // requests can't both pass the balance check and overdraw coins.
        $deduct = $db->prepare('UPDATE users SET coins=coins-? WHERE id=? AND coins>=?');
        $deduct->execute([$coinBet, $userId, $coinBet]);
        if ($deduct->rowCount() === 0) {
            $db->rollBack();
            respond(402, false, 'Not enough coins. Your balance may have changed.'); return;
        }

        // Create room
        $roomStmt = $db->prepare(
            'INSERT INTO duel_rooms
             (host_user_id, level, category, question_count, coin_bet,
              timed_mode, seconds_per_q, max_players)
             VALUES (?,?,?,?,?,?,?,?)
             RETURNING id, uuid'
        );
        $roomStmt->execute([
            $userId, $level, $category, $questionCnt, $coinBet,
            $timedMode ? 'true' : 'false', $secsPerQ, $maxPlayers,
        ]);
        $room = $roomStmt->fetch();

        // Add host as participant
        $db->prepare(
            'INSERT INTO duel_participants (room_id, user_id, status, coins_wagered)
             VALUES (?,?,\'joined\',?)'
        )->execute([$room['id'], $userId, $coinBet]);

        // Record debit transaction
        $newBal = $bal - $coinBet;
        $db->prepare(
            'INSERT INTO coin_transactions
             (user_id, amount, balance_after, type, reference_id, description)
             VALUES (?,?,?,\'duel_bet_debit\',?,?)'
        )->execute([
            $userId, -$coinBet, $newBal, $room['id'],
            "Duel bet placed — room {$room['uuid']}",
        ]);

        // Store question IDs in Redis for fast retrieval during live duel
        // Key: duel:questions:{room_id}
        $redisKey = 'duel:questions:' . $room['id'];
        require_once dirname(__DIR__) . '/redis/RateLimiter.php';
        \RateLimiter::cacheSet($redisKey, json_encode($qIds), 7200); // 2hr TTL

        $db->commit();
    } catch (\Exception $e) {
        $db->rollBack();
        Monitor::error('duel_create', $e->getMessage(), [], $userId);
        respond(500, false, 'Failed to create duel room.'); return;
    }

    respond(201, true, 'Duel room created!', [
        'room_id'   => $room['id'],
        'room_uuid' => $room['uuid'],
        'invite_link' => 'nipinomanabu://duel/' . $room['uuid'],
        'coin_bet'  => $coinBet,
        'new_balance' => $bal - $coinBet,
    ]);
}

// ════════════════════════════════════════════════════════════════════════════
// INVITE A USER TO A DUEL ROOM
// ════════════════════════════════════════════════════════════════════════════
function handleInvite(PDO $db): void {
    $claims    = Auth::requireAuth();
    $userId    = (int) $claims['sub'];
    $ip        = $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';
    // No limit here before meant an unlimited number of invite/notification
    // spam attempts, and — since the "user not found" response differs from
    // success — an unlimited number of user-ID-existence probes too.
    RateLimiter::enforce($ip, 'duel_invite', 20, 3600);
    $body      = Auth::getJsonBody();
    $roomId    = (int) ($body['room_id']    ?? 0);
    $inviteeId = (int) ($body['invitee_id'] ?? 0);
    $message   = Auth::sanitizeString($body['message'] ?? '', 200);

    // Verify host owns the room and it is still waiting
    $roomStmt = $db->prepare(
        'SELECT id, host_user_id, status, max_players,
           (SELECT COUNT(*) FROM duel_participants WHERE room_id=?) AS joined
         FROM duel_rooms WHERE id=? AND host_user_id=?'
    );
    $roomStmt->execute([$roomId, $userId]);
    $room = $roomStmt->fetch();
    if (!$room)    { respond(403, false, 'Room not found or you are not the host.'); return; }
    if ($room['status'] !== 'waiting') { respond(409, false, 'Room is no longer accepting invites.'); return; }
    if ((int)$room['joined'] >= (int)$room['max_players'])
        { respond(409, false, 'Room is full.'); return; }

    // Check invitee exists
    $invStmt = $db->prepare('SELECT id, username, fcm_token FROM users WHERE id=? AND is_active=TRUE');
    $invStmt->execute([$inviteeId]);
    $invitee = $invStmt->fetch();
    if (!$invitee) { respond(404, false, 'User not found.'); return; }

    // Avoid duplicate pending invite
    $dupStmt = $db->prepare(
        "SELECT id FROM invitations
         WHERE type='duel' AND from_user_id=? AND to_user_id=?
           AND reference_id=? AND status='pending'"
    );
    $dupStmt->execute([$userId, $inviteeId, $roomId]);
    if ($dupStmt->fetch()) { respond(409, false, 'Already invited this user.'); return; }

    // Create invitation
    $db->prepare(
        "INSERT INTO invitations (type, from_user_id, to_user_id, reference_id, message)
         VALUES ('duel',?,?,?,?)"
    )->execute([$userId, $inviteeId, $roomId, $message]);

    // Send push notification
    if ($invitee['fcm_token']) {
        $hostName = $claims['username'];
        FCM::sendToToken(
            $invitee['fcm_token'],
            "⚔️ {$hostName} challenges you!",
            "You've been invited to a coin duel. Tap to accept!",
            ['type' => 'duel_invite', 'room_id' => (string)$roomId, 'screen' => 'duel']
        );
    }

    respond(200, true, 'Invitation sent to ' . $invitee['username'] . '.');
}

// ════════════════════════════════════════════════════════════════════════════
// JOIN A DUEL ROOM (via UUID deep link or invitation)
// ════════════════════════════════════════════════════════════════════════════
function handleJoin(PDO $db): void {
    $claims   = Auth::requireAuth();
    $userId   = (int) $claims['sub'];
    $body     = Auth::getJsonBody();
    $roomUuid = Auth::sanitizeString($body['room_uuid'] ?? '', 40);

    $roomStmt = $db->prepare(
        'SELECT id, host_user_id, status, max_players, coin_bet, expires_at,
           (SELECT COUNT(*) FROM duel_participants WHERE room_id=dr.id) AS joined
         FROM duel_rooms dr WHERE uuid=?'
    );
    $roomStmt->execute([$roomUuid]);
    $room = $roomStmt->fetch();

    if (!$room)                         { respond(404, false, 'Duel room not found.'); return; }
    if ($room['status'] !== 'waiting')  { respond(409, false, 'This room has already started or ended.'); return; }
    if (strtotime($room['expires_at']) < time()) { respond(410, false, 'This duel has expired.'); return; }
    if ((int)$room['joined'] >= (int)$room['max_players']) { respond(409, false, 'Room is full.'); return; }
    if ((int)$room['host_user_id'] === $userId) { respond(409, false, 'You are already in this room as the host.'); return; }

    // Check already joined
    $chkStmt = $db->prepare('SELECT id FROM duel_participants WHERE room_id=? AND user_id=?');
    $chkStmt->execute([$room['id'], $userId]);
    if ($chkStmt->fetch()) { respond(409, false, 'You have already joined this room.'); return; }

    // Check coins
    $coinBet = (int)$room['coin_bet'];
    $balStmt = $db->prepare('SELECT coins FROM users WHERE id=?');
    $balStmt->execute([$userId]);
    $bal = (int)($balStmt->fetch()['coins'] ?? 0);
    if ($bal < $coinBet) {
        respond(402, false,
            "Not enough coins. You need {$coinBet} coins to join, you have {$bal}."); return;
    }

    $db->beginTransaction();
    try {
        // Lock the room row so concurrent joins serialize instead of both
        // reading the same stale "joined < max_players" snapshot — without
        // this, two users joining a 1-slot-left room at the same instant
        // could both pass the earlier check and overfill it past max_players.
        $lockStmt = $db->prepare(
            'SELECT dr.status, dr.max_players,
               (SELECT COUNT(*) FROM duel_participants WHERE room_id=dr.id) AS joined
             FROM duel_rooms dr WHERE dr.id=? FOR UPDATE'
        );
        $lockStmt->execute([$room['id']]);
        $locked = $lockStmt->fetch();
        if (!$locked || $locked['status'] !== 'waiting') {
            $db->rollBack();
            respond(409, false, 'This room has already started or ended.'); return;
        }
        if ((int)$locked['joined'] >= (int)$locked['max_players']) {
            $db->rollBack();
            respond(409, false, 'Room is full.'); return;
        }

        // Atomic + re-checked inside the transaction — same reasoning as
        // handleCreate: the earlier SELECT can go stale under concurrency.
        $deduct = $db->prepare('UPDATE users SET coins=coins-? WHERE id=? AND coins>=?');
        $deduct->execute([$coinBet, $userId, $coinBet]);
        if ($deduct->rowCount() === 0) {
            $db->rollBack();
            respond(402, false, 'Not enough coins. Your balance may have changed.'); return;
        }

        $db->prepare(
            "INSERT INTO duel_participants (room_id, user_id, status, coins_wagered)
             VALUES (?,?,'joined',?)"
        )->execute([$room['id'], $userId, $coinBet]);

        $newBal = $bal - $coinBet;
        $db->prepare(
            "INSERT INTO coin_transactions
             (user_id, amount, balance_after, type, reference_id, description)
             VALUES (?,?,?,'duel_bet_debit',?,?)"
        )->execute([
            $userId, -$coinBet, $newBal, $room['id'],
            'Duel bet — joined room',
        ]);

        // Accept any pending invitation from this room to this user
        $db->prepare(
            "UPDATE invitations SET status='accepted'
             WHERE type='duel' AND to_user_id=? AND reference_id=? AND status='pending'"
        )->execute([$userId, $room['id']]);

        $db->commit();
    } catch (\Exception $e) {
        $db->rollBack();
        respond(500, false, 'Failed to join room.'); return;
    }

    // Notify host
    $hostStmt = $db->prepare('SELECT username, fcm_token FROM users WHERE id=?');
    $hostStmt->execute([$room['host_user_id']]);
    $host = $hostStmt->fetch();
    if ($host && $host['fcm_token']) {
        FCM::sendToToken(
            $host['fcm_token'],
            '⚔️ ' . $claims['username'] . ' joined your duel!',
            'Your room is ready. Tap to start the battle.',
            ['type' => 'duel_joined', 'room_id' => (string)$room['id'], 'screen' => 'duel']
        );
    }

    respond(200, true, 'Joined duel room.', [
        'room_id'     => $room['id'],
        'coin_bet'    => $coinBet,
        'new_balance' => $bal - $coinBet,
    ]);
}

// ════════════════════════════════════════════════════════════════════════════
// MARK READY — host starts when all players are ready
// ════════════════════════════════════════════════════════════════════════════
function handleReady(PDO $db): void {
    $claims = Auth::requireAuth();
    $userId = (int) $claims['sub'];
    $body   = Auth::getJsonBody();
    $roomId = (int) ($body['room_id'] ?? 0);

    // Verify participant
    $stmt = $db->prepare(
        "SELECT dp.id, dr.host_user_id, dr.status, dr.max_players,
           (SELECT COUNT(*) FROM duel_participants WHERE room_id=? AND status='joined') AS joined_count
         FROM duel_participants dp
         JOIN duel_rooms dr ON dr.id=dp.room_id
         WHERE dp.room_id=? AND dp.user_id=?"
    );
    $stmt->execute([$roomId, $userId]);
    $row = $stmt->fetch();
    if (!$row)                          { respond(403, false, 'Not in this room.'); return; }
    if ($row['status'] !== 'waiting')   { respond(409, false, 'Duel already started.'); return; }

    // Mark this participant as ready
    $db->prepare("UPDATE duel_participants SET status='ready' WHERE room_id=? AND user_id=?")
       ->execute([$roomId, $userId]);

    // Check if all participants are ready — if so, start the duel
    $readyStmt = $db->prepare(
        "SELECT COUNT(*) AS cnt FROM duel_participants WHERE room_id=? AND status='ready'"
    );
    $readyStmt->execute([$roomId]);
    $readyCount = (int)($readyStmt->fetch()['cnt'] ?? 0);
    $joinedCount = (int)$row['joined_count'];

    $started = false;
    if ($readyCount >= $joinedCount && $joinedCount >= 2) {
        $db->prepare(
            "UPDATE duel_rooms SET status='active', started_at=NOW() WHERE id=?"
        )->execute([$roomId]);

        // Notify all participants
        $partStmt = $db->prepare(
            'SELECT u.fcm_token FROM duel_participants dp
             JOIN users u ON u.id=dp.user_id
             WHERE dp.room_id=? AND u.fcm_token IS NOT NULL'
        );
        $partStmt->execute([$roomId]);
        foreach ($partStmt->fetchAll() as $p) {
            FCM::sendToToken($p['fcm_token'], '⚔️ Duel starting!',
                'All players are ready — the quiz begins now!',
                ['type' => 'duel_start', 'room_id' => (string)$roomId, 'screen' => 'duel']);
        }
        $started = true;
    }

    respond(200, true, $started ? 'All ready — duel started!' : 'Marked as ready.',
        ['duel_started' => $started]);
}

// ════════════════════════════════════════════════════════════════════════════
// SUBMIT ANSWER
// ════════════════════════════════════════════════════════════════════════════
function handleAnswer(PDO $db): void {
    $claims   = Auth::requireAuth();
    $userId   = (int) $claims['sub'];
    $body     = Auth::getJsonBody();
    $roomId   = (int) ($body['room_id']        ?? 0);
    $qOrder   = (int) ($body['question_order'] ?? 0); // 0-indexed
    $chosen   = isset($body['chosen_index']) ? (int)$body['chosen_index'] : null;
    $answerMs = (int) ($body['answer_ms']      ?? 0);

    // Verify room is active and user is participant
    $roomStmt = $db->prepare(
        'SELECT dr.status, dr.timed_mode, dr.seconds_per_q, dr.question_count
         FROM duel_rooms dr
         JOIN duel_participants dp ON dp.room_id=dr.id AND dp.user_id=?
         WHERE dr.id=? AND dr.status=\'active\''
    );
    $roomStmt->execute([$roomId, $userId]);
    $room = $roomStmt->fetch();
    if (!$room) { respond(403, false, 'Not in an active duel room.'); return; }

    if ($qOrder < 0 || $qOrder >= (int)$room['question_count'])
        { respond(422, false, 'Invalid question order.'); return; }

    // Prevent re-answering
    $dupStmt = $db->prepare(
        'SELECT id FROM duel_answers WHERE room_id=? AND user_id=? AND question_order=?'
    );
    $dupStmt->execute([$roomId, $userId, $qOrder]);
    if ($dupStmt->fetch()) { respond(409, false, 'Already answered this question.'); return; }

    // Get the question ID for this position from Redis cache
    $qIds = json_decode(
        \RateLimiter::cacheGet('duel:questions:' . $roomId) ?? '[]', true
    );
    if (empty($qIds) || !isset($qIds[$qOrder])) {
        respond(500, false, 'Question data unavailable.'); return;
    }
    $questionId = (int)$qIds[$qOrder];

    // Verify answer correctness
    $qStmt = $db->prepare('SELECT correct_index, point_value FROM quiz_questions WHERE id=?');
    $qStmt->execute([$questionId]);
    $question    = $qStmt->fetch();
    $isCorrect   = ($chosen !== null && $chosen === (int)$question['correct_index']);

    // Timed mode: answer after time limit counts as wrong
    if ($room['timed_mode'] && $answerMs > ($room['seconds_per_q'] * 1000 + 500)) {
        $isCorrect = false;
        $chosen    = null; // treat as timeout
    }

    $score = $isCorrect ? (int)$question['point_value'] : 0;

    // Save answer
    $db->prepare(
        'INSERT INTO duel_answers
         (room_id, user_id, question_id, question_order, chosen_index, is_correct, answer_ms)
         VALUES (?,?,?,?,?,?,?)'
    )->execute([$roomId, $userId, $questionId, $qOrder, $chosen, $isCorrect ? 'true' : 'false', $answerMs]);

    // Update participant score
    $db->prepare(
        'UPDATE duel_participants
         SET score=score+?, correct_count=correct_count+?, time_taken_ms=time_taken_ms+?
         WHERE room_id=? AND user_id=?'
    )->execute([$score, $isCorrect ? 1 : 0, $answerMs, $roomId, $userId]);

    // Check if this user has answered all questions
    $answeredStmt = $db->prepare(
        'SELECT COUNT(*) AS cnt FROM duel_answers WHERE room_id=? AND user_id=?'
    );
    $answeredStmt->execute([$roomId, $userId]);
    $answeredCount = (int)($answeredStmt->fetch()['cnt'] ?? 0);

    $userFinished = $answeredCount >= (int)$room['question_count'];
    if ($userFinished) {
        $db->prepare(
            "UPDATE duel_participants SET status='finished', finished_at=NOW()
             WHERE room_id=? AND user_id=?"
        )->execute([$roomId, $userId]);
    }

    // Check if ALL active participants have finished
    $allDoneStmt = $db->prepare(
        "SELECT COUNT(*) AS total,
           SUM(CASE WHEN status IN ('finished','forfeit') THEN 1 ELSE 0 END) AS done
         FROM duel_participants WHERE room_id=?"
    );
    $allDoneStmt->execute([$roomId]);
    $progress = $allDoneStmt->fetch();
    $duelDone = (int)$progress['total'] > 0
        && (int)$progress['done'] >= (int)$progress['total'];

    if ($duelDone) {
        try { $db->exec("SELECT finalize_duel($roomId)"); }
        catch (\Throwable $e) { Monitor::error('duel_finalize', $e->getMessage(), ['room_id' => $roomId], $userId); }
    }

    respond(200, true, $isCorrect ? 'Correct!' : 'Wrong.',
    [
        'is_correct'    => $isCorrect,
        'score_awarded' => $score,
        'user_finished' => $userFinished,
        'duel_finished' => $duelDone,
    ]);
}

// ════════════════════════════════════════════════════════════════════════════
// FORFEIT
// ════════════════════════════════════════════════════════════════════════════
function handleForfeit(PDO $db): void {
    $claims = Auth::requireAuth();
    $userId = (int) $claims['sub'];
    $body   = Auth::getJsonBody();
    $roomId = (int) ($body['room_id'] ?? 0);

    $stmt = $db->prepare(
        "UPDATE duel_participants SET status='forfeit', finished_at=NOW()
         WHERE room_id=? AND user_id=?
           AND status NOT IN ('finished','forfeit')"
    );
    $stmt->execute([$roomId, $userId]);
    if ($stmt->rowCount() === 0) { respond(409, false, 'Cannot forfeit.'); return; }

    // Check if all others are done
    $allDoneStmt = $db->prepare(
        "SELECT COUNT(*) AS total,
           SUM(CASE WHEN status IN ('finished','forfeit') THEN 1 ELSE 0 END) AS done
         FROM duel_participants WHERE room_id=?"
    );
    $allDoneStmt->execute([$roomId]);
    $p = $allDoneStmt->fetch();
    if ((int)$p['done'] >= (int)$p['total']) {
        try { $db->exec("SELECT finalize_duel($roomId)"); }
        catch (\Throwable $e) { Monitor::error('duel_finalize', $e->getMessage(), ['room_id' => $roomId], $userId); }
    }
    respond(200, true, 'Forfeited. Coins lost.');
}

// ════════════════════════════════════════════════════════════════════════════
// GET ROOM STATE (polling / websocket alternative)
// ════════════════════════════════════════════════════════════════════════════
function handleGetRoom(PDO $db): void {
    $claims   = Auth::requireAuth();
    $userId   = (int) $claims['sub'];
    $roomUuid = $_GET['uuid'] ?? '';
    if (!$roomUuid) { respond(422, false, 'Room UUID required.'); return; }

    $roomStmt = $db->prepare(
        'SELECT dr.*, u.username AS host_username
         FROM duel_rooms dr JOIN users u ON u.id=dr.host_user_id
         WHERE dr.uuid=?'
    );
    $roomStmt->execute([$roomUuid]);
    $room = $roomStmt->fetch();
    if (!$room) { respond(404, false, 'Room not found.'); return; }

    $partStmt = $db->prepare(
        'SELECT dp.user_id, u.username, dp.status, dp.score,
                dp.correct_count, dp.time_taken_ms, dp.coins_wagered
         FROM duel_participants dp JOIN users u ON u.id=dp.user_id
         WHERE dp.room_id=? ORDER BY dp.score DESC, dp.time_taken_ms ASC'
    );
    $partStmt->execute([$room['id']]);
    $participants = $partStmt->fetchAll();

    // Fetch questions (without revealing correct answers if duel is active)
    $qIds   = json_decode(\RateLimiter::cacheGet('duel:questions:'.$room['id']) ?? '[]', true);
    $qData  = [];
    if (!empty($qIds)) {
        $inList = implode(',', array_map('intval', $qIds));
        $qRes   = $db->query(
            "SELECT id, question_text, question_type, options,
               CASE WHEN '{$room['status']}'='finished' THEN correct_index ELSE NULL END AS correct_index,
               point_value, memory_tip, image_url, audio_url, media_credit
             FROM quiz_questions WHERE id IN ($inList)"
        );
        $qMap = [];
        foreach ($qRes->fetchAll() as $q) {
            $q['options'] = json_decode($q['options'], true);
            $qMap[$q['id']] = $q;
        }
        foreach ($qIds as $qid) {
            if (isset($qMap[$qid])) $qData[] = $qMap[$qid];
        }
    }

    // Winner info
    $winner = null;
    if ($room['winner_user_id']) {
        $wStmt = $db->prepare('SELECT id, username FROM users WHERE id=?');
        $wStmt->execute([$room['winner_user_id']]);
        $winner = $wStmt->fetch();
    }

    respond(200, true, 'Room fetched.', [
        'room'         => [
            'id'             => (int)$room['id'],
            'uuid'           => $room['uuid'],
            'host_username'  => $room['host_username'],
            'level'          => $room['level'],
            'category'       => $room['category'],
            'coin_bet'       => (int)$room['coin_bet'],
            'timed_mode'     => (bool)$room['timed_mode'],
            'seconds_per_q'  => (int)$room['seconds_per_q'],
            'question_count' => (int)$room['question_count'],
            'max_players'    => (int)$room['max_players'],
            'status'         => $room['status'],
            'prize_coins'    => (int)$room['prize_coins'],
            'expires_at'     => $room['expires_at'],
            'started_at'     => $room['started_at'],
            'finished_at'    => $room['finished_at'],
        ],
        'participants' => $participants,
        'questions'    => $qData,
        'winner'       => $winner,
    ]);
}

// ════════════════════════════════════════════════════════════════════════════
// LIST OPEN ROOMS (join by browsing)
// ════════════════════════════════════════════════════════════════════════════
function handleList(PDO $db): void {
    Auth::requireAuth();
    $stmt = $db->prepare(
        "SELECT dr.uuid, dr.level, dr.category, dr.coin_bet,
                dr.timed_mode, dr.seconds_per_q, dr.max_players,
                dr.expires_at, u.username AS host,
                (SELECT COUNT(*) FROM duel_participants WHERE room_id=dr.id) AS joined
         FROM duel_rooms dr JOIN users u ON u.id=dr.host_user_id
         WHERE dr.status='waiting' AND dr.expires_at > NOW()
         ORDER BY dr.created_at DESC LIMIT 20"
    );
    $stmt->execute();
    $rooms = $stmt->fetchAll();
    respond(200, true, 'Open rooms fetched.', ['rooms' => $rooms]);
}

// ════════════════════════════════════════════════════════════════════════════
// GET INVITATIONS FOR CURRENT USER
// ════════════════════════════════════════════════════════════════════════════
function handleGetInvitations(PDO $db): void {
    $claims = Auth::requireAuth();
    $userId = (int) $claims['sub'];
    $stmt = $db->prepare(
        "SELECT i.id, i.uuid, i.type, i.message, i.expires_at, i.created_at,
                i.reference_id,
                fu.username AS from_username,
                CASE
                  WHEN i.type='duel' THEN
                    (SELECT json_build_object('level',level,'category',category,'coin_bet',coin_bet,'status',status)
                     FROM duel_rooms WHERE id=i.reference_id)
                  WHEN i.type='challenge' THEN
                    (SELECT json_build_object('title',title,'prize_coins',prize_coins,'starts_at',starts_at)
                     FROM challenge_events WHERE id=i.reference_id)
                END AS details
         FROM invitations i
         LEFT JOIN users fu ON fu.id=i.from_user_id
         WHERE i.to_user_id=? AND i.status='pending' AND i.expires_at>NOW()
         ORDER BY i.created_at DESC"
    );
    $stmt->execute([$userId]);
    $invitations = $stmt->fetchAll();
    foreach ($invitations as &$inv) {
        if (is_string($inv['details'])) {
            $inv['details'] = json_decode($inv['details'], true);
        }
    }
    respond(200, true, 'Invitations fetched.', ['invitations' => $invitations]);
}

// ════════════════════════════════════════════════════════════════════════════
// RESPOND TO INVITATION (accept/decline)
// ════════════════════════════════════════════════════════════════════════════
function handleRespondInvite(PDO $db): void {
    $claims     = Auth::requireAuth();
    $userId     = (int) $claims['sub'];
    $body       = Auth::getJsonBody();
    $invUuid    = Auth::sanitizeString($body['invitation_uuid'] ?? '', 40);
    $action     = Auth::sanitizeString($body['action'] ?? '', 10);

    if (!in_array($action, ['accept','decline'], true))
        { respond(422, false, 'Action must be accept or decline.'); return; }

    $invStmt = $db->prepare(
        "SELECT id, type, reference_id FROM invitations
         WHERE uuid=? AND to_user_id=? AND status='pending' AND expires_at>NOW()"
    );
    $invStmt->execute([$invUuid, $userId]);
    $inv = $invStmt->fetch();
    if (!$inv) { respond(404, false, 'Invitation not found or expired.'); return; }

    $db->prepare(
        "UPDATE invitations SET status=? WHERE id=?"
    )->execute([$action === 'accept' ? 'accepted' : 'declined', $inv['id']]);

    // For duel invites, the client needs the room's own uuid (distinct from
    // this invitation's uuid) to actually call /duel/join — it previously
    // had no way to get it and was reusing the invitation uuid as if it
    // were the room uuid, which never matches any room.
    $roomUuid = null;
    if ($inv['type'] === 'duel') {
        $roomStmt = $db->prepare('SELECT uuid FROM duel_rooms WHERE id=?');
        $roomStmt->execute([$inv['reference_id']]);
        $roomUuid = $roomStmt->fetch()['uuid'] ?? null;
    }

    respond(200, true, "Invitation {$action}ed.", [
        'type'         => $inv['type'],
        'reference_id' => $inv['reference_id'],
        'room_uuid'    => $roomUuid,
    ]);
}

function respond(int $code, bool $ok, string $msg, array $data = []): void {
    http_response_code($code);
    echo json_encode(array_merge(['success'=>$ok,'message'=>$msg],$data),
        JSON_UNESCAPED_UNICODE);
}
