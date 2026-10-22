*** Settings ***
Library    SSHLibrary
Resource    api.resource

*** Variables ***
${curl_timeout}    9
${SCENARIO}        install
${PHONE_USER}       u1@domain.test

*** Keywords ***
Retry test
    [Arguments]    ${keyword}
    Wait Until Keyword Succeeds    60 seconds    1 second    ${keyword}

Backend URL is reachable
    ${rc} =    Execute Command    curl -f ${backend_url}/webtop/
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0

Login as u1
    ${output}    ${err}    ${rc} =    Execute Command
    ...    rm -f cookies.txt; curl -L -v -X POST ${backend_url}/webtop/login -d "wtusername=${PHONE_USER}" -d "wtpassword=Nethesis,1234" -d "location=${backend_url}/webtop/" -d "wtdomain=NethServer" -b cookies.txt -c cookies.txt -H "User-Agent: curl/8.15.0" -H "Referer: ${backend_url}/webtop/" -H "Accept: */*"
    ...    return_rc=True
    ...    return_stdout=True
    ...    return_stderr=True
    Log    Curl stdout: ${output}
    Log    Curl stderr: ${err}
    Log    Curl rc: ${rc}
    # webtop redirects to https://
    Should Contain    ${err}    HTTP/1.1 302
    # match the cookie of the authenticated session
    Should Contain    ${err}    Set-Cookie: JSESSIONID=

Get the database id of u1
    # WebTop adds a user to its database on the first login
    ${uid} =    Execute Command
    ...    runagent -m ${webtop_module_id} podman exec postgres psql -U postgres -tA webtop5 -c "SELECT user_uid FROM core.users WHERE domain_id = 'NethServer' AND user_id = 'u1' AND type = 'U'"
    Should Not Be Empty    ${uid}
    RETURN    ${uid}

Mark the start of the phone run
    [Arguments]    ${again}=${False}
    # 85_php_logs checks that the PHP container logs go back to this point (22_update marks it again)
    ${defined} =    Run Keyword And Return Status    Variable Should Exist    \${PHONE_RUN_STARTED}
    IF    not ${defined} or ${again}
        Wait until the PHP containers settle
        ${now} =    Execute Command    date +%s
        Set Global Variable    ${PHONE_RUN_STARTED}    ${now}
    END

Wait until the PHP containers settle
    # configure-module and update-module bind the user domain, and the user-domain-changed event
    # restarts the module once more a few seconds later: wait until webdav and z-push keep their
    # start time for 30 s
    ${cmd} =    Evaluate    shlex.join(['runagent', '-m', $webtop_module_id, 'podman', 'inspect', '-f', '{{.State.Running}} {{.State.StartedAt.Unix}}', 'webdav', 'z-push'])    modules=shlex
    ${last} =    Set Variable    ${EMPTY}
    ${steady} =    Set Variable    ${0}
    FOR    ${i}    IN RANGE    60
        ${state} =    Execute Command    ${cmd}
        ${up} =    Evaluate    $state.split().count('true') == 2
        IF    ${up} and $state == $last
            ${steady} =    Evaluate    ${steady} + 1
        ELSE
            ${steady} =    Set Variable    ${0}
        END
        IF    ${steady} >= 6    BREAK
        ${last} =    Set Variable    ${state}
        Sleep    5s
    END
    Should Be True    ${steady} >= 6    the webdav and z-push containers kept restarting: ${state}
