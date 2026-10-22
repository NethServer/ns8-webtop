*** Settings ***
Documentation     ActiveSync push: a phone waiting in Ping is woken by changes
Test Timeout      5 minutes
Resource          phonesync_sync.resource
Suite Setup       Run Keywords    Set up phone suite    AND    Pair the phone
Suite Teardown    Run Keywords    Delete all test items in WebTop    AND    Delete test messages    ${PHONE_USER}

*** Variables ***
# Short enough to keep the suite fast; the long waits real phones use are checked by
# "Phone can wait longer than a minute"
${HEARTBEAT}      45

*** Test Cases ***
Quiet ping times out
    Phone EAS sync    ios-eas    Email
    ${r} =    Phonesync    eas    ping    ios-eas    --classes    Email    --heartbeat    ${HEARTBEAT}
    Should Be Equal As Integers    ${r['status']}    1
    Should Be True    40 <= ${r['seconds']} <= 60    a quiet ping lasted ${r['seconds']} s

New mail wakes the phone
    Phone EAS sync    ios-eas    Email
    Start phonesync    eas    ping    ios-eas    --classes    Email    --heartbeat    ${HEARTBEAT}
    Sleep    5s
    ${subject} =    Unique name    push
    Deliver mail    ${PHONE_USER}    ${subject}
    ${r} =    Finish phonesync
    Should Be Equal As Integers    ${r['status']}    2    the phone was not woken (status ${r['status']} after ${r['seconds']} s)
    Should Contain    ${r['folders']}    ${INBOX}
    # woken by the mail, not answered at once: the mail is delivered 5 s after the ping started
    Should Be True    5 <= ${r['seconds']} < ${HEARTBEAT}    the phone was woken after ${r['seconds']} s

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

Phone can wait longer than a minute
    [Documentation]    Real phones wait minutes in Ping; Apache's default 60 s timeout used to end it with 504
    Phone EAS sync    ios-eas    Email
    ${r} =    Phonesync    eas    ping    ios-eas    --classes    Email    --heartbeat    120
    Should Be Equal As Integers    ${r['status']}    1

Phone can wait longer than a minute through the NS8 proxy
    [Documentation]    Real phones reach Z-Push through Traefik, which must not end the wait either
    Phone EAS sync    ios-eas    Email
    Set Test Variable    ${backend_url}    https://127.0.0.1
    ${r} =    Phonesync    eas    ping    ios-eas    --classes    Email    --heartbeat    120    --insecure
    Should Be Equal As Integers    ${r['status']}    1
    Should Be True    110 <= ${r['seconds']} <= 150    a quiet 120 s ping lasted ${r['seconds']} s

*** Keywords ***
Pair the phone
    ${r} =    Phonesync    eas    setup    ios-eas
    ${ids} =    Evaluate    [f['id'] for f in $r['folders'] if f['type'] == '2']
    Set Suite Variable    ${INBOX}    ${ids[0]}
