<?php
// Run from a built tree: sabre 4 hands PHP errors (not only exceptions) to
// Sonicle's exception logger, which must log them instead of crashing.
require 'vendor/autoload.php';

$logger = new class {
    public $critical = [];
    public function critical($message) { $this->critical[] = (string) $message; }
    public function debug($message) {}
};
$server = new \Sabre\DAV\Server([]);
$server->addPlugin(new \WT\DAV\Connector\ExceptionLoggerPlugin($logger));
$server->emit('exception', [new \TypeError('e2e smoke probe')]);
if (count($logger->critical) !== 1 || strpos($logger->critical[0], 'e2e smoke probe') === false) {
    fwrite(STDERR, "the exception logger did not log a PHP error\n");
    exit(1);
}
echo "ok: exception logger handles PHP errors\n";

// WebTop REST errors reach the phone with a matching status, not as success
foreach ([400 => 'BadRequest', 403 => 'Forbidden', 404 => 'NotFound', 500 => 'Exception', 0 => 'Exception'] as $code => $class) {
    $e = \WT\Util::toDavException(new \Exception('rest', $code), 'e2e smoke');
    if (get_class($e) !== ($class === 'Exception' ? 'Sabre\DAV\Exception' : "Sabre\\DAV\\Exception\\$class")
            || $e->getHTTPCode() !== ($code ?: 500) || $e->getMessage() !== 'e2e smoke') {
        fwrite(STDERR, "WebTop error $code maps to " . get_class($e) . ' ' . $e->getHTTPCode() . "\n");
        exit(1);
    }
}
echo "ok: WebTop errors map to DAV errors\n";
