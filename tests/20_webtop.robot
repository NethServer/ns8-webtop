*** Settings ***
Library    SSHLibrary
Resource    api.resource

*** Variables ***
${curl_timeout}    9
${SCENARIO}        install

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
    ...    rm -f cookies.txt; curl -L -v -X POST ${backend_url}/webtop/login -d "wtusername=u1@domain.test" -d "wtpassword=Nethesis,1234" -d "location=${backend_url}/webtop/" -d "wtdomain=NethServer" -b cookies.txt -c cookies.txt -H "User-Agent: curl/8.15.0" -H "Referer: ${backend_url}/webtop/" -H "Accept: */*"
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


*** Test Cases ***
Check if webtop is installed correctly
    # The update scenario starts from the NS8 stable release, then upgrades it below
    ${image} =    Set Variable If    '${SCENARIO}' == 'update'    webtop    ${IMAGE_URL}
    ${output}  ${rc} =    Execute Command    add-module ${image} 1
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0
    &{output} =    Evaluate    ${output}
    Set Global Variable    ${webtop_module_id}    ${output.module_id}

Check if we can retrieve the mail module ID
    FOR    ${i}    IN RANGE    30
        ${ocfg} =   Run task    module/${webtop_module_id}/get-defaults    {}
        Log    ${ocfg}
        Run Keyword If    ${ocfg}    Exit For Loop
        Sleep    2s
    END
    Set Suite Variable     ${mail_modules_id}    ${ocfg['mail_modules_id'][0]['value']}
    Should Not Be Empty    ${mail_modules_id}

Check if webtop can be configured
    ${mail_module}    ${mail_domain}=    Evaluate    "${mail_modules_id}".split(",")
    ${rc} =    Execute Command    api-cli run module/${webtop_module_id}/configure-module --data '{"ejabberd_domain": "","ejabberd_module": "","hostname": "webtop.domain.com","locale": "en_US","mail_domain": "${mail_domain}","mail_module": "${mail_module}","pecbridge_admin_mail": "","phonebook_instance": "","request_https_certificate": false,"timezone": "Europe/Rome","webapp": {"debug": false, "max_memory": 1024, "min_memory": 512},"webdav": {"debug": false, "loglevel": "ERROR"},"zpush": {"loglevel": "ERROR"}}'
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0

Retrieve webtop backend URL
    # Assuming the test is running on a single node cluster
    ${response} =    Run task     module/traefik1/get-route    {"instance":"${webtop_module_id}"}
    Set Suite Variable    ${backend_url}    ${response['url']}

Check if webtop works as expected
    Retry test    Backend URL is reachable

Verify webtop frontend title
    ${output} =    Execute Command    curl -s ${backend_url}/webtop/
    Should Contain    ${output}    <title>NethService Collaboration</title>

Login to webtop as user u1@domain.test
    Login as u1

Check u1 is in the webtop database
    ${uid} =    Get the database id of u1
    Set Suite Variable    ${u1_uid}    ${uid}

Update webtop to the image under test
    Skip If    '${SCENARIO}' != 'update'    scenario is ${SCENARIO}, nothing to update
    ${rc} =    Execute Command
    ...    api-cli run update-module --data '{"force":true,"module_url":"${IMAGE_URL}","instances":["${webtop_module_id}"]}'
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0

Check the configuration survives the update
    Skip If    '${SCENARIO}' != 'update'    scenario is ${SCENARIO}, nothing to update
    ${config} =    Run task    module/${webtop_module_id}/get-configuration    {}
    Should Be Equal    ${config['hostname']}    webtop.domain.com
    Should Be Equal    ${config['timezone']}    Europe/Rome
    Should Be Equal    ${config['locale']}    en_US
    ${mail_module} =    Evaluate    "${mail_modules_id}".split(",")[0]
    Should Be Equal    ${config['mail_module']}    ${mail_module}

Check webtop works after the update
    Skip If    '${SCENARIO}' != 'update'    scenario is ${SCENARIO}, nothing to update
    Retry test    Backend URL is reachable
    Retry test    Login as u1

Check u1 keeps its database row after the update
    Skip If    '${SCENARIO}' != 'update'    scenario is ${SCENARIO}, nothing to update
    ${uid} =    Get the database id of u1
    Should Be Equal    ${uid}    ${u1_uid}
