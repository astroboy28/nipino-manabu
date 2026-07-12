<?php
// backend/api/wellknown.php
// ─── Serves /.well-known/ files required for deep links ──────────────────────
// Apple and Google verify these during app review. Must return correct
// Content-Type and be served over HTTPS with no redirect on the path.

declare(strict_types=1);

$file = $_GET['file'] ?? '';

// Whitelist — only allow these two files
$allowed = [
    'assetlinks.json'          => 'application/json',
    'apple-app-site-association' => 'application/json',
];

if (!isset($allowed[$file])) {
    http_response_code(404);
    exit;
}

$path = dirname(__DIR__) . '/wellknown/' . $file;
if (!file_exists($path)) {
    http_response_code(404);
    exit;
}

// CRITICAL: Apple requires NO redirect on this path and exact Content-Type
header('Content-Type: ' . $allowed[$file]);
header('Cache-Control: public, max-age=3600');
header('X-Content-Type-Options: nosniff');
http_response_code(200);
readfile($path);
