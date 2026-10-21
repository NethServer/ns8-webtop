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
