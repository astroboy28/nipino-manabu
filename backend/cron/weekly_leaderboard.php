#!/usr/bin/env php
<?php
// backend/cron/weekly_leaderboard.php — weekly leaderboard wrap-up notification
// Crontab: 20 0 * * 1 /usr/bin/php /var/www/nipino-manabu/backend/cron/weekly_leaderboard.php >> /var/log/nipino_cron.log 2>&1
//
// Runs once a week (Monday, after daily.php's 00:05 refresh_leaderboard()
// call so the snapshot is current). Distinct from the daily top-10 "Weekly
// results are in!" ping already sent by daily.php (backend/cron/daily.php
// step 5) -- that one repeats the same generic message every day. This one
// fires once a week and tells rank #2-#10 exactly how many points separate
// them from the rank above, to nudge people back in before the rolling
// 7-day window moves past their best score.
declare(strict_types=1);

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
$db  = Database::connect();
$log = fn(string $m) => print('['.date('Y-m-d H:i:s').'] '.$m.PHP_EOL);
$log('=== Weekly Leaderboard Cron START ===');

try {
    $rows = $db->query(
        "SELECT ls.rank_pos, ls.total_score, u.username, u.fcm_token
         FROM leaderboard_snapshots ls JOIN users u ON u.id=ls.user_id
         WHERE ls.period='weekly' AND ls.level IS NULL AND ls.rank_pos<=10
           AND u.fcm_token IS NOT NULL AND u.is_active=TRUE
         ORDER BY ls.rank_pos ASC"
    )->fetchAll();

    $sent = 0; $failed = 0;
    foreach ($rows as $i => $r) {
        if ((int)$r['rank_pos'] === 1) {
            $title = '🥇 #1 on the weekly leaderboard!';
            $body  = "You're leading this week, {$r['username']}. Defend your spot!";
        } else {
            $gap = (int)$rows[$i - 1]['total_score'] - (int)$r['total_score'];
            $title = "🏁 Weekly leaderboard: #{$r['rank_pos']}";
            $body  = $gap > 0
                ? "You're #{$r['rank_pos']} this week, only {$gap} points behind #".((int)$r['rank_pos']-1).". One more quiz could close the gap!"
                : "You're #{$r['rank_pos']} this week, tied with #".((int)$r['rank_pos']-1).". Break the tie!";
        }
        $ok = FCM::sendToToken($r['fcm_token'], $title, $body,
            ['type' => 'leaderboard', 'rank' => (string)$r['rank_pos'], 'screen' => 'leaderboard']);
        if ($ok) $sent++; else $failed++;
    }
    $log("Weekly leaderboard notifications: {$sent} sent, {$failed} failed, ".count($rows).' eligible');
} catch (\Throwable $e) { $log('ERROR: '.$e->getMessage()); }

$log('=== Weekly Leaderboard Cron END ===');
