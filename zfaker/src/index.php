<?php
// Runs z-push-admin for WebTop's Devices panel. Parameters come as JSON
// {"params": "-a lastsync"}; only plain words are accepted and each one is
// passed to the shell quoted, so nothing in them can run as a command.
$json = file_get_contents('php://input');
$data = json_decode($json, true);
$params = is_array($data) && isset($data['params']) && is_string($data['params']) ? $data['params'] : '';
$words = preg_split('/\s+/', trim($params), -1, PREG_SPLIT_NO_EMPTY);
foreach ($words as $word) {
    if (!preg_match('/^[A-Za-z0-9@._:+-]+$/', $word)) {
        http_response_code(400);
        echo "Invalid parameter\n";
        exit;
    }
}
$cmd = __DIR__ . '/wrapper.sh --';
foreach ($words as $word) {
    $cmd .= ' ' . escapeshellarg($word);
}
echo shell_exec($cmd);
