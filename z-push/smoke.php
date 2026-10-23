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
// Sonicle's log goes to a file, for the push check below
$logFile = tempnam(sys_get_temp_dir(), 'smoke-log');
\WT\Log::init('eas-server', 'WARNING', $logFile);
function logSince($offset) {
    global $logFile;
    clearstatcache();
    return (string)file_get_contents($logFile, false, null, $offset);
}

$_SERVER['SCRIPT_FILENAME'] = WT_EAS_ROOT . $config->getZPushSrc() . '/index.php';
chdir(WT_EAS_ROOT . $config->getZPushSrc());
require WT_EAS_ROOT . '/inc/zpush.config.php';

check(ZPUSH_VERSION === '2.7.7', 'ZPUSH_VERSION is ' . var_export(ZPUSH_VERSION, true) . ', expected the shipped 2.7.7');

// As on every request: sets up logging (and Z-Push's error handler, so collect
// warnings after it) and loads the policy file
ZPush::CheckConfig();
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

// What Z-Push 2.4.5 returned: WebTop stores attendees as "email <email>"
foreach (['Ann <ann@example.org>' => ['address' => 'ann@example.org', 'personal' => '"Ann"'],
          'u3@example.org <u3@example.org>' => ['address' => 'u3@example.org', 'personal' => '"u3@example.org"'],
          '"Ann B" <ann@example.org>' => ['address' => 'ann@example.org', 'personal' => '"Ann B"'],
          'ann@example.org' => ['address' => 'ann@example.org', 'personal' => '']] as $input => $expected) {
    try {
        $ia = \WT\EAS\ZPUtil::parseInternetAddress($input);
        check($ia === $expected, "ZPUtil::parseInternetAddress('$input') gives " . json_encode($ia));
    } catch (\Throwable $e) {
        check(false, "ZPUtil::parseInternetAddress('$input') throws " . get_class($e) . ': ' . $e->getMessage());
    }
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
// Z-Push 2.7 formats every date it sends with the intl extension
try {
    check(Utils::FormatDateUtc(31536000, "yyyyMMdd'T'HHmmSS'Z'") === '19710101T000000Z', 'Z-Push formats dates');
} catch (\Throwable $e) {
    check(false, 'Z-Push date formatting throws ' . get_class($e) . ': ' . $e->getMessage());
}

// Phones paired before the upgrade saved the hash of the policy they accepted:
// a different hash makes every phone provision again. These are Z-Push 2.4.5's
// hashes of the default policy, by ActiveSync version
try {
    $protocol = new ReflectionProperty('Request', 'asProtocolVersion');
    $protocol->setAccessible(true);
    foreach (['12.0' => 'eb9d07ca23fcbf51a31ce74dc7fe2a70', '12.1' => '794e30742dfdda378caebc4203d4c843',
              '14.0' => '794e30742dfdda378caebc4203d4c843'] as $version => $hash) {
        $protocol->setValue(null, $version);
        $p = SyncProvisioning::GetObjectWithPolicies(ZPush::GetPolicies()['default']);
        $p->PolicyName = 'default';
        check($p->GetPolicyHash() === $hash, "the ActiveSync $version policy hash is unchanged (no provisioning again)");
    }
} catch (\Throwable $e) {
    check(false, 'policy hash check throws ' . get_class($e) . ': ' . $e->getMessage());
}

// Push: while WebTop answers with errors, each check of the Ping loop logs one
// warning, not Sonicle's ERROR with the whole exception; a sync still logs it.
// A stand-in for WebTop on the apiBaseUrl of verify.sh's config.json answers 503
$router = tempnam(sys_get_temp_dir(), 'smoke-router');
file_put_contents($router, '<?php http_response_code(503); echo "starting";');
$server = proc_open([PHP_BINARY, '-S', '127.0.0.1:18080', $router], [1 => ['file', '/dev/null', 'w'], 2 => ['file', '/dev/null', 'w']], $pipes);
for ($i = 0; $i < 50 && !($sock = @fsockopen('127.0.0.1', 18080)); $i++) usleep(100000);
if ($sock) fclose($sock);
try {
    $backend = new BackendContacts();
    foreach (['sinkFolders' => ['1' => '1'], 'sinkStates' => ['1' => 'etag']] as $name => $value) {
        $prop = new ReflectionProperty('AbstractWebTopBackendDiff', $name);
        $prop->setAccessible(true);
        $prop->setValue($backend, $value);
    }
    $offset = filesize($logFile);
    $changes = $backend->ChangesSink(1);
    $log = logSince($offset);
    check($changes === [] && substr_count($log, '.WARNING: ') === 1 && strpos($log, '.ERROR: ') === false,
        'a push check while WebTop answers 503 wakes no phone and logs one warning' . ($log === '' ? '' : ":\n  " . trim($log)));
    $sync = new ReflectionMethod('BackendContacts', 'doGetApiFolders');
    $sync->setAccessible(true);
    $offset = filesize($logFile);
    check($sync->invoke($backend) === null && strpos(logSince($offset), '.ERROR: ') !== false,
        'a sync while WebTop answers 503 still logs an error');
} catch (\Throwable $e) {
    check(false, 'push check throws ' . get_class($e) . ': ' . $e->getMessage());
}
proc_terminate($server);
proc_close($server);
unlink($router);
unlink($logFile);

restore_error_handler();
exit($fail);
