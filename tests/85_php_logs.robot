*** Settings ***
Documentation     After all phone suites, the PHP services logged no PHP errors
Resource          phonesync_sync.resource
Suite Setup       Resolve test environment

*** Variables ***
# PHP-level problems only: Sonicle's own error lines (e.g. a REST call that failed) are expected
${PHP_ERRORS}     PHP (Fatal|Parse) error|Uncaught|TypeError|ArgumentCountError|ValueError|Deprecated:

*** Test Cases ***
WebDAV logged no PHP errors
    PHP errors in log    webdav

*** Keywords ***
PHP errors in log
    [Arguments]    ${container}
    ${cmd} =    Evaluate    shlex.join(['runagent', '-m', $webtop_module_id, 'podman', 'logs', $container]) + ' 2>&1 | grep -E ' + shlex.quote($PHP_ERRORS) + ' | head -n 20'    modules=shlex
    ${lines} =    Execute Command    ${cmd}
    Should Be Empty    ${lines}    ${container} logged PHP errors:${\n}${lines}
