*** Settings ***
Library    SSHLibrary
Resource    api.resource

*** Variables ***
${curl_timeout}    9

*** Keywords ***
Retry test
    [Arguments]    ${keyword}
    Wait Until Keyword Succeeds    60 seconds    1 second    ${keyword}

Backend URL is reachable
    ${rc} =    Execute Command    curl -f ${backend_url}/webtop/
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0


*** Test Cases ***
Check if webtop is installed correctly
    ${output}  ${rc} =    Execute Command    add-module ${IMAGE_URL} 1
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
    ${output}    ${err}    ${rc} =    Execute Command
    ...    curl -L -v -X POST ${backend_url}/webtop/login -d "wtusername=u1@domain.test" -d "wtpassword=Nethesis,1234" -d "location=${backend_url}/webtop/" -d "wtdomain=NethServer" -b cookies.txt -c cookies.txt -H "User-Agent: curl/8.15.0" -H "Referer: ${backend_url}/webtop/" -H "Accept: */*"
    ...    return_rc=True
    ...    return_stdout=True
    ...    return_stderr=True
    Log    Curl stdout: ${output}
    Log    Curl stderr: ${err}
    Log    Curl rc: ${rc}
    # webtop redirect to https://
    #Should Be Equal As Integers    ${rc}    35
    Should Contain    ${err}    HTTP/1.1 302
    Should Contain    ${err}    Clear auth, redirects scheme from HTTP to httpsIssue another request to this URL:
