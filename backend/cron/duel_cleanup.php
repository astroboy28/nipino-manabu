#!/usr/bin/env php
<?php
// backend/cron/duel_cleanup.php
// Crontab: */5 * * * * /usr/bin/php /var/www/nipino-manabu/backend/cron/duel_cleanup.php >> /var/log/nipino_cron.log 2>&1
//
// Sweeps duel rooms that were never going to finish on their own:
//   - 'waiting' rooms past expires_at (nobody joined in time) — refunds bets.
//   - 'active' rooms abandoned mid-duel (see migration 009) — forfeits
//     whoever didn't finish and finalizes the room.
// Runs every 5 minutes (not daily, like daily.php) because a stuck duel
// otherwise locks both players' wagered coins for up to 2 hours.
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
$db  = Database::connect();
$log = fn(string $m) => print('['.date('Y-m-d H:i:s').'] '.$m.PHP_EOL);

$log('=== Nipino-Manabu Duel Cleanup START ===');

try {
    $r = $db->query('SELECT expire_duel_rooms() AS count');
    $n = (int)($r->fetch()['count'] ?? 0);
    $log("Expired waiting rooms: {$n}");
} catch (\Throwable $e) { $log('expire_duel_rooms ERROR: '.$e->getMessage()); }

try {
    $r = $db->query('SELECT expire_stale_active_duels() AS count');
    $n = (int)($r->fetch()['count'] ?? 0);
    $log("Finalized stale active duels: {$n}");
} catch (\Throwable $e) { $log('expire_stale_active_duels ERROR: '.$e->getMessage()); }

$log('=== Duel Cleanup END ===');
