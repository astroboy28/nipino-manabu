<?php
// backend/middleware/Monitor.php
// ─── Structured error monitoring + alerting ───────────────────────────────────
declare(strict_types=1);

class Monitor {
    private static ?PDO $db = null;

    private static function db(): ?PDO {
        if (self::$db) return self::$db;
        try {
            require_once dirname(__DIR__) . '/config/Database.php';
            self::$db = Database::connect();
        } catch (\Throwable $e) {
            // If DB is down, fall back to file logging only
        }
        return self::$db;
    }

    // ── Log levels ────────────────────────────────────────────────────────────
    public static function error(string $context, string $message,
        array $meta = [], ?int $userId = null): void
    {
        self::log('error', $context, $message, $meta, $userId);
    }

    public static function warn(string $context, string $message,
        array $meta = [], ?int $userId = null): void
    {
        self::log('warn', $context, $message, $meta, $userId);
    }

    public static function info(string $context, string $message,
        array $meta = [], ?int $userId = null): void
    {
        self::log('info', $context, $message, $meta, $userId);
    }

    // ── Core log method ───────────────────────────────────────────────────────
    private static function log(string $level, string $context,
        string $message, array $meta, ?int $userId): void
    {
        $ip = $_SERVER['REMOTE_ADDR'] ?? null;

        // Always write to error_log (Apache/PHP log)
        $logLine = sprintf(
            '[%s] %s [%s] %s | meta:%s | user:%s | ip:%s',
            strtoupper($level), date('Y-m-d H:i:s'), $context,
            $message, json_encode($meta), $userId ?? 'anon', $ip ?? 'unknown'
        );
        error_log($logLine);

        // Write to DB (non-fatal if fails)
        try {
            $db = self::db();
            if ($db) {
                $db->prepare(
                    'INSERT INTO error_log (level,context,message,meta,user_id,ip_address)
                     VALUES (?,?,?,?,?,?::inet)'
                )->execute([
                    $level,
                    substr($context, 0, 100),
                    $message,
                    json_encode($meta),
                    $userId,
                    $ip,
                ]);
            }
        } catch (\Throwable $e) {
            error_log('Monitor DB write failed: ' . $e->getMessage());
        }

        // Alert on errors (email/Slack webhook)
        if ($level === 'error') {
            self::alert($context, $message, $meta);
        }
    }

    // ── Alert (Slack webhook or email) ────────────────────────────────────────
    private static function alert(string $context, string $message, array $meta): void {
        $webhookUrl = $_ENV['SLACK_WEBHOOK_URL'] ?? '';
        if (!$webhookUrl) return;

        $cfg = require dirname(__DIR__) . '/config/config.php';
        if ($cfg['app']['env'] !== 'production') return; // Only alert in production

        $payload = json_encode([
            'text' => null,
            'blocks' => [[
                'type' => 'section',
                'text' => ['type' => 'mrkdwn',
                    'text' => "*🚨 Nipino-Manabu Error*\n"
                        . "*Context:* $context\n"
                        . "*Message:* $message\n"
                        . "*Time:* " . date('Y-m-d H:i:s') . " UTC\n"
                        . "*Server:* " . ($_SERVER['SERVER_NAME'] ?? 'unknown'),
                ],
            ]],
        ]);

        $ch = curl_init($webhookUrl);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_POST           => true,
            CURLOPT_POSTFIELDS     => $payload,
            CURLOPT_HTTPHEADER     => ['Content-Type: application/json'],
            CURLOPT_TIMEOUT        => 5,
        ]);
        curl_exec($ch);
        curl_close($ch);
    }

    // ── Register global error/exception handlers ──────────────────────────────
    public static function register(): void {
        set_error_handler(function (int $errno, string $errstr,
            string $errfile, int $errline): bool
        {
            if (!(error_reporting() & $errno)) return false;
            self::error('php_error', $errstr,
                ['errno' => $errno, 'file' => $errfile, 'line' => $errline]);
            return false;
        });

        set_exception_handler(function (\Throwable $e): void {
            self::error('uncaught_exception', $e->getMessage(), [
                'class' => get_class($e),
                'file'  => $e->getFile(),
                'line'  => $e->getLine(),
                'trace' => substr($e->getTraceAsString(), 0, 500),
            ]);
            http_response_code(500);
            header('Content-Type: application/json');
            echo json_encode([
                'success' => false,
                'message' => 'An unexpected error occurred. Our team has been notified.',
            ]);
        });

        register_shutdown_function(function (): void {
            $err = error_get_last();
            if ($err && in_array($err['type'],
                [E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR], true))
            {
                self::error('fatal_error', $err['message'], [
                    'type' => $err['type'],
                    'file' => $err['file'],
                    'line' => $err['line'],
                ]);
            }
        });
    }

    // ── Health check endpoint ─────────────────────────────────────────────────
    public static function healthCheck(): array {
        $checks = [];

        // DB
        try {
            Database::connect()->query('SELECT 1');
            $checks['database'] = 'ok';
        } catch (\Throwable $e) {
            $checks['database'] = 'error';
        }

        // Redis
        try {
            require_once dirname(__DIR__) . '/redis/RateLimiter.php';
            RateLimiter::cacheSet('health_check', '1', 5);
            $v = RateLimiter::cacheGet('health_check');
            $checks['redis'] = $v === '1' ? 'ok' : 'error';
        } catch (\Throwable $e) {
            $checks['redis'] = 'error';
        }

        $checks['php']     = PHP_VERSION;
        $checks['time']    = date('c');
        $checks['version'] = '1.0.0';

        $overallOk = !in_array('error', $checks, true);
        return ['ok' => $overallOk, 'checks' => $checks];
    }
}
