*** Settings ***
Documentation     ActiveSync push: a phone waiting in Ping is woken by changes
Test Timeout      5 minutes
Resource          phonesync_sync.resource
Suite Setup       Run Keywords    Set up phone suite    AND    Phonesync    eas    setup    ios-eas
Suite Teardown    Run Keywords    Delete all test items in WebTop    AND    Delete test messages    ${PHONE_USER}

*** Variables ***
${HEARTBEAT}      45

*** Test Cases ***
Quiet ping times out
    Phone EAS sync    ios-eas    Email
    ${r} =    Phonesync    eas    ping    ios-eas    --classes    Email    --heartbeat    ${HEARTBEAT}
    Should Be Equal As Integers    ${r['status']}    1
    Should Be True    40 <= ${r['seconds']} <= 60    a quiet ping lasted ${r['seconds']} s

New mail wakes the phone
    Phone EAS sync    ios-eas    Email
    ${inbox} =    Inbox id    ios-eas
    Start phonesync    eas    ping    ios-eas    --classes    Email    --heartbeat    ${HEARTBEAT}
    Sleep    5s
    ${subject} =    Unique name    push
    Deliver mail    ${PHONE_USER}    ${subject}
    ${r} =    Finish phonesync
    Should Be Equal As Integers    ${r['status']}    2    the phone was not woken (status ${r['status']} after ${r['seconds']} s)
    Should Contain    ${r['folders']}    ${inbox}
    Should Be True    ${r['seconds']} < ${HEARTBEAT}

Contact change wakes the phone
    [Documentation]    Known issue: Sonicle's backend reads the folder state once per request,
    ...                so changes made in WebTop never wake a waiting phone. Skipped while it fails.
    [Tags]    known-issue    robot:skip-on-failure
    Phone EAS sync    ios-eas    Contacts
    Start phonesync    eas    ping    ios-eas    --classes    Contacts    --heartbeat    ${HEARTBEAT}
    Sleep    5s
    ${name} =    Unique name    push contact
    Create contact in WebTop    ${name}
    ${r} =    Finish phonesync
    Should Be Equal As Integers    ${r['status']}    2    the phone was not woken (status ${r['status']} after ${r['seconds']} s)

*** Keywords ***
Inbox id
    [Arguments]    ${profile}
    ${r} =    Phonesync    eas    setup    ${profile}
    ${ids} =    Evaluate    [f['id'] for f in $r['folders'] if f['type'] == '2']
    RETURN    ${ids[0]}
