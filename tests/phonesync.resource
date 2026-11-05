*** Settings ***
Library     SSHLibrary
Library     Collections
Library     String
Resource    api.resource
Resource    webtop.resource

*** Variables ***
# CI defaults; override with -v when running against another machine
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

Set test dates
    # Events are one week after the run day: phones sync only recent past events
    # (ActiveSync keeps one month by default). Set once per run, so 21_pre_upgrade
    # and 23_post_upgrade agree. The node computes them: it has the time zone data
    ${defined} =    Run Keyword And Return Status    Variable Should Exist    \${EVENT_DAY}
    IF    ${defined}    RETURN
    ${out} =    Execute Command
    ...    d=$(date -u -d '+7 days' +%F) && echo "$d" && date -u -d "$d +1 day" +%F && date -u -d "TZ=\\"Europe/Rome\\" $d 10:00" +%FT%TZ && date -u -d "TZ=\\"Europe/Rome\\" $d 11:00" +%FT%TZ && date -u -d "$d +5 days" +%FT08:00:00Z
    @{lines} =    Split To Lines    ${out}
    Length Should Be    ${lines}    5
    # 10:00 to 11:00 Rome time, the time the phones send
    Set Global Variable    ${EVENT_DAY}    ${lines}[0]
    Set Global Variable    ${EVENT_NEXT_DAY}    ${lines}[1]
    Set Global Variable    ${LOCAL_START}    ${lines}[0]T10:00:00
    Set Global Variable    ${LOCAL_END}    ${lines}[0]T11:00:00
    Set Global Variable    ${UTC_START}    ${lines}[2]
    Set Global Variable    ${UTC_END}    ${lines}[3]
    Set Global Variable    ${TASK_DUE}    ${lines}[4]

Upload phonesync helper
    Execute Command    rm -rf ${PHONESYNC} && mkdir -p ${PHONESYNC_STATE}
    Put Directory    ${CURDIR}/phonesync    ${PHONESYNC}    recursive=True
    # the node needs only the helper, not its offline unit tests
    Execute Command    cd ${PHONESYNC} && rm -rf fixtures __pycache__ test_*.py

Phonesync command line
    [Arguments]    ${proto}    ${command}    ${profile}    @{args}
    IF    '${proto}' == 'version'
        @{argv} =    Create List    version
    ELSE
        @{argv} =    Create List    ${proto}    ${command}
        ...    --url    ${backend_url}    --host    ${WEBTOP_HOST}
        ...    --user    ${PHONE_USER}    --password    ${PHONE_PASSWORD}    @{args}
        IF    $profile
            Append To List    ${argv}    --profile    ${profile}
        END
        IF    '${proto}' == 'webtop'
            Append To List    ${argv}    --module    ${webtop_module_id}
        END
    END
    ${cmdline} =    Evaluate    shlex.join(['python3', $PHONESYNC] + $argv)    modules=shlex
    RETURN    ${cmdline}

Phonesync result
    [Arguments]    ${label}    ${out}    ${err}    ${rc}
    Log    ${out}
    ${result} =    Evaluate    json.loads($out) if $out.strip() else {"error": $err}    modules=json
    Should Be Equal As Integers    ${rc}    0    phonesync ${label} failed: ${result.get('error')}${\n}${err}
    RETURN    ${result}

Phonesync
    [Arguments]    ${proto}    ${command}    ${profile}    @{args}
    ${cmdline} =    Phonesync command line    ${proto}    ${command}    ${profile}    @{args}
    ${out}    ${err}    ${rc} =    Execute Command    ${cmdline}    return_stderr=True    return_rc=True
    ${result} =    Phonesync result    ${proto} ${command}    ${out}    ${err}    ${rc}
    RETURN    ${result}

Start phonesync
    # runs in the background, e.g. a phone waiting in Ping; collect it with Finish phonesync
    [Arguments]    ${proto}    ${command}    ${profile}    @{args}
    ${cmdline} =    Phonesync command line    ${proto}    ${command}    ${profile}    @{args}
    Start Command    ${cmdline}

Finish phonesync
    ${out}    ${err}    ${rc} =    Read Command Output    return_stderr=True    return_rc=True
    ${result} =    Phonesync result    background command    ${out}    ${err}    ${rc}
    RETURN    ${result}

Reset phones
    # forget every phone pairing, so reruns on a development machine start clean
    Execute Command    rm -rf ${PHONESYNC_STATE} && mkdir -p ${PHONESYNC_STATE}

Unique name
    [Arguments]    ${base}
    ${hex} =    Evaluate    secrets.token_hex(4)    modules=secrets
    RETURN    e2e-${hex}-${base}
