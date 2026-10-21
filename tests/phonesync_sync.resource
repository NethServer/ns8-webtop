*** Comments ***
Keywords shared by the phone protocol suites.

*** Settings ***
Library     Collections
Resource    phonesync.resource
Resource    webtop_server.resource

*** Variables ***
&{DETAILS}        mobile=+39 333 1234567    email=niccolo@example.test    street=Via Roma 1    city=Pesaro    photo=png

*** Keywords ***
Expected details
    &{expected} =    Evaluate    dict(mobile=$DETAILS['mobile'], email=$DETAILS['email'], street=$DETAILS['street'], city=$DETAILS['city'], photo_size=len(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGBgAAAABQABpfZFQAAAAABJRU5ErkJggg==')))    modules=base64
    RETURN    ${expected}

Set up phone suite
    Resolve test environment
    Upload phonesync helper
    Open WebTop once as phone user

Start from unpaired phones
    # leftovers of an earlier run on a development machine would break "exactly once" checks
    Reset phones
    Delete all test items in WebTop
    Delete pre-upgrade items in WebTop

Names in
    [Arguments]    ${entries}
    ${names} =    Evaluate    [e['name'] for e in $entries]
    RETURN    ${names}

Hrefs in
    [Arguments]    ${entries}
    ${hrefs} =    Evaluate    [e['href'] for e in $entries]
    RETURN    ${hrefs}

Wait for the next WebTop second
    # WebTop etags, ctags and sync tokens are timestamps with one-second resolution:
    # a write in the same second as a phone's sync could look unchanged to that phone
    Sleep    1.1s

Phone DAV sync
    [Arguments]    ${profile}    ${kind}
    ${r} =    Phonesync    dav    sync    ${profile}    --kind    ${kind}
    Should Not Be True    ${r['full_resync']}    ${profile} had to resync all ${kind}s
    Wait for the next WebTop second
    RETURN    ${r}

Phone DAV sync has nothing new
    [Arguments]    ${profile}    ${kind}
    ${r} =    Phone DAV sync    ${profile}    ${kind}
    Should Be Empty    ${r['added']}
    Should Be Empty    ${r['changed']}
    Should Be Empty    ${r['deleted']}

Server ids in
    [Arguments]    ${entries}
    ${ids} =    Evaluate    [e['server_id'] for e in $entries]
    RETURN    ${ids}

Phone EAS sync
    [Arguments]    ${profile}    ${class}    @{args}
    ${r} =    Phonesync    eas    sync    ${profile}    --class    ${class}    @{args}
    Should Not Be True    ${r['full_resync']}    ${profile} had to resync all ${class}
    Wait for the next WebTop second
    RETURN    ${r}

Phone EAS sync has nothing new
    [Arguments]    ${profile}    ${class}
    ${r} =    Phone EAS sync    ${profile}    ${class}
    Should Be Empty    ${r['added']}
    Should Be Empty    ${r['changed']}
    Should Be Empty    ${r['deleted']}

Pre-upgrade name
    [Arguments]    ${profile}    ${what}
    RETURN    pre-upgrade-${profile}-${what}

Skip unless update scenario
    Skip If    '${SCENARIO}' != 'update'    scenario is ${SCENARIO}, no upgrade to survive
