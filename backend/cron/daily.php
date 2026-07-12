#!/usr/bin/env php
<?php
// backend/cron/daily.php — FINAL with deletion execution
// Crontab: 5 0 * * * /usr/bin/php /var/www/nipino-manabu/backend/cron/daily.php >> /var/log/nipino_cron.log 2>&1
declare(strict_types=1);

// CLI-only. Nothing in the web server config routes to this file, but that's
// the only thing stopping a direct HTTP hit from repeatedly re-running
// scheduled-deletion / notification logic — enforce it here too so it's not
// solely dependent on .htaccess/vhost config staying correct.
if (PHP_SAPI !== 'cli') {
    http_response_code(403);
    exit('Forbidden');
}

$envFile = dirname(__DIR__) . '/.env';
if (file_exists($envFile)) {
    foreach (file($envFile, FILE_IGNORE_NEW_LINES|FILE_SKIP_EMPTY_LINES) as $line) {
        if (str_starts_with(trim($line),'#')) continue;
        [$k,$v] = explode('=',$line,2)+[1=>''];
        $_ENV[trim($k)]=trim($v); putenv(trim($k).'='.trim($v));
    }
}
require_once dirname(__DIR__).'/config/Database.php';
require_once dirname(__DIR__).'/email/FCM.php';
require_once dirname(__DIR__).'/email/Mailer.php';
$db = Database::connect();
$log = fn(string $m) => print('['.date('Y-m-d H:i:s').'] '.$m.PHP_EOL);
$log('=== Nipino-Manabu Daily Cron START ===');
// 1. Token cleanup
try { $db->exec('SELECT cleanup_expired_tokens()'); $log('Token cleanup: OK'); }
catch(\Throwable $e){ $log('Token cleanup ERROR: '.$e->getMessage()); }
// 2. Log purge
try { $db->exec('SELECT purge_old_logs()'); $log('Log purge: OK'); }
catch(\Throwable $e){ $log('Log purge ERROR: '.$e->getMessage()); }
// 3. Execute scheduled deletions
try {
    $r=$db->query('SELECT execute_scheduled_deletions() AS count');
    $n=(int)($r->fetch()['count']??0);
    $log("Scheduled deletions: {$n} accounts permanently deleted");
} catch(\Throwable $e){ $log('Deletions ERROR: '.$e->getMessage()); }
// 4. Streak reminders
try {
    $stmt=$db->prepare('SELECT u.id,u.username,u.email,u.streak_days,u.fcm_token FROM users u
        WHERE u.last_quiz_date=CURRENT_DATE-INTERVAL \'1 day\'
          AND u.streak_days>=2 AND u.is_active=TRUE
          AND u.deletion_scheduled_at IS NULL LIMIT 5000');
    $stmt->execute(); $users=$stmt->fetchAll();
    $pushed=0; $emailed=0;
    foreach($users as $u){
        if($u['fcm_token'] && FCM::streakReminder($u['fcm_token'],(int)$u['streak_days'])) $pushed++;
        if((int)$u['streak_days']>=7){ Mailer::sendStreakReminder($u['email'],$u['username'],(int)$u['streak_days']); $emailed++; }
        $db->prepare('INSERT INTO notification_log (user_id,type,title,body) VALUES (?,?,?,?)')
           ->execute([$u['id'],'streak_reminder','Streak reminder',$u['streak_days'].'-day streak at risk']);
    }
    $log("Streak reminders: {$pushed} push, {$emailed} email, ".count($users).' users');
} catch(\Throwable $e){ $log('Streak ERROR: '.$e->getMessage()); }
// 5. Leaderboard
try {
    $db->exec('SELECT refresh_leaderboard()'); $log('Leaderboard refresh: OK');
    $top=$db->query("SELECT ls.rank_pos AS rank,u.fcm_token,u.username
        FROM leaderboard_snapshots ls JOIN users u ON u.id=ls.user_id
        WHERE ls.period='weekly' AND ls.level IS NULL AND ls.rank_pos<=10
          AND u.fcm_token IS NOT NULL AND u.is_active=TRUE")->fetchAll();
    foreach($top as $r) FCM::weeklyLeaderboard($r['fcm_token'],$r['username'],(int)$r['rank']);
    $log('Leaderboard notifications: '.count($top).' sent');
} catch(\Throwable $e){ $log('Leaderboard ERROR: '.$e->getMessage()); }
$log('=== Daily Cron END ===');
