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
