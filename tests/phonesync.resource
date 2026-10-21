*** Settings ***
Library     SSHLibrary
Resource    api.resource

*** Variables ***
# CI defaults; override with -v when running against another machine
${PHONE_USER}        u1@domain.test
${PHONE_PASSWORD}    Nethesis,1234
${MAIL_RECIPIENT}    u3@domain.test
${WEBTOP_HOST}       webtop.domain.com
${PHONESYNC}         /root/phonesync
${PHONESYNC_STATE}   /root/phonesync-state

*** Keywords ***
Resolve test environment
    ${defined} =    Run Keyword And Return Status    Variable Should Exist    \${webtop_module_id}
    IF    not ${defined}
        ${id} =    Execute Command    getent passwd | grep -oE '^webtop[0-9]+' | tail -n 1
        Should Not Be Empty    ${id}
        Set Global Variable    ${webtop_module_id}    ${id}
    END
    ${defined} =    Run Keyword And Return Status    Variable Should Exist    \${MID}
    IF    not ${defined}
        ${id} =    Execute Command    getent passwd | grep -oE '^mail[0-9]+' | head -n 1
        Should Not Be Empty    ${id}
        Set Global Variable    ${MID}    ${id}
    END
    ${defined} =    Run Keyword And Return Status    Variable Should Exist    \${backend_url}
    IF    not ${defined}
        ${route} =    Run task    module/traefik1/get-route    {"instance":"${webtop_module_id}"}
        Set Global Variable    ${backend_url}    ${route['url']}
    END

Upload phonesync helper
    Execute Command    rm -rf ${PHONESYNC} && mkdir -p ${PHONESYNC_STATE}
    Put Directory    ${CURDIR}/phonesync    ${PHONESYNC}    recursive=True

Phonesync
    [Arguments]    ${proto}    ${command}    ${profile}    @{args}
    IF    '${proto}' == 'version'
        @{argv} =    Create List    version
    ELSE
        @{argv} =    Create List    ${proto}    ${command}    --profile    ${profile}
        ...    --url    ${backend_url}    --host    ${WEBTOP_HOST}
        ...    --user    ${PHONE_USER}    --password    ${PHONE_PASSWORD}    @{args}
    END
    ${cmdline} =    Evaluate    shlex.join(['python3', $PHONESYNC] + $argv)    modules=shlex
    ${out}    ${err}    ${rc} =    Execute Command    ${cmdline}    return_stderr=True    return_rc=True
    Log    ${out}
    ${result} =    Evaluate    json.loads($out) if $out.strip() else {"error": $err}    modules=json
    Should Be Equal As Integers    ${rc}    0    phonesync ${proto} ${command} failed: ${result.get('error')}${\n}${err}
    RETURN    ${result}

Unique name
    [Arguments]    ${base}
    ${hex} =    Evaluate    secrets.token_hex(4)    modules=secrets
    RETURN    e2e-${hex}-${base}
