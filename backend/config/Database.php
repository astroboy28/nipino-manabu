<?php
// backend/config/Database.php
declare(strict_types=1);

class Database {
    private static ?PDO $instance = null;

    public static function connect(): PDO {
        if (self::$instance !== null) return self::$instance;

        $cfg = require __DIR__ . '/config.php';
        $db  = $cfg['db'];

        $dsn = "pgsql:host={$db['host']};port={$db['port']};"
             . "dbname={$db['name']};sslmode={$db['sslmode']}";

        try {
            self::$instance = new PDO($dsn, $db['user'], $db['pass'], [
                PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                // NOTE: this was previously commented "IMPORTANT for
                // security", which is backwards — native server-side
                // prepares (false) are generally the safer default and
                // would have caught this codebase's several $1/$2-style
                // placeholder typos at prepare() time instead of failing
                // silently or throwing deep in execute(). Left as `true`
                // here since flipping it is a behavior change that wants
                // its own testing pass, not a drive-by comment fix.
                PDO::ATTR_EMULATE_PREPARES   => true,
                PDO::ATTR_PERSISTENT         => false,
            ]);
            // Set application timezone
            self::$instance->exec("SET TIME ZONE 'UTC'");
            return self::$instance;
        } catch (PDOException $e) {
            // Never expose DB details in response
            error_log('DB connection failed: ' . $e->getMessage());
            http_response_code(503);
            echo json_encode(['success' => false, 'message' => 'Service unavailable']);
            exit;
        }
    }
}
