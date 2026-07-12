<?php
// backend/api/health.php
// ─── Health check — used by load balancers and uptime monitors ────────────────
declare(strict_types=1);

require_once dirname(__DIR__) . '/config/Database.php';
require_once dirname(__DIR__) . '/redis/RateLimiter.php';
require_once dirname(__DIR__) . '/middleware/Monitor.php';

header('Content-Type: application/json');
header('Cache-Control: no-store');

$result = Monitor::healthCheck();
http_response_code($result['ok'] ? 200 : 503);
echo json_encode($result, JSON_PRETTY_PRINT);
