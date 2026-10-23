*** Settings ***
Documentation     After all phone suites, the PHP services logged no PHP errors
Resource          phonesync_sync.resource
Suite Setup       Resolve test environment

*** Variables ***
# PHP-level problems only: Sonicle's own error lines (e.g. a REST call that failed) are expected.
# sabre/dav 4 catches every PHP error and Sonicle logs it as "CRITICAL: <Class>Error: ...", so match
# any *Error class, plus PHP warnings and crashed workers. Z-Push's own error handler logs PHP
# errors as "trace error: <file>:<line> <message>"
${PHP_ERRORS}     PHP (Fatal error|Parse error|Recoverable fatal error|Warning)|Uncaught|(^|[^A-Za-z])[A-Z][A-Za-z]*Error: |exited on signal|trace error:

*** Test Cases ***
WebDAV logged no PHP errors
    PHP errors in log    webdav

Z-Push logged no PHP errors
    PHP errors in log    z-push

*** Keywords ***
PHP errors in log
    [Arguments]    ${container}
    ${cmd} =    Evaluate    shlex.join(['runagent', '-m', $webtop_module_id, 'podman', 'logs', $container])    modules=shlex
    ${log}    ${rc} =    Execute Command    ${cmd} 2>&1    return_rc=True
    Should Be Equal As Integers    ${rc}    0    cannot read the ${container} log: ${log}
    Container log covers the phone run    ${container}
    ${lines} =    Evaluate    '\\n'.join(list(filter(lambda l, p=$PHP_ERRORS: re.search(p, l), $log.splitlines()))[:20])    modules=re
    Should Be Empty    ${lines}    ${container} logged PHP errors:${\n}${lines}

Container log covers the phone run
    [Arguments]    ${container}
    # php-fpm logs only warnings, so no line marks its start: check instead that the container was not
    # replaced or restarted after the phone suites began, so its log holds every phone request
    ${defined} =    Run Keyword And Return Status    Variable Should Exist    \${PHONE_RUN_STARTED}
    Should Be True    ${defined}    no phone suite ran: nothing to check in the ${container} log
    ${cmd} =    Evaluate    shlex.join(['runagent', '-m', $webtop_module_id, 'podman', 'inspect', '-f', '{{.State.Running}} {{.State.StartedAt.Unix}}', $container])    modules=shlex
    ${state} =    Execute Command    ${cmd}
    ${running}    ${started} =    Evaluate    $state.split()
    Should Be Equal    ${running}    true    the ${container} container is not running
    Should Be True    ${started} <= ${PHONE_RUN_STARTED}    the ${container} container started at ${started}, after the phone suites began at ${PHONE_RUN_STARTED}: its log misses their requests
