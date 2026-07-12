<?php
// backend/api/auth.php — register, login, refresh, logout, forgot-password,
//                        reset-password, verify-email, resend-verification
declare(strict_types=1);

require_once dirname(__DIR__) . '/config/Database.php';
require_once dirname(__DIR__) . '/middleware/Auth.php';
require_once dirname(__DIR__) . '/redis/RateLimiter.php';
require_once dirname(__DIR__) . '/email/Mailer.php';

Auth::securityHeaders();
$db     = Database::connect();
$body   = Auth::getJsonBody();
$method = $_SERVER['REQUEST_METHOD'];
$action = $_GET['action'] ?? '';
$ip     = $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';

if (RateLimiter::isBlacklisted($ip)) {
    http_response_code(403);
    echo json_encode(['success'=>false,'message'=>'Access denied.']);
    exit;
}

match (true) {
    $method==='POST' && $action==='register'            => handleRegister($db,$body,$ip),
    $method==='POST' && $action==='login'               => handleLogin($db,$body,$ip),
    $method==='POST' && $action==='refresh'             => handleRefresh($db,$body),
    $method==='POST' && $action==='logout'              => handleLogout($db),
    $method==='POST' && $action==='forgot-password'     => handleForgotPassword($db,$body,$ip),
    $method==='POST' && $action==='reset-password'      => handleResetPassword($db,$body),
    $method==='GET'  && $action==='verify-email'        => handleVerifyEmail($db),
    $method==='POST' && $action==='resend-verification' => handleResendVerification($db,$body,$ip),
    default => respond(404,false,'Endpoint not found'),
};


function handleRegister(PDO $db, array $body, string $ip): void {
    RateLimiter::register($ip);
    $username = trim($body["username"] ?? "");
    $email    = strtolower(trim($body["email"] ?? ""));
    $password = $body["password"] ?? "";
    $errors   = [];
    if (strlen($username) < 3 || strlen($username) > 50) $errors[] = "Username must be 3-50 characters.";
    if (!preg_match("/^[a-zA-Z0-9_.\\-]+$/", $username)) $errors[] = "Username: letters, numbers, _ . - only.";
    if (!filter_var($email, FILTER_VALIDATE_EMAIL)) $errors[] = "Invalid email address.";
    if (strlen($password) < 8) $errors[] = "Password must be at least 8 characters.";
    if (!preg_match("/[A-Z]/", $password)) $errors[] = "Password needs an uppercase letter.";
    if (!preg_match("/[0-9]/", $password)) $errors[] = "Password needs a number.";
    if ($errors) { respond(422, false, implode(" ", $errors)); return; }
    $chk = $db->prepare("SELECT id FROM users WHERE email = ? OR username = ? LIMIT 1");
    $chk->execute([$email, $username]);
    if ($chk->fetch()) { respond(409, false, "Email or username already registered."); return; }
    $hash    = password_hash($password, PASSWORD_BCRYPT, ["cost" => 12]);
    $tok     = bin2hex(random_bytes(32));
    $tokHash = hash("sha256", $tok);
    $sql = "INSERT INTO users (username, email, password_hash, coins, email_verify_token, email_verify_expires) VALUES (?, ?, ?, 100, ?, NOW() + '24 hours'::interval) RETURNING id, uuid, username, email, coins, streak_days, current_level, total_score, created_at, is_verified";
    $stmt = $db->prepare($sql);
    $stmt->execute([$username, $email, $hash, $tokHash]);
    $user = $stmt->fetch();
    if (!$user) { respond(500, false, "Registration failed."); return; }
    $seed = $db->prepare("INSERT INTO user_level_progress (user_id, level) VALUES (?, ?) ON CONFLICT DO NOTHING");
    foreach (["N5","N4","N3","N2","N1"] as $l) {
        $seed->execute([(int)$user["id"], $l]);
    }
    try { try { Mailer::sendVerification($email, $username, $tok); } catch (\Exception $e) { error_log("Mail error: " . $e->getMessage()); } } catch (\Exception $e) { error_log("Mail error: " . $e->getMessage()); }
    [$access, $refresh] = issueTokens($db, (int)$user["id"], $user["username"]);
    respond(201, true, "Account created. Check your email to verify your address.", [
        "user"           => $user,
        "access_token"   => $access,
        "refresh_token"  => $refresh,
        "email_verified" => false,
    ]);
}

