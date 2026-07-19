<?php
// backend/redis/RateLimiter.php
// ─── Production Redis rate limiter with atomic sliding-window algorithm ─────
declare(strict_types=1);

class RateLimiter {
    private static ?\Redis $redis = null;

    // ── Connect to Redis (singleton) ──────────────────────────────────────────
    private static function redis(): \Redis {
        if (self::$redis !== null) return self::$redis;

        $cfg = require dirname(__DIR__) . '/config/config.php';
        $r   = new \Redis();

        try {
            $host = $_ENV['REDIS_HOST']     ?? '127.0.0.1';
            $port = (int)($_ENV['REDIS_PORT'] ?? 6379);
            $pass = $_ENV['REDIS_PASSWORD']  ?? '';
            $r->connect($host, $port, 2.0); // 2s timeout
            if ($pass) $r->auth($pass);
            // Staging shares this Redis instance with production -- DB 0
            // stays the production default so behavior here is unchanged;
            // staging's .env sets REDIS_DB=1 so its rate-limit counters
            // (and anyone testing registration/login limits) can't affect
            // real users, and vice versa.
            $r->select((int)($_ENV['REDIS_DB'] ?? 0));
            $r->setOption(\Redis::OPT_PREFIX, 'nipino:rl:');
            self::$redis = $r;
        } catch (\RedisException $e) {
            error_log('Redis connection failed: ' . $e->getMessage());
            // Fail open to file-based fallback (never block app on Redis failure)
            return self::fileFallback();
        }

        return self::$redis;
    }

    // ── Sliding-window counter (atomic via MULTI/EXEC) ────────────────────────
    // Returns true if request is allowed, false if rate limited.
    public static function allow(string $key, int $maxRequests, int $windowSeconds): bool {
        try {
            $r   = self::redis();
            $now = microtime(true);
            $win = $now - $windowSeconds;

            $r->multi(\Redis::PIPELINE);
            // Remove timestamps outside the window
            $r->zRemRangeByScore($key, '-inf', (string)$win);
            // Count current window
            $r->zCard($key);
            // Add this request
            $r->zAdd($key, $now, $now . '_' . random_int(0, 999999));
            // Expire key after window
            $r->expire($key, $windowSeconds + 1);
            $results = $r->exec();

            $count = (int)($results[1] ?? 0);
            return $count < $maxRequests;

        } catch (\Throwable $e) {
            error_log('RateLimiter error: ' . $e->getMessage());
            return true; // Fail open
        }
    }

    // ── Enforce limit — abort with 429 if exceeded ───────────────────────────
    public static function enforce(
        string $identifier,
        string $endpoint,
        int    $maxRequests,
        int    $windowSeconds
    ): void {
        $key     = "$endpoint:$identifier";
        $allowed = self::allow($key, $maxRequests, $windowSeconds);

        if (!$allowed) {
            $retryAfter = $windowSeconds;
            header("Retry-After: $retryAfter");
            http_response_code(429);
            echo json_encode([
                'success'     => false,
                'message'     => 'Too many requests. Please wait before retrying.',
                'retry_after' => $retryAfter,
            ]);
            exit;
        }
    }

    // ── Preset policies ───────────────────────────────────────────────────────
    public static function login(string $ip, string $email): void {
        // 5 attempts per IP per 5 min
        self::enforce($ip,    'login_ip',    5,  300);
        // 10 attempts per email per 15 min (prevent credential stuffing)
        self::enforce($email, 'login_email', 10, 900);
    }

    public static function register(string $ip): void {
        self::enforce($ip, 'register', 3, 3600); // 3 per hour per IP
    }

    public static function passwordReset(string $ip, string $email): void {
        self::enforce($ip,    'pw_reset_ip',    5,  3600); // 5/hr per IP
        self::enforce($email, 'pw_reset_email', 3, 86400); // 3/day per email
    }

    public static function quizSubmit(string $userId): void {
        self::enforce($userId, 'quiz_submit', 60, 3600); // 60/hr per user
    }

    public static function api(string $ip): void {
        self::enforce($ip, 'api_general', 200, 60); // 200/min per IP
    }

    // ── File-based fallback (when Redis unavailable) ──────────────────────────
    private static function fileFallback(): \Redis {
        // Return a dummy that always allows (fail open)
        // In production, alert your monitoring if this path is hit
        error_log('ALERT: RateLimiter falling back to permissive mode — Redis unavailable');
        return new class extends \Redis {
            public function zRemRangeByScore($key, $min, $max): int { return 0; }
            public function zCard($key): int { return 0; }
            public function zAdd($key, ...$args): int { return 1; }
            public function expire($key, $ttl): bool { return true; }
            public function multi($mode = \Redis::MULTI): \Redis { return $this; }
            public function exec(): array { return [0, 0, 1, true]; }
        };
    }

    // ── Blacklist IP (for abuse) ───────────────────────────────────────────────
    public static function blacklist(string $ip, int $seconds = 86400): void {
        try {
            $r = self::redis();
            $r->setEx("blacklist:$ip", $seconds, '1');
        } catch (\Throwable $e) {
            error_log('Blacklist error: ' . $e->getMessage());
        }
    }

    public static function isBlacklisted(string $ip): bool {
        try {
            return (bool)(self::redis()->get("blacklist:$ip") ?? false);
        } catch (\Throwable $e) {
            return false;
        }
    }

    // ── Cache helper (general key-value, used for email token dedup) ──────────
    public static function cacheSet(string $key, string $value, int $ttl): void {
        try { self::redis()->setEx("cache:$key", $ttl, $value); }
        catch (\Throwable $e) { error_log('Cache set error: ' . $e->getMessage()); }
    }

    public static function cacheGet(string $key): ?string {
        try {
            $v = self::redis()->get("cache:$key");
            return $v === false ? null : (string)$v;
        } catch (\Throwable $e) { return null; }
    }

    public static function cacheDel(string $key): void {
        try { self::redis()->del("cache:$key"); }
        catch (\Throwable $e) { error_log('Cache del error: ' . $e->getMessage()); }
    }
}
