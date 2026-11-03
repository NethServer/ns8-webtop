*** Settings ***
Library    SSHLibrary
Resource    webtop.resource

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
    Set Global Variable    ${mail_modules_id}    ${ocfg['mail_modules_id'][0]['value']}
    Should Not Be Empty    ${mail_modules_id}

Check if webtop can be configured
    ${mail_module}    ${mail_domain}=    Evaluate    "${mail_modules_id}".split(",")
    ${rc} =    Execute Command    api-cli run module/${webtop_module_id}/configure-module --data '{"ejabberd_domain": "","ejabberd_module": "","hostname": "webtop.domain.com","locale": "en_US","mail_domain": "${mail_domain}","mail_module": "${mail_module}","pecbridge_admin_mail": "","phonebook_instance": "","request_https_certificate": false,"timezone": "Europe/Rome","webapp": {"debug": false, "max_memory": 1024, "min_memory": 512},"webdav": {"debug": false, "loglevel": "ERROR"},"zpush": {"loglevel": "ERROR"}}'
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0

Retrieve webtop backend URL
    # Assuming the test is running on a single node cluster
    ${response} =    Run task     module/traefik1/get-route    {"instance":"${webtop_module_id}"}
    Set Global Variable    ${backend_url}    ${response['url']}

Check if webtop works as expected
    Retry test    Backend URL is reachable

Verify webtop frontend title
    ${output} =    Execute Command    curl -s ${backend_url}/webtop/
    Should Contain    ${output}    <title>NethService Collaboration</title>

Login to webtop as user u1@domain.test
    Login as u1

Check u1 is in the webtop database
    ${uid} =    Get the database id of u1
    Set Global Variable    ${u1_uid}    ${uid}