function handleVerifyEmail(PDO $db): void {
    $token=$_GET['token']??'';
    if (!$token) { respond(422,false,'Token required.'); return; }
    $hash=hash('sha256',$token);
    $stmt=$db->prepare('UPDATE users SET is_verified=TRUE,email_verify_token=NULL,email_verify_expires=NULL
        WHERE email_verify_token=? AND email_verify_expires>NOW() AND is_verified=FALSE
        RETURNING id,username,email');
    $stmt->execute([$hash]);
    $user=$stmt->fetch();
    header('Content-Type: text/html; charset=utf-8');
    if (!$user) {
        http_response_code(400);
        echo '<html><body style="font-family:sans-serif;text-align:center;padding:60px">
            <h2 style="color:#CC0000">Link expired or already used</h2>
            <p>Request a new verification email from the app.</p></body></html>'; return;
    }
    Mailer::sendWelcome($user['email'],$user['username']);
    echo '<html><head><meta http-equiv="refresh" content="3;url=nipinomanabu://email-verified"></head>
        <body style="font-family:sans-serif;text-align:center;padding:60px">
        <h2 style="color:#1A7A3C">&#10003; Email verified!</h2>
        <p>Opening Nipino-Manabu...</p></body></html>';
}

function handleResendVerification(PDO $db, array $body, string $ip): void {
    RateLimiter::enforce($ip,'resend_verify',3,3600);
    $email=Auth::sanitizeEmail($body['email']??'');
    $stmt=$db->prepare('SELECT id,username,is_verified FROM users WHERE email=? AND is_active=TRUE');
    $stmt->execute([$email]);
    $user=$stmt->fetch();
    if (!$user||$user['is_verified']) { respond(200,true,'If unverified, a new link was sent.'); return; }
    $tok=bin2hex(random_bytes(32)); $tokHash=hash('sha256',$tok);
    $db->prepare("UPDATE users SET email_verify_token=?,email_verify_expires=NOW() + '24 hours'::interval WHERE id=?")
        ->execute([$tokHash,$user['id']]);
    Mailer::sendVerification($email,$user['username'],$tok);
    respond(200,true,'If unverified, a new link was sent.');
}

function handleLogin(PDO $db, array $body, string $ip): void {
    $email=Auth::sanitizeEmail($body['email']??'');
    RateLimiter::login($ip,$email);
    $password=$body['password']??'';
    if (!$email||!$password) { respond(422,false,'Email and password required.'); return; }
    $stmt=$db->prepare('SELECT id,uuid,username,email,password_hash,coins,streak_days,
        current_level,total_score,is_active,is_verified,last_quiz_date,created_at FROM users WHERE email=? LIMIT 1');
    $stmt->execute([$email]);
    $user=$stmt->fetch();
    $dummy='?y?$invalidhashtopreventtimingattackXXXXXXXXXXXXXXXXXXXXX';
    $valid=Auth::verifyPassword($password,$user?$user['password_hash']:$dummy);
    if (!$user||!$valid) { respond(401,false,'Invalid email or password.'); return; }
    if (!$user['is_active']) { respond(403,false,'Account suspended. Contact support.'); return; }
    updateStreak($db,(int)$user['id'],$user['last_quiz_date']);
    [$access,$refresh]=issueTokens($db,(int)$user['id'],$user['username']);
    $fresh=$db->prepare('SELECT id,uuid,username,email,coins,streak_days,current_level,total_score,is_verified,created_at FROM users WHERE id=?');
    $fresh->execute([$user['id']]);
    $u=$fresh->fetch();
    $resp=['user'=>formatUser($u),'access_token'=>$access,'refresh_token'=>$refresh,'email_verified'=>(bool)$u['is_verified']];
    if (!$u['is_verified']) $resp['warning']='Please verify your email to unlock all features.';
    respond(200,true,'Login successful.',$resp);
}

function handleForgotPassword(PDO $db, array $body, string $ip): void {
    $email=Auth::sanitizeEmail($body['email']??'');
    RateLimiter::passwordReset($ip,$email);
    $stmt=$db->prepare('SELECT id,username,is_active FROM users WHERE email=? LIMIT 1');
    $stmt->execute([$email]);
    $user=$stmt->fetch();
    if (!$user||!$user['is_active']) { respond(200,true,'If registered, a reset link was sent.'); return; }
    $db->prepare('UPDATE password_reset_tokens SET used=TRUE WHERE user_id=? AND used=FALSE')
        ->execute([$user['id']]);
    $tok=bin2hex(random_bytes(32)); $tokHash=hash('sha256',$tok);
    $db->prepare("INSERT INTO password_reset_tokens (user_id,token_hash,expires_at) VALUES (?,?,NOW() + '1 hour'::interval)")
        ->execute([$user['id'],$tokHash]);
    Mailer::sendPasswordReset($email,$user['username'],$tok);
    respond(200,true,'If registered, a reset link was sent.');
}

function handleResetPassword(PDO $db, array $body): void {
    $token=$body['token']??''; $password=$body['password']??'';
    if (!$token||strlen($password)<8) { respond(422,false,'Token and password (8+ chars) required.'); return; }
    if (!preg_match('/[A-Z]/',$password)||!preg_match('/[0-9]/',$password))
        { respond(422,false,'Password needs an uppercase letter and a number.'); return; }
    $tokHash=hash('sha256',$token);
    $stmt=$db->prepare('SELECT prt.id,prt.user_id,u.email,u.username FROM password_reset_tokens prt
        JOIN users u ON u.id=prt.user_id
        WHERE prt.token_hash=? AND prt.expires_at>NOW() AND prt.used=FALSE AND u.is_active=TRUE LIMIT 1');
    $stmt->execute([$tokHash]);
    $row=$stmt->fetch();
    if (!$row) { respond(400,false,'Link invalid or expired. Request a new one.'); return; }
    $db->beginTransaction();
    try {
        $db->prepare('UPDATE users SET password_hash=? WHERE id=?')
           ->execute([Auth::hashPassword($password),$row['user_id']]);
        $db->prepare('UPDATE password_reset_tokens SET used=TRUE WHERE id=?')
           ->execute([$row['id']]);
        $db->prepare('UPDATE refresh_tokens SET revoked_at=NOW() WHERE user_id=? AND revoked_at IS NULL')
           ->execute([$row['user_id']]);
        $db->commit();
    } catch(\Exception $e) {
        $db->rollBack();
        error_log('PW reset error: '.$e->getMessage());
        respond(500,false,'Reset failed. Try again.'); return;
    }
    respond(200,true,'Password updated. Please sign in with your new password.');
}

function handleRefresh(PDO $db, array $body): void {
    $raw=$body['refresh_token']??'';
    if (!$raw) { respond(401,false,'Refresh token required.'); return; }
    $hash=hash('sha256',$raw);
    $stmt=$db->prepare('SELECT rt.id,rt.user_id,u.username FROM refresh_tokens rt
        JOIN users u ON u.id=rt.user_id
        WHERE rt.token_hash=? AND rt.revoked_at IS NULL AND rt.expires_at>NOW() AND u.is_active=TRUE LIMIT 1');
    $stmt->execute([$hash]);
    $row=$stmt->fetch();
    if (!$row) { respond(401,false,'Invalid or expired refresh token.'); return; }
    $db->prepare('UPDATE refresh_tokens SET revoked_at=NOW() WHERE id=?')->execute([$row['id']]);
    [$access,$refresh]=issueTokens($db,(int)$row['user_id'],$row['username']);
    respond(200,true,'Tokens refreshed.',['access_token'=>$access,'refresh_token'=>$refresh]);
}

function handleLogout(PDO $db): void {
    $claims=Auth::requireAuth();
    $db->prepare('UPDATE refresh_tokens SET revoked_at=NOW() WHERE user_id=? AND revoked_at IS NULL')
       ->execute([(int)$claims['sub']]);
    respond(200,true,'Logged out.');
}

function issueTokens(PDO $db, int $uid, string $uname): array {
    $cfg=require dirname(__DIR__).'/config/config.php';
    $access=Auth::generateAccessToken($uid,$uname);
    $raw=Auth::generateRefreshToken(); $hash=hash('sha256',$raw);
    $exp=date('Y-m-d H:i:s',time()+$cfg['jwt']['refresh_ttl']);
    $db->prepare('INSERT INTO refresh_tokens (user_id,token_hash,expires_at) VALUES (?,?,?)')
       ->execute([$uid,$hash,$exp]);
    return [$access,$raw];
}

function updateStreak(PDO $db, int $uid, ?string $last): void {
    $today=date('Y-m-d'); $yday=date('Y-m-d',strtotime('-1 day'));
    if ($last===$today) return;
    $db->prepare($last===$yday
        ? 'UPDATE users SET streak_days=streak_days+1,last_quiz_date=? WHERE id=?'
        : 'UPDATE users SET streak_days=1,last_quiz_date=? WHERE id=?')
       ->execute([$today,$uid]);
}

function formatUser(array $u): array {
    return ['id'=>(int)$u['id'],'username'=>$u['username'],'email'=>$u['email'],
            'coins'=>(int)$u['coins'],'streak_days'=>(int)$u['streak_days'],
            'current_level'=>$u['current_level'],'total_score'=>(int)$u['total_score'],
            'is_verified'=>(bool)($u['is_verified']??false),'created_at'=>$u['created_at']];
}

function respond(int $code, bool $ok, string $msg, array $data=[]): void {
    http_response_code($code);
    echo json_encode(array_merge(['success'=>$ok,'message'=>$msg],$data),JSON_UNESCAPED_UNICODE);
}
