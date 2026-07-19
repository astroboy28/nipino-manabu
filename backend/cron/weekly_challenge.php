#!/usr/bin/env php
<?php
// backend/cron/weekly_challenge.php — challenge_events lifecycle + auto-creation
// Crontab: 10 * * * * /usr/bin/php /var/www/nipino-manabu/backend/cron/weekly_challenge.php >> /var/log/nipino_cron.log 2>&1
//
// Runs hourly and does three things:
//  1. Activate: upcoming -> active once starts_at has passed (nothing else
//     in the app ever did this, so every challenge sat as "upcoming" forever
//     — see handleUpdate() in api/challenge.php for the only other writer of
//     this column).
//  2. Finalize: active -> finished once ends_at has passed, picking a winner
//     and paying out the prize. Mirrors handleAdminFinalize() in
//     api/challenge.php since that function isn't reusable from a CLI
//     script (challenge.php dispatches on load).
//  3. Auto-create: if no challenge is upcoming/active, create a new one for
//     the next 7 days so the Home screen's FeaturedChallengeBanner isn't
//     empty most of the time, rotating level/category by ISO week number.
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
$log('=== Weekly Challenge Cron START ===');

// ── 1. Activate ─────────────────────────────────────────────────────────────
try {
    $n = $db->exec(
        "UPDATE challenge_events SET status='active'
         WHERE status='upcoming' AND starts_at<=NOW()"
    );
    $log("Activated: {$n} challenge(s)");
} catch (\Throwable $e) { $log('Activate ERROR: '.$e->getMessage()); }

// ── 2. Finalize ──────────────────────────────────────────────────────────────
try {
    $expired = $db->query(
        "SELECT id, title, prize_coins, prize_badge_name, prize_badge_emoji
         FROM challenge_events WHERE status='active' AND ends_at<=NOW()"
    )->fetchAll();

    $finalized = 0;
    foreach ($expired as $event) {
        $eventId = (int)$event['id'];
        $winnerStmt = $db->prepare(
            'SELECT cp.user_id, u.username
             FROM challenge_participants cp
             JOIN users u ON u.id=cp.user_id
             WHERE cp.event_id=? AND cp.completed_at IS NOT NULL
             ORDER BY cp.score DESC, cp.time_taken_ms ASC
             LIMIT 1'
        );
        $winnerStmt->execute([$eventId]);
        $winner = $winnerStmt->fetch();

        $db->beginTransaction();
        try {
            if ($winner) {
                $db->prepare('UPDATE users SET coins=coins+? WHERE id=?')
                   ->execute([$event['prize_coins'], $winner['user_id']]);

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

                if ($event['prize_badge_name']) {
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

                $rankStmt = $db->prepare(
                    'SELECT user_id FROM challenge_participants
                     WHERE event_id=? AND completed_at IS NOT NULL
                     ORDER BY score DESC, time_taken_ms ASC'
                );
                $rankStmt->execute([$eventId]);
                $updRank = $db->prepare(
                    'UPDATE challenge_participants SET rank_pos=?, coins_awarded=?
                     WHERE event_id=? AND user_id=?'
                );
                foreach ($rankStmt->fetchAll() as $rank => $row) {
                    $award = $rank === 0 ? (int)$event['prize_coins'] : 0;
                    $updRank->execute([$rank + 1, $award, $eventId, $row['user_id']]);
                }
            }

            $db->prepare(
                'UPDATE challenge_events
                 SET status=\'finished\', winner_user_id=?, featured=TRUE, finished_at=NOW()
                 WHERE id=?'
            )->execute([$winner['user_id'] ?? null, $eventId]);

            $db->commit();
            $finalized++;
        } catch (\Throwable $e) {
            $db->rollBack();
            $log("Finalize ERROR (event {$eventId}): ".$e->getMessage());
        }
    }
    $log("Finalized: {$finalized} of ".count($expired).' expired challenge(s)');
} catch (\Throwable $e) { $log('Finalize query ERROR: '.$e->getMessage()); }

// ── 3. Auto-create ────────────────────────────────────────────────────────────
try {
    $pending = $db->query(
        "SELECT COUNT(*) AS c FROM challenge_events WHERE status IN ('upcoming','active')"
    )->fetch();

    if ((int)($pending['c'] ?? 0) === 0) {
        $admin = $db->query('SELECT id FROM users WHERE is_admin=TRUE ORDER BY id LIMIT 1')->fetch();
        if (!$admin) {
            $log('Auto-create SKIPPED: no admin user found to own the event');
        } else {
            $levels = ['N5','N4','N3','N2','N1'];
            $cats   = ['kanji','vocabulary','grammar','listening'];
            $week   = (int)date('W');
            $level  = $levels[$week % count($levels)];
            $cat    = $cats[intdiv($week, count($levels)) % count($cats)];
            $prizeCoins = 200;

            $stmt = $db->prepare(
                'INSERT INTO challenge_events
                 (title, description, created_by_id, level, category,
                  question_count, seconds_per_q, prize_coins, featured,
                  status, max_participants, starts_at, ends_at)
                 VALUES (?,?,?,?,?,15,20,?,TRUE,\'active\',1000,NOW(),NOW() + INTERVAL \'7 days\')
                 RETURNING id, title'
            );
            $stmt->execute([
                "Weekly Challenge — ".ucfirst($cat)." ({$level})",
                "This week's community challenge! Answer 15 {$cat} questions ".
                "correctly and fastest at {$level} level to win {$prizeCoins} coins.",
                (int)$admin['id'], $level, $cat, $prizeCoins,
            ]);
            $created = $stmt->fetch();
            $log("Auto-created challenge {$created['id']}: {$created['title']}");

            $tokens = $db->query(
                "SELECT fcm_token FROM users WHERE is_active=TRUE AND fcm_token IS NOT NULL LIMIT 10000"
            )->fetchAll(\PDO::FETCH_COLUMN);
            if ($tokens) {
                $result = FCM::sendToTokens(
                    $tokens,
                    "🏆 New challenge: {$created['title']}",
                    "Prize: {$prizeCoins} coins. Tap to join!",
                    ['type' => 'challenge_invite', 'event_id' => (string)$created['id'], 'screen' => 'challenge']
                );
                $log("Push notified: {$result['sent']} sent, {$result['failed']} failed");
            }
        }
    } else {
        $log('Auto-create SKIPPED: a challenge is already upcoming/active');
    }
} catch (\Throwable $e) { $log('Auto-create ERROR: '.$e->getMessage()); }

$log('=== Weekly Challenge Cron END ===');
