#!/usr/bin/env php
<?php
// backend/cron/weekly_leaderboard.php — weekly leaderboard archive + notification
// Crontab: 20 0 * * 1 /usr/bin/php /var/www/nipino-manabu/backend/cron/weekly_leaderboard.php >> /var/log/nipino_cron.log 2>&1
//
// Runs once a week (Monday, after daily.php's 00:05 refresh_leaderboard()
// call). Since migration 019, 'weekly' in leaderboard_snapshots is a real
// calendar-week bucket that resets every Monday -- this script computes last
// week's final standings directly from quiz_results (independent of whatever
// the snapshot table currently holds, so it doesn't matter whether this runs
// before or after the day's refresh), archives them permanently to
// leaderboard_history, and tells rank #2-10 exactly how many points
// separated them from the rank above.
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
    // The week that just ended: [last Monday 00:00, this Monday 00:00).
    $rows = $db->query(
        "SELECT u.id AS user_id, u.username, u.fcm_token,
                COALESCE(SUM(qr.correct_count * 10), 0) AS total_score,
                COALESCE(AVG(qr.score_percent), 0) AS accuracy,
                ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(qr.correct_count * 10), 0) DESC) AS rank_pos
         FROM users u
         JOIN quiz_results qr ON qr.user_id = u.id
           AND qr.taken_at >= (date_trunc('week', NOW() AT TIME ZONE 'Asia/Tokyo') AT TIME ZONE 'Asia/Tokyo') - INTERVAL '7 days'
           AND qr.taken_at <  (date_trunc('week', NOW() AT TIME ZONE 'Asia/Tokyo') AT TIME ZONE 'Asia/Tokyo')
         WHERE u.is_active = TRUE
         GROUP BY u.id
         HAVING COALESCE(SUM(qr.correct_count * 10), 0) > 0
         ORDER BY total_score DESC
         LIMIT 10"
    )->fetchAll();

    if (!$rows) {
        $log('No quiz activity last week — nothing to archive or notify.');
    } else {
        // Cast the JST wall-clock timestamp (not a re-converted timestamptz)
        // to ::date directly, so the date isn't shifted by the session's
        // forced UTC timezone (see Database.php).
        $periodStart = $db->query("SELECT (date_trunc('week', NOW() AT TIME ZONE 'Asia/Tokyo') - INTERVAL '7 days')::date AS d")->fetch()['d'];
        $periodEnd   = $db->query("SELECT date_trunc('week', NOW() AT TIME ZONE 'Asia/Tokyo')::date AS d")->fetch()['d'];

        $ins = $db->prepare(
            'INSERT INTO leaderboard_history (period_start, period_end, user_id, rank_pos, total_score, accuracy)
             VALUES (?,?,?,?,?,?)
             ON CONFLICT (period_start, user_id) DO UPDATE
               SET rank_pos=EXCLUDED.rank_pos, total_score=EXCLUDED.total_score, accuracy=EXCLUDED.accuracy'
        );
        foreach ($rows as $r) {
            $ins->execute([$periodStart, $periodEnd, $r['user_id'], $r['rank_pos'], $r['total_score'], $r['accuracy']]);
        }
        $log("Archived {$periodStart} to {$periodEnd}: ".count($rows).' ranked users');

        $sent = 0; $failed = 0; $notified = 0;
        foreach ($rows as $i => $r) {
            if (!$r['fcm_token']) continue;
            $notified++;
            if ((int)$r['rank_pos'] === 1) {
                $title = '🥇 #1 on last week\'s leaderboard!';
                $body  = "You finished #1 last week, {$r['username']}. This week just started — defend it!";
            } else {
                $gap = (int)$rows[$i - 1]['total_score'] - (int)$r['total_score'];
                $title = "🏁 Last week you finished #{$r['rank_pos']}";
                $body  = $gap > 0
                    ? "Only {$gap} points behind #".((int)$r['rank_pos']-1)." last week. This week's leaderboard just reset — go close the gap!"
                    : "Tied for #{$r['rank_pos']} last week. This week's leaderboard just reset — break the tie!";
            }
            $ok = FCM::sendToToken($r['fcm_token'], $title, $body,
                ['type' => 'leaderboard', 'rank' => (string)$r['rank_pos'], 'screen' => 'leaderboard']);
            if ($ok) $sent++; else $failed++;
        }
        $log("Notifications: {$sent} sent, {$failed} failed, {$notified} had a registered device");
    }
} catch (\Throwable $e) { $log('ERROR: '.$e->getMessage()); }

$log('=== Weekly Leaderboard Cron END ===');
