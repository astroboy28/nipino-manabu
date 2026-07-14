<?php
declare(strict_types=1);
require_once dirname(__DIR__).'/config/Database.php';
function respond(int $code, bool $ok, string $msg, array $data = []): void { http_response_code($code); echo json_encode(array_merge(["success"=>$ok,"message"=>$msg], $data), JSON_UNESCAPED_UNICODE); }
require_once dirname(__DIR__).'/middleware/Auth.php';
require_once dirname(__DIR__).'/email/FCM.php';
Auth::securityHeaders();
$db = Database::connect();
$method = $_SERVER['REQUEST_METHOD'];
$action = $_GET['action'] ?? '';
$claims = Auth::requireAuth();
$userId = (int)$claims['sub'];
$stmt = $db->prepare('SELECT is_admin FROM users WHERE id=?');
$stmt->execute([$userId]);
$row = $stmt->fetch();
if (!$row || !$row['is_admin']) { respond(403, false, 'Admin access required.'); exit; }
match(true) {
    $method==='GET'  && $action==='stats'           => handleStats($db),
    $method==='GET'  && $action==='users'           => handleGetUsers($db),
    $method==='POST' && $action==='give-coins'      => handleGiveCoins($db),
    $method==='GET'  && $action==='questions'       => handleGetQuestions($db),
    $method==='POST' && $action==='add-question'    => handleAddQuestion($db),
    $method==='POST' && $action==='edit-question'   => handleEditQuestion($db),
    $method==='POST' && $action==='delete-question' => handleDeleteQuestion($db),
    $method==='POST' && $action==='upload-audio'    => handleUploadAudio($db),
    $method==='POST' && $action==='generate-tts'    => handleGenerateTTS($db),
    $method==='POST' && $action==='ban-user'        => handleBanUser($db, $userId),
    $method==='POST' && $action==='unban-user'      => handleUnbanUser($db),
    $method==='POST' && $action==='set-admin'       => handleSetAdmin($db, $userId),
    $method==='POST' && $action==='broadcast'       => handleBroadcast($db),
    $method==='GET'  && $action==='error-logs'      => handleErrorLogs($db),
    default => respond(404, false, 'Not found'),
};
function handleStats(PDO $db): void {
    $users     = $db->query('SELECT COUNT(*) FROM users')->fetchColumn();
    $questions = $db->query('SELECT COUNT(*) FROM quiz_questions')->fetchColumn();
    $results   = $db->query('SELECT COUNT(*) FROM quiz_results')->fetchColumn();
    $coins     = $db->query('SELECT SUM(coins) FROM users')->fetchColumn();
    respond(200, true, 'Stats fetched.', [
        'total_users'     => (int)$users,
        'total_questions' => (int)$questions,
        'total_quizzes'   => (int)$results,
        'total_coins'     => (int)$coins,
    ]);
}
function handleGetUsers(PDO $db): void {
    $search = $_GET['search'] ?? '';
    $limit  = min((int)($_GET['limit'] ?? 20), 100);
    $offset = (int)($_GET['offset'] ?? 0);
    if ($search) {
        $stmt = $db->prepare('SELECT id,username,email,coins,streak_days,current_level,is_verified,is_admin,banned_at,ban_reason,created_at FROM users WHERE username ILIKE ? OR email ILIKE ? ORDER BY created_at DESC LIMIT ? OFFSET ?');
        $stmt->execute(["%$search%", "%$search%", $limit, $offset]);
    } else {
        $stmt = $db->prepare('SELECT id,username,email,coins,streak_days,current_level,is_verified,is_admin,banned_at,ban_reason,created_at FROM users ORDER BY created_at DESC LIMIT ? OFFSET ?');
        $stmt->execute([$limit, $offset]);
    }
    $users = $stmt->fetchAll();
    $total = $db->query('SELECT COUNT(*) FROM users')->fetchColumn();
    respond(200, true, 'Users fetched.', ['users' => $users, 'total' => (int)$total]);
}
function handleGiveCoins(PDO $db): void {
    $b      = Auth::getJsonBody();
    $userId = (int)($b['user_id'] ?? 0);
    $coins  = (int)($b['coins'] ?? 0);
    if ($userId < 1 || $coins < 1 || $coins > 100000) { respond(422, false, 'Invalid data.'); return; }
    // Every other coin-crediting path in the app (quiz rewards, duel prizes,
    // IAP/web purchases, referral bonuses) writes a coin_transactions row —
    // this one didn't, so admin grants were invisible in the ledger/user's
    // transaction history. 'admin_grant' has been a valid type there since
    // migration 004; nothing ever wrote one until now.
    $db->beginTransaction();
    try {
        $stmt = $db->prepare('UPDATE users SET coins=coins+? WHERE id=? RETURNING coins');
        $stmt->execute([$coins, $userId]);
        $row = $stmt->fetch();
        if (!$row) { $db->rollBack(); respond(404, false, 'User not found.'); return; }
        $db->prepare(
            "INSERT INTO coin_transactions (user_id, amount, balance_after, type, description)
             VALUES (?,?,?,'admin_grant',?)"
        )->execute([$userId, $coins, $row['coins'], 'Coins granted via admin panel']);
        $db->commit();
    } catch (\Exception $e) {
        $db->rollBack();
        respond(500, false, 'Grant failed.'); return;
    }
    respond(200, true, "Added $coins coins to user $userId.");
}
function handleGetQuestions(PDO $db): void {
    $level    = $_GET['level'] ?? '';
    $category = $_GET['category'] ?? '';
    $search   = trim($_GET['search'] ?? '');
    $limit    = min((int)($_GET['limit'] ?? 20), 100);
    $offset   = (int)($_GET['offset'] ?? 0);
    $params   = [];
    $where    = 'WHERE 1=1';
    if ($level)    { $where .= ' AND level=?';    $params[] = $level; }
    if ($category) { $where .= ' AND category=?'; $params[] = $category; }
    if ($search)   { $where .= ' AND (question_text ILIKE ? OR explanation ILIKE ?)'; $params[] = "%$search%"; $params[] = "%$search%"; }
    $params[] = $limit;
    $params[] = $offset;
    $stmt = $db->prepare("SELECT id,level,category,question_text,options,correct_index,explanation,memory_tip,point_value,is_active FROM quiz_questions $where ORDER BY id DESC LIMIT ? OFFSET ?");
    $stmt->execute($params);
    $questions = $stmt->fetchAll();
    $total = $db->query("SELECT COUNT(*) FROM quiz_questions")->fetchColumn();
    respond(200, true, 'Questions fetched.', ['questions' => $questions, 'total' => (int)$total]);
}
function handleAddQuestion(PDO $db): void {
    $b        = Auth::getJsonBody();
    $level    = trim($b['level'] ?? '');
    $category = trim($b['category'] ?? '');
    $text     = trim($b['question_text'] ?? '');
    $options  = $b['options'] ?? [];
    $correct  = (int)($b['correct_index'] ?? 0);
    $explanation = trim($b['explanation'] ?? '');
    $tip      = trim($b['memory_tip'] ?? '');
    $points   = (int)($b['point_value'] ?? 10);
    if (!$level || !$category || !$text || count($options) < 2) { respond(422, false, 'Missing fields.'); return; }
    $db->prepare('INSERT INTO quiz_questions (level,category,question_text,question_type,options,correct_index,explanation,memory_tip,point_value,is_active) VALUES (?,?,?,?,?,?,?,?,?,true)')
       ->execute([$level,$category,$text,'reading',json_encode($options,JSON_UNESCAPED_UNICODE),$correct,$explanation,$tip,$points]);
    respond(201, true, 'Question added.');
}
function handleEditQuestion(PDO $db): void {
    $b  = Auth::getJsonBody();
    $id = (int)($b['id'] ?? 0);
    if ($id < 1) { respond(422, false, 'Invalid ID.'); return; }
    $db->prepare('UPDATE quiz_questions SET level=?,category=?,question_text=?,options=?,correct_index=?,explanation=?,memory_tip=?,point_value=?,is_active=? WHERE id=?')
       ->execute([$b['level'],$b['category'],$b['question_text'],json_encode($b['options'],JSON_UNESCAPED_UNICODE),(int)$b['correct_index'],$b['explanation'],$b['memory_tip'],(int)$b['point_value'],(bool)($b['is_active']??true),$id]);
    respond(200, true, 'Question updated.');
}
function handleDeleteQuestion(PDO $db): void {
    $b  = Auth::getJsonBody();
    $id = (int)($b['id'] ?? 0);
    if ($id < 1) { respond(422, false, 'Invalid ID.'); return; }
    $db->prepare('UPDATE quiz_questions SET is_active=false WHERE id=?')->execute([$id]);
    respond(200, true, 'Question deactivated.');
}
function handleUploadAudio(PDO $db): void {
    if (!isset($_FILES['audio'])) { respond(422, false, 'No file uploaded.'); return; }
    $file = $_FILES['audio'];
    $ext  = strtolower(pathinfo($file['name'], PATHINFO_EXTENSION));
    if (!in_array($ext, ['mp3','wav','ogg'])) { respond(422, false, 'Invalid file type.'); return; }
    $filename = 'upload_' . uniqid() . '.' . $ext;
    $dest = '/var/www/nipino-manabu/backend/audio/' . $filename;
    if (!move_uploaded_file($file['tmp_name'], $dest)) { respond(500, false, 'Upload failed.'); return; }
    $url = 'https://api.nipino-manabu.com/audio/' . $filename;
    respond(200, true, 'Audio uploaded.', ['url' => $url, 'filename' => $filename]);
}
function handleGenerateTTS(PDO $db): void {
    $b = Auth::getJsonBody();
    $text = trim($b['text'] ?? '');
    $level = trim($b['level'] ?? 'N5');
    $filename = trim($b['filename'] ?? '');
    if (!$text) { respond(422, false, 'No text provided.'); return; }
    if (!$filename) $filename = strtolower($level) . '_tts_' . uniqid() . '.mp3';
    // $filename is client-supplied and was being concatenated straight into
    // a filesystem path with only a ".mp3" suffix enforced — a crafted value
    // like "../../api/x.mp3" could write outside the audio directory.
    // basename() strips any directory components and the whitelist below
    // strips everything else that isn't a safe filename character.
    $filename = preg_replace('/[^a-zA-Z0-9_.-]/', '_', basename($filename));
    if (!$filename || $filename === '.' || $filename === '..') { respond(422, false, 'Invalid filename.'); return; }
    if (!str_ends_with($filename, '.mp3')) $filename .= '.mp3';
    $dest = '/var/www/nipino-manabu/backend/audio/' . $filename;
    $result = shell_exec("python3 -c \"from gtts import gTTS; tts=gTTS(text=" . escapeshellarg($text) . ",lang='ja'); tts.save(" . escapeshellarg($dest) . ")\" 2>&1");
    if (!file_exists($dest)) { respond(500, false, 'TTS generation failed: ' . $result); return; }
    $url = 'https://api.nipino-manabu.com/audio/' . $filename;
    respond(200, true, 'Audio generated.', ['url' => $url, 'filename' => $filename]);
}
function handleBanUser(PDO $db, int $callerId): void {
    $b      = Auth::getJsonBody();
    $userId = (int)($b['user_id'] ?? 0);
    $reason = trim($b['reason'] ?? '');
    if ($userId < 1) { respond(422, false, 'Invalid user_id.'); return; }
    if ($userId === $callerId) { respond(409, false, 'You cannot ban yourself.'); return; }
    $target = $db->prepare('SELECT username, is_admin FROM users WHERE id=?');
    $target->execute([$userId]);
    $t = $target->fetch();
    if (!$t) { respond(404, false, 'User not found.'); return; }
    // Demote first — stops a compromised admin session from banning other
    // admins to cover its tracks.
    if ($t['is_admin']) { respond(409, false, 'Demote this user before banning them.'); return; }
    $db->prepare('UPDATE users SET is_active=FALSE, banned_at=NOW(), ban_reason=?, banned_by_id=? WHERE id=?')
       ->execute([$reason ?: null, $callerId, $userId]);
    $db->prepare('UPDATE refresh_tokens SET revoked_at=NOW() WHERE user_id=? AND revoked_at IS NULL')
       ->execute([$userId]);
    respond(200, true, "{$t['username']} has been banned.");
}
function handleUnbanUser(PDO $db): void {
    $b      = Auth::getJsonBody();
    $userId = (int)($b['user_id'] ?? 0);
    if ($userId < 1) { respond(422, false, 'Invalid user_id.'); return; }
    // Only lifts bans this panel itself created — never touches
    // deletion_scheduled_at, so it can't be used to sidestep the separate
    // GDPR account-deletion flow (backend/api/account.php).
    $stmt = $db->prepare(
        'UPDATE users SET is_active=TRUE, banned_at=NULL, ban_reason=NULL, banned_by_id=NULL
         WHERE id=? AND banned_at IS NOT NULL RETURNING username'
    );
    $stmt->execute([$userId]);
    $row = $stmt->fetch();
    if (!$row) { respond(404, false, 'No active ban found for this user.'); return; }
    respond(200, true, "{$row['username']} has been unbanned.");
}
function handleSetAdmin(PDO $db, int $callerId): void {
    $b       = Auth::getJsonBody();
    $userId  = (int)($b['user_id'] ?? 0);
    $isAdmin = (bool)($b['is_admin'] ?? false);
    if ($userId < 1) { respond(422, false, 'Invalid user_id.'); return; }
    // Prevent revoking your own admin access — that's how you end up with
    // zero admins and no way back in short of a direct DB edit.
    if ($userId === $callerId && !$isAdmin) { respond(409, false, 'You cannot revoke your own admin access.'); return; }
    $stmt = $db->prepare('UPDATE users SET is_admin=? WHERE id=? RETURNING username');
    $stmt->execute([$isAdmin ? 'true' : 'false', $userId]);
    $row = $stmt->fetch();
    if (!$row) { respond(404, false, 'User not found.'); return; }
    respond(200, true, $isAdmin ? "{$row['username']} is now an admin." : "Admin access revoked for {$row['username']}.");
}
function handleBroadcast(PDO $db): void {
    $b     = Auth::getJsonBody();
    $title = trim($b['title'] ?? '');
    $msg   = trim($b['body']  ?? '');
    if (!$title || !$msg) { respond(422, false, 'title and body are required.'); return; }
    $stmt = $db->prepare('SELECT id, fcm_token FROM users WHERE is_active=TRUE AND fcm_token IS NOT NULL LIMIT 10000');
    $stmt->execute();
    $users  = $stmt->fetchAll();
    $tokens = array_column($users, 'fcm_token');
    $result = FCM::sendToTokens($tokens, $title, $msg, ['type' => 'admin_broadcast']);
    if ($users) {
        $log = $db->prepare("INSERT INTO notification_log (user_id, type, title, body, delivered) VALUES (?, 'admin_broadcast', ?, ?, TRUE)");
        foreach ($users as $u) { $log->execute([$u['id'], $title, $msg]); }
    }
    respond(200, true, "Sent to {$result['sent']} users ({$result['failed']} failed).", $result);
}
function handleErrorLogs(PDO $db): void {
    $level = trim($_GET['level'] ?? '');
    $limit = min((int)($_GET['limit'] ?? 50), 200) ?: 50;
    if (in_array($level, ['error','warn','info'], true)) {
        $stmt = $db->prepare('SELECT level, context, message, meta, user_id, created_at FROM error_log WHERE level=? ORDER BY created_at DESC LIMIT ?');
        $stmt->execute([$level, $limit]);
    } else {
        $stmt = $db->prepare('SELECT level, context, message, meta, user_id, created_at FROM error_log ORDER BY created_at DESC LIMIT ?');
        $stmt->execute([$limit]);
    }
    respond(200, true, 'Logs fetched.', ['logs' => $stmt->fetchAll()]);
}
