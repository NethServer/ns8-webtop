<?php
// Run by verify.sh from a scratch copy of a built tree that has a config.json:
// boot like index.php, load the mail backend as a sync would, and check what
// PHP 8.4 and Z-Push 2.7.7 change.
$fail = 0;
function check($ok, $what) {
    global $fail;
    echo ($ok ? 'ok: ' : 'FAIL: ') . $what . "\n";
    if (!$ok) $fail = 1;
}

define('WT_EAS_ROOT', getcwd());
require 'vendor/autoload.php';
\WT\EAS\Config::load(WT_EAS_ROOT . '/config.json');
$config = \WT\EAS\Config::get();
\WT\Log::init('eas-server', 'ERROR', 'php://stderr');

$_SERVER['SCRIPT_FILENAME'] = WT_EAS_ROOT . $config->getZPushSrc() . '/index.php';
chdir(WT_EAS_ROOT . $config->getZPushSrc());
require WT_EAS_ROOT . '/inc/zpush.config.php';

check(ZPUSH_VERSION === '2.7.7', 'ZPUSH_VERSION is ' . var_export(ZPUSH_VERSION, true) . ', expected the shipped 2.7.7');

// Loading ZLog installs Z-Push's error handler: collect warnings after it
class_exists('ZLog');
$warnings = [];
set_error_handler(function ($no, $str, $file, $line) use (&$warnings) {
    if ($no & (E_WARNING | E_USER_WARNING)) $warnings[] = "$file:$line $str";
    return true;
});
BackendWebTop::GetBackendCombinedConfig();
check(class_exists('BackendWTIMAP'), 'the WebTop mail backend loads');
check(defined('IMAP_SERVER') && IMAP_SERVER === $config->getMailImapServer(),
    'IMAP_SERVER comes from Sonicle\'s config (' . (defined('IMAP_SERVER') ? IMAP_SERVER : 'undefined') . ')');
check(!$warnings, 'no PHP warnings while loading the backends' . ($warnings ? ":\n  " . implode("\n  ", $warnings) : ''));

try {
    $ia = \WT\EAS\ZPUtil::parseInternetAddress('Ann <ann@example.org>');
    check(is_array($ia) && $ia['address'] === 'ann@example.org', 'ZPUtil::parseInternetAddress parses an address');
} catch (\Throwable $e) {
    check(false, 'ZPUtil::parseInternetAddress throws ' . get_class($e) . ': ' . $e->getMessage());
}
// Contact photos: phone → WebTop as a data URI, and back
$png = base64_encode(base64_decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='));
try {
    $uri = \WT\EAS\ZPUtil::pictureToDataUri($png);
    check($uri === 'data:image/png;base64,' . $png, 'a phone photo becomes a data URI');
    $pic = \WT\EAS\ZPUtil::dataUriToPicture(\WT\EAS\ZPUtil::parseDataUri($uri));
    check($pic === ['data' => $png, 'mimeType' => 'image/png'], 'a WebTop data URI becomes a phone photo');
} catch (\Throwable $e) {
    check(false, 'contact photo conversion throws ' . get_class($e) . ': ' . $e->getMessage());
}
restore_error_handler();
exit($fail);
