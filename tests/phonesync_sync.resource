*** Comments ***
Keywords shared by the phone protocol suites.

*** Settings ***
Library     Collections
Resource    phonesync.resource
Resource    webtop_server.resource

*** Keywords ***
Set up phone suite
    Resolve test environment
    Upload phonesync helper
    Open WebTop once as phone user

Names in
    [Arguments]    ${entries}
    ${names} =    Evaluate    [e['name'] for e in $entries]
    RETURN    ${names}

Hrefs in
    [Arguments]    ${entries}
    ${hrefs} =    Evaluate    [e['href'] for e in $entries]
    RETURN    ${hrefs}

Phone DAV sync
    [Arguments]    ${profile}    ${kind}
    ${r} =    Phonesync    dav    sync    ${profile}    --kind    ${kind}
    Should Not Be True    ${r['full_resync']}    ${profile} had to resync all ${kind}s
    RETURN    ${r}

Phone DAV sync has nothing new
    [Arguments]    ${profile}    ${kind}
    ${r} =    Phone DAV sync    ${profile}    ${kind}
    Should Be Empty    ${r['added']}
    Should Be Empty    ${r['changed']}
    Should Be Empty    ${r['deleted']}
