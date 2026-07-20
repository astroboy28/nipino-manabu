#!/usr/bin/env php
<?php
// backend/cron/healthcheck_alert.php
// Crontab: */2 * * * * /usr/bin/php /var/www/nipino-manabu/backend/cron/healthcheck_alert.php >> /var/log/nipino_healthcheck.log 2>&1
//
// Hits the public HTTPS /health endpoint (not an in-process DB/Redis check)
// so this also catches Apache/SSL/routing being down, not just the database.
// Alerts only on a state CHANGE (healthy -> down, down -> healthy), gated by
// a few consecutive failures first, so one network blip doesn't page anyone
// and a real outage doesn't spam an email per check either.
declare(strict_types=1);

if (PHP_SAPI !== 'cli') { http_response_code(403); exit('Forbidden'); }

$envFile = dirname(__DIR__) . '/.env';
if (file_exists($envFile)) {
    foreach (file($envFile, FILE_IGNORE_NEW_LINES|FILE_SKIP_EMPTY_LINES) as $line) {
        if (str_starts_with(trim($line), '#')) continue;
        [$k, $v] = explode('=', $line, 2) + [1 => ''];
        $_ENV[trim($k)] = trim($v);
        putenv(trim($k) . '=' . trim($v));
    }
}
require_once dirname(__DIR__) . '/email/Mailer.php';

$log = fn(string $m) => print('[' . date('Y-m-d H:i:s') . '] ' . $m . PHP_EOL);

$healthUrl     = $_ENV['HEALTHCHECK_URL'] ?? 'https://api.nipino-manabu.com/health';
$alertEmail    = $_ENV['OPS_ALERT_EMAIL'] ?? '';
$stateFile     = '/root/.nipino_health_state.json';
$failThreshold = 2; // consecutive failing checks (~4 min at a 2-min cron) before alerting

$state = ['consecutive_failures' => 0, 'alerted' => false];
if (is_file($stateFile)) {
    $decoded = json_decode((string) file_get_contents($stateFile), true);
    if (is_array($decoded)) $state = array_merge($state, $decoded);
}

$ch = curl_init($healthUrl);
curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_TIMEOUT        => 10,
    CURLOPT_CONNECTTIMEOUT => 5,
]);
$res  = curl_exec($ch);
$err  = curl_error($ch);
$code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

$body    = $res !== false ? json_decode((string) $res, true) : null;
$healthy = $code === 200 && is_array($body) && ($body['ok'] ?? false) === true;

if ($healthy) {
    $log("OK ($code)");
    if ($state['alerted']) {
        $log('Recovered — sending recovery notice');
        if ($alertEmail) {
            Mailer::sendOpsAlert($alertEmail, '✅ Nipino-Manabu API recovered',
                "The health check at $healthUrl is passing again as of " . date('c') . ".\n\n"
                . "It had failed {$state['consecutive_failures']} consecutive check(s) before this.");
        }
    }
    $state = ['consecutive_failures' => 0, 'alerted' => false];
} else {
    $reason = $err ?: ("HTTP $code" . ($body ? ' — ' . json_encode($body) : ' — no/invalid response body'));
    $state['consecutive_failures']++;
    $log("FAIL ({$state['consecutive_failures']}): $reason");

    if ($state['consecutive_failures'] >= $failThreshold && !$state['alerted']) {
        $log('Threshold reached — sending alert');
        if ($alertEmail) {
            Mailer::sendOpsAlert($alertEmail, '🚨 Nipino-Manabu API is down',
                "Health check at $healthUrl has failed {$state['consecutive_failures']} consecutive time(s).\n\n"
                . "Last error: $reason\n"
                . "Checked at: " . date('c') . "\n\n"
                . "First steps:\n"
                . "  ssh nipino \"sudo systemctl status apache2 postgresql redis-server\"\n"
                . "  ssh nipino \"sudo tail -50 /var/log/apache2/nipino-error.log\"\n");
        } else {
            $log('OPS_ALERT_EMAIL not set in .env — no alert sent');
        }
        $state['alerted'] = true;
    }
}

file_put_contents($stateFile, json_encode($state));
