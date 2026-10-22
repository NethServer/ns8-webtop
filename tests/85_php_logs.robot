*** Settings ***
Documentation     After all phone suites, the PHP services logged no PHP errors
Resource          phonesync_sync.resource
Suite Setup       Resolve test environment

*** Variables ***
# PHP-level problems only: Sonicle's own error lines (e.g. a REST call that failed) are expected.
# sabre/dav 4 catches every PHP error and Sonicle logs it as "CRITICAL: <Class>Error: ...", so match
# any *Error class, plus PHP warnings and crashed workers
${PHP_ERRORS}     PHP (Fatal error|Parse error|Recoverable fatal error|Warning)|Uncaught|(^|[^A-Za-z])[A-Z][A-Za-z]*Error: |exited on signal

*** Test Cases ***
WebDAV logged no PHP errors
    PHP errors in log    webdav

*** Keywords ***
PHP errors in log
    [Arguments]    ${container}
    ${cmd} =    Evaluate    shlex.join(['runagent', '-m', $webtop_module_id, 'podman', 'logs', $container])    modules=shlex
    ${log}    ${rc} =    Execute Command    ${cmd} 2>&1    return_rc=True
    Should Be Equal As Integers    ${rc}    0    cannot read the ${container} log: ${log}
    Should Contain    ${log}    fpm is running    the ${container} log does not cover the php-fpm start
    ${lines} =    Evaluate    '\\n'.join(list(filter(lambda l, p=$PHP_ERRORS: re.search(p, l), $log.splitlines()))[:20])    modules=re
    Should Be Empty    ${lines}    ${container} logged PHP errors:${\n}${lines}
