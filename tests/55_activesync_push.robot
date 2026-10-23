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
    Phone EAS sync    ios-eas    Contacts
    Start phonesync    eas    ping    ios-eas    --classes    Contacts    --heartbeat    ${HEARTBEAT}
    Sleep    5s
    ${name} =    Unique name    push contact
    Create contact in WebTop    ${name}
    ${r} =    Finish phonesync
    Should Be Equal As Integers    ${r['status']}    2    the phone was not woken (status ${r['status']} after ${r['seconds']} s)

Event change wakes the phone
    Phone EAS sync    ios-eas    Calendar
    Start phonesync    eas    ping    ios-eas    --classes    Calendar    --heartbeat    ${HEARTBEAT}
    Sleep    5s
    ${name} =    Unique name    push event
    Create event in WebTop    ${name}    2026-07-15T08:00:00Z    2026-07-15T09:00:00Z
    ${r} =    Finish phonesync
    Should Be Equal As Integers    ${r['status']}    2    the phone was not woken (status ${r['status']} after ${r['seconds']} s)
    Should Be True    5 <= ${r['seconds']} < ${HEARTBEAT}    the phone was woken after ${r['seconds']} s

Task change wakes the phone
    Phone EAS sync    ios-eas    Tasks
    Start phonesync    eas    ping    ios-eas    --classes    Tasks    --heartbeat    ${HEARTBEAT}
    Sleep    5s
    ${name} =    Unique name    push task
    Create task in WebTop    ${name}    2026-07-20T08:00:00Z
    ${r} =    Finish phonesync
    Should Be Equal As Integers    ${r['status']}    2    the phone was not woken (status ${r['status']} after ${r['seconds']} s)
    Should Be True    5 <= ${r['seconds']} < ${HEARTBEAT}    the phone was woken after ${r['seconds']} s

Quiet ping on WebTop folders times out
    # nothing changes: the phone must not be woken early, and the server must not answer at once
    FOR    ${class}    IN    Contacts    Calendar    Tasks
        Phone EAS sync    ios-eas    ${class}
    END
    ${r} =    Phonesync    eas    ping    ios-eas    --classes    Contacts,Calendar,Tasks    --heartbeat    ${HEARTBEAT}
    Should Be Equal As Integers    ${r['status']}    1
    Should Be True    40 <= ${r['seconds']} <= 60    a quiet ping lasted ${r['seconds']} s

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
