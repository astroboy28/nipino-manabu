<?php
// backend/middleware/Auth.php
// ─── JWT authentication + security headers middleware ─────────────────────────
declare(strict_types=1);

class Auth {
    private static array $cfg;

    private static function cfg(): array {
        if (!isset(self::$cfg)) {
            $c = require dirname(__DIR__) . '/config/config.php';
            self::$cfg = $c['jwt'];
            if (strlen(self::$cfg['secret']) < 32) {
                // Refuse to sign/verify tokens with a missing or weak secret —
                // an empty/short HMAC key is trivially forgeable.
                error_log('FATAL: JWT_SECRET is unset or shorter than 32 bytes.');
                http_response_code(503);
                echo json_encode(['success' => false, 'message' => 'Service unavailable']);
                exit;
            }
        }
        return self::$cfg;
    }

    // ── Security headers — attach to EVERY response ───────────────────────────
    public static function securityHeaders(): void {
        header('Content-Type: application/json; charset=utf-8');
        header('X-Content-Type-Options: nosniff');
        header('X-Frame-Options: DENY');
        header('X-XSS-Protection: 1; mode=block');
        header('Referrer-Policy: strict-origin-when-cross-origin');
        header('Cache-Control: no-store, no-cache, must-revalidate');
        header('Strict-Transport-Security: max-age=31536000; includeSubDomains');
        header('Content-Security-Policy: default-src \'none\'');
        // CORS — restrict to your app domains
        $origin = $_SERVER['HTTP_ORIGIN'] ?? '';
        $allowed = ['https://nipino-manabu.com', 'https://api.nipino-manabu.com'];
        if (in_array($origin, $allowed, true)) {
            header("Access-Control-Allow-Origin: $origin");
        }
        header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
        header('Access-Control-Allow-Headers: Authorization, Content-Type, X-App-Version');
        header('Access-Control-Max-Age: 86400');
        if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(204); exit; }
    }

    // ── Generate JWT (access token) ───────────────────────────────────────────
    public static function generateAccessToken(int $userId, string $username): string {
        $cfg = self::cfg();
        $now = time();
        $header  = self::base64url(json_encode(['alg' => $cfg['algorithm'], 'typ' => 'JWT']));
        $payload = self::base64url(json_encode([
            'iss'      => $cfg['issuer'],
            'aud'      => $cfg['audience'],
            'iat'      => $now,
            'exp'      => $now + $cfg['access_ttl'],
            'sub'      => (string)$userId,
            'username' => $username,
            'jti'      => bin2hex(random_bytes(16)),
        ]));
        $sig = self::base64url(
            hash_hmac('sha256', "$header.$payload", $cfg['secret'], true)
        );
        return "$header.$payload.$sig";
    }

    // ── Generate refresh token (opaque, stored hashed in DB) ──────────────────
    public static function generateRefreshToken(): string {
        return bin2hex(random_bytes(64)); // 128-char hex string
    }

    // ── Verify & decode JWT ───────────────────────────────────────────────────
    public static function verifyAccessToken(string $token): ?array {
        $cfg   = self::cfg();
        $parts = explode('.', $token);
        if (count($parts) !== 3) return null;

        [$header, $payload, $sig] = $parts;
        $expected = self::base64url(
            hash_hmac('sha256', "$header.$payload", $cfg['secret'], true)
        );
        if (!hash_equals($expected, $sig)) return null; // timing-safe compare

        $data = json_decode(self::base64urlDecode($payload), true);
        if (!$data) return null;
        if (($data['exp'] ?? 0) < time()) return null;
        if (($data['iss'] ?? '') !== $cfg['issuer'])  return null;
        if (($data['aud'] ?? '') !== $cfg['audience']) return null;

        return $data;
    }

    // ── Extract Bearer token from Authorization header ────────────────────────
    public static function getBearerToken(): ?string {
        $auth = $_SERVER['HTTP_AUTHORIZATION']
             ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION']
             ?? '';
        // Confirmed on this server's Apache/mod_php: HTTP_AUTHORIZATION is
        // NOT populated in $_SERVER even though the header genuinely arrives
        // (a known mod_php quirk) — every authenticated endpoint was
        // rejecting valid tokens with "No token provided" as a result.
        // getallheaders() reads Apache's request headers directly and does
        // see it, so fall back to that.
        if (!$auth && function_exists('getallheaders')) {
            foreach (getallheaders() as $name => $value) {
                if (strcasecmp($name, 'Authorization') === 0) { $auth = $value; break; }
            }
        }
        if (preg_match('/Bearer\s+(.+)/i', $auth, $m)) {
            return trim($m[1]);
        }
        return null;
    }

    // ── Middleware: require valid JWT, return user claims ─────────────────────
    public static function requireAuth(): array {
        $token = self::getBearerToken();
        if (!$token) {
            http_response_code(401);
            echo json_encode(['success' => false, 'message' => 'No token provided']);
            exit;
        }
        $claims = self::verifyAccessToken($token);
        if (!$claims) {
            http_response_code(401);
            echo json_encode(['success' => false, 'message' => 'Token invalid or expired']);
            exit;
        }
        return $claims;
    }

    // ── Input sanitization ────────────────────────────────────────────────────
    public static function sanitizeString(string $input, int $maxLen = 255): string {
        $input = trim($input);
        $input = substr($input, 0, $maxLen);
        // Strip null bytes
        $input = str_replace("\0", '', $input);
        return $input;
    }

    public static function sanitizeEmail(string $email): string {
        $email = strtolower(trim($email));
        $clean = filter_var($email, FILTER_SANITIZE_EMAIL);
        return $clean ?: '';
    }

    public static function validateEmail(string $email): bool {
        return (bool) filter_var($email, FILTER_VALIDATE_EMAIL);
    }

    // ── Rate limiting (file-based; use Redis in production) ───────────────────
    public static function rateLimit(string $key, int $max, int $window): void {
        $dir  = sys_get_temp_dir() . '/nipino_rl/';
        if (!is_dir($dir)) mkdir($dir, 0700, true);
        $file = $dir . hash('sha256', $key) . '.json';
        $now  = time();
        $data = ['count' => 0, 'window_start' => $now];

        if (file_exists($file)) {
            $data = json_decode(file_get_contents($file), true) ?? $data;
            if ($now - $data['window_start'] > $window) {
                $data = ['count' => 0, 'window_start' => $now];
            }
        }
        $data['count']++;
        file_put_contents($file, json_encode($data), LOCK_EX);

        if ($data['count'] > $max) {
            http_response_code(429);
            echo json_encode([
                'success' => false,
                'message' => 'Too many requests. Please wait before retrying.',
                'retry_after' => $window - ($now - $data['window_start']),
            ]);
            exit;
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────
    // Public: also used by store.php to sign the Google service-account JWT.
    public static function base64url(string $data): string {
        return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
    }
    private static function base64urlDecode(string $data): string {
        return base64_decode(strtr($data, '-_', '+/') . str_repeat('=', (4 - strlen($data) % 4) % 4));
    }

    // ── Get JSON body safely ──────────────────────────────────────────────────
    public static function getJsonBody(): array {
        $raw = file_get_contents('php://input');
        if (!$raw || trim($raw) === '') {
            // Fallback: try to read from apache request body
            $raw = isset($GLOBALS['HTTP_RAW_POST_DATA'])
                ? $GLOBALS['HTTP_RAW_POST_DATA'] : '';
        }
        if (!$raw || trim($raw) === '') return [];
        $data = json_decode($raw, true);
        return is_array($data) ? $data : [];
    }

    // ── Hash password (bcrypt cost=12) ────────────────────────────────────────
    public static function hashPassword(string $password): string {
        return password_hash($password, PASSWORD_BCRYPT, ['cost' => 12]);
    }

    public static function verifyPassword(string $password, string $hash): bool {
        return password_verify($password, $hash);
    }
}
