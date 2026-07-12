<?php
// backend/email/FCM.php
// ─── Firebase Cloud Messaging — push notifications via FCM HTTP v1 API ───────
declare(strict_types=1);

class FCM {
    private static ?string $accessToken = null;
    private static int     $tokenExpiry = 0;

    // ── Get OAuth2 access token for FCM HTTP v1 ───────────────────────────────
    private static function accessToken(): ?string {
        if (self::$accessToken && time() < self::$tokenExpiry - 60) {
            return self::$accessToken;
        }
        $keyJson = $_ENV['FIREBASE_SERVICE_ACCOUNT_JSON'] ?? '';
        if (!$keyJson) {
            error_log('FCM: FIREBASE_SERVICE_ACCOUNT_JSON not set');
            return null;
        }
        $key = json_decode($keyJson, true);
        if (!$key) { error_log('FCM: Invalid service account JSON'); return null; }

        $now    = time();
        $header = rtrim(strtr(base64_encode(json_encode(['alg'=>'RS256','typ'=>'JWT'])),'+/','-_'),'=');
        $claim  = rtrim(strtr(base64_encode(json_encode([
            'iss'   => $key['client_email'],
            'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
            'aud'   => 'https://oauth2.googleapis.com/token',
            'iat'   => $now,
            'exp'   => $now + 3600,
        ])),'+/','-_'),'=');

        $toSign = "$header.$claim";
        if (!openssl_sign($toSign, $sig, $key['private_key'], 'SHA256')) {
            error_log('FCM: openssl_sign failed'); return null;
        }
        $jwt = $toSign . '.' . rtrim(strtr(base64_encode($sig),'+/','-_'),'=');

        $ch = curl_init('https://oauth2.googleapis.com/token');
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_POST           => true,
            CURLOPT_POSTFIELDS     => http_build_query([
                'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                'assertion'  => $jwt,
            ]),
            CURLOPT_SSL_VERIFYPEER => true,
            CURLOPT_TIMEOUT        => 10,
        ]);
        $res  = curl_exec($ch);
        curl_close($ch);
        $data = json_decode($res, true);

        self::$accessToken = $data['access_token'] ?? null;
        self::$tokenExpiry = $now + ($data['expires_in'] ?? 3600);
        return self::$accessToken;
    }

    // ── Send to a single FCM token ────────────────────────────────────────────
    public static function sendToToken(
        string $fcmToken,
        string $title,
        string $body,
        array  $data = [],
        string $imageUrl = ''
    ): bool {
        $projectId = $_ENV['FIREBASE_PROJECT_ID'] ?? '';
        if (!$projectId) { error_log('FCM: FIREBASE_PROJECT_ID not set'); return false; }

        $accessToken = self::accessToken();
        if (!$accessToken) return false;

        $msg = [
            'token'        => $fcmToken,
            'notification' => ['title' => $title, 'body' => $body],
            'data'         => array_map('strval', $data), // all values must be strings
            'android'      => [
                'notification' => [
                    'sound'        => 'default',
                    'click_action' => 'FLUTTER_NOTIFICATION_CLICK',
                    'channel_id'   => 'nipino_manabu_channel',
                    'color'        => '#CC0000',
                    'icon'         => 'ic_notification',
                ],
                'priority' => 'high',
            ],
            'apns' => [
                'payload' => [
                    'aps' => [
                        'sound' => 'default',
                        'badge' => 1,
                        'content-available' => 1,
                    ],
                ],
                'headers' => ['apns-priority' => '10'],
            ],
        ];

        if ($imageUrl) {
            $msg['notification']['image']                   = $imageUrl;
            $msg['android']['notification']['image']        = $imageUrl;
            $msg['apns']['payload']['aps']['mutable-content'] = 1;
        }

        $url = "https://fcm.googleapis.com/v1/projects/$projectId/messages:send";
        $ch  = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_POST           => true,
            CURLOPT_POSTFIELDS     => json_encode(['message' => $msg]),
            CURLOPT_HTTPHEADER     => [
                'Authorization: Bearer ' . $accessToken,
                'Content-Type: application/json',
            ],
            CURLOPT_SSL_VERIFYPEER => true,
            CURLOPT_TIMEOUT        => 10,
        ]);
        $res  = curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $err  = curl_error($ch);
        curl_close($ch);

        if ($err) { error_log("FCM curl error: $err"); return false; }
        if ($code !== 200) {
            error_log("FCM error $code: $res");
            // Handle invalid token — should be removed from DB
            $resp = json_decode($res, true);
            if (isset($resp['error']['details'][0]['errorCode'])
                && in_array($resp['error']['details'][0]['errorCode'],
                    ['UNREGISTERED','INVALID_ARGUMENT'], true)) {
                return false; // Caller should remove token
            }
            return false;
        }
        return true;
    }

    // ── Send to multiple tokens (batch) ───────────────────────────────────────
    public static function sendToTokens(
        array  $fcmTokens,
        string $title,
        string $body,
        array  $data = []
    ): array {
        $results = ['sent' => 0, 'failed' => 0, 'invalid_tokens' => []];
        foreach ($fcmTokens as $token) {
            $ok = self::sendToToken($token, $title, $body, $data);
            if ($ok) {
                $results['sent']++;
            } else {
                $results['failed']++;
                $results['invalid_tokens'][] = $token;
            }
        }
        return $results;
    }

    // ── Preset notification types ─────────────────────────────────────────────
    public static function streakReminder(string $token, int $streak): bool {
        return self::sendToToken(
            $token,
            '🔥 ' . $streak . '-day streak at risk!',
            'You haven\'t quizzed today. Keep your streak alive!',
            ['type' => 'streak_reminder', 'screen' => 'quiz']
        );
    }

    public static function badgeEarned(string $token, string $badgeName, string $emoji): bool {
        return self::sendToToken(
            $token,
            "$emoji New badge: $badgeName!",
            'You earned a new achievement in Nipino-Manabu!',
            ['type' => 'badge', 'screen' => 'profile']
        );
    }

    public static function levelComplete(string $token, string $level): bool {
        return self::sendToToken(
            $token,
            "🎓 $level complete!",
            "Congratulations! You've completed all $level topics.",
            ['type' => 'level_complete', 'level' => $level, 'screen' => 'home']
        );
    }

    public static function weeklyLeaderboard(
        string $token, string $username, int $rank
    ): bool {
        return self::sendToToken(
            $token,
            '🏆 Weekly results are in!',
            "You ranked #$rank this week, $username. Keep pushing!",
            ['type' => 'leaderboard', 'rank' => (string)$rank, 'screen' => 'leaderboard']
        );
    }
}
