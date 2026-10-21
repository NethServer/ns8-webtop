*** Settings ***
Documentation     ActiveSync push: a phone waiting in Ping is woken by changes
Test Timeout      5 minutes
Resource          phonesync_sync.resource
Suite Setup       Run Keywords    Set up phone suite    AND    Pair the phone
Suite Teardown    Run Keywords    Delete all test items in WebTop    AND    Delete test messages    ${PHONE_USER}

*** Variables ***
# ActiveSync allows 60 s and more, but Apache in front of Z-Push answers 504 after 60 s today
# (see "Phone can wait longer than a minute"), so the working cases stay below that
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
    [Documentation]    Known issue: Apache in front of Z-Push ends requests after 60 s with 504, so the
    ...                multi-minute waits real phones use fail and push falls back to polling. Skipped while it fails.
    [Tags]    known-issue    robot:skip-on-failure
    Phone EAS sync    ios-eas    Email
    ${r} =    Phonesync    eas    ping    ios-eas    --classes    Email    --heartbeat    120
    Should Be Equal As Integers    ${r['status']}    1

*** Keywords ***
Pair the phone
    ${r} =    Phonesync    eas    setup    ios-eas
    ${ids} =    Evaluate    [f['id'] for f in $r['folders'] if f['type'] == '2']
    Set Suite Variable    ${INBOX}    ${ids[0]}
