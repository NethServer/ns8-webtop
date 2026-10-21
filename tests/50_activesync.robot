*** Settings ***
Documentation     Contacts, calendar and mail over ActiveSync, as the iOS Mail app and Android mail apps sync them
Resource          phonesync_sync.resource
Suite Setup       Set up phone suite
Suite Teardown    Run Keywords    Delete all test items in WebTop
...               AND    Delete test messages    ${PHONE_USER}
...               AND    Delete test messages    ${MAIL_RECIPIENT}

*** Variables ***
# Summer time: 10:00 in Rome is 08:00 UTC
${LOCAL_START}    2026-07-15T10:00:00
${LOCAL_END}      2026-07-15T11:00:00
${TZ}             Europe/Rome
${UTC_START}      2026-07-15T08:00:00Z
${UTC_END}        2026-07-15T09:00:00Z

*** Test Cases ***
Phone sets up account
    [Template]    Phone sets up account
    ios-eas
    android-eas

Contacts initial sync
    [Template]    Initial sync
    ios-eas    Contacts
    android-eas    Contacts

Contact created on phone reaches WebTop
    [Template]    Contact created on phone reaches WebTop
    ios-eas
    android-eas

Non-ASCII contact round-trips
    [Template]    Non-ASCII contact round-trips
    ios-eas    android-eas
    android-eas    ios-eas

Contact changed in WebTop reaches phone
    [Template]    Contact changed in WebTop reaches phone
    ios-eas
    android-eas

Contact deleted in WebTop leaves phone
    [Template]    Contact deleted in WebTop leaves phone
    ios-eas
    android-eas

Contact deleted on phone leaves WebTop
    [Template]    Contact deleted on phone leaves WebTop
    ios-eas
    android-eas

Second phone sees first phone's contact
    [Template]    Second phone sees first phone's item
    ios-eas    android-eas    Contacts
    android-eas    ios-eas    Contacts

Large address book pages
    [Template]    Large address book pages
    ios-eas
    android-eas

Calendar initial sync
    [Template]    Initial sync
    ios-eas    Calendar
    android-eas    Calendar

Event created on phone reaches WebTop
    [Template]    Event created on phone reaches WebTop
    ios-eas
    android-eas

Phone reads event back
    [Template]    Phone reads event back
    ios-eas    android-eas
    android-eas    ios-eas

Event modified on phone reaches WebTop
    [Template]    Event modified on phone reaches WebTop
    ios-eas
    android-eas

Non-ASCII event round-trips
    [Template]    Non-ASCII event round-trips
    ios-eas    android-eas
    android-eas    ios-eas

Event changed in WebTop reaches phone
    [Template]    Event changed in WebTop reaches phone
    ios-eas
    android-eas

Event deleted in WebTop leaves phone
    [Template]    Event deleted in WebTop leaves phone
    ios-eas
    android-eas

Event deleted on phone leaves WebTop
    [Template]    Event deleted on phone leaves WebTop
    ios-eas
    android-eas

Second phone sees first phone's event
    [Template]    Second phone sees first phone's item
    ios-eas    android-eas    Calendar
    android-eas    ios-eas    Calendar

Phone reads a message
    Phone EAS sync    ios-eas    Email
    ${subject} =    Unique name    inbox
    Put message in mailbox    ${PHONE_USER}    ${subject}    Hello from the e2e test
    ${r} =    Phone EAS sync    ios-eas    Email
    ${names} =    Names in    ${r['added']}
    Should Be Equal    ${names}    ${{[$subject]}}
    ${mail} =    Phonesync    eas    fetch    ios-eas    --server-id    ${r['added'][0]['server_id']}
    Should Be Equal    ${mail['subject']}    ${subject}
    Should Be Equal    ${mail['body']}    Hello from the e2e test

Phone sends a message
    ${subject} =    Unique name    outgoing ☕
    Phonesync    eas    send    ios-eas    --to    ${MAIL_RECIPIENT}    --subject    ${subject}    --body    Sent from the e2e phone
    Mailbox has message    ${MAIL_RECIPIENT}    ${subject}

*** Keywords ***
Phone sets up account
    [Arguments]    ${profile}
    ${r} =    Phonesync    eas    setup    ${profile}
    ${types} =    Evaluate    {f['type'] for f in $r['folders']}
    Should Contain    ${types}    2    no Inbox
    Should Be True    $types & {'9', '14'}    no address book folder
    Should Be True    $types & {'8', '13'}    no calendar folder

Initial sync
    [Arguments]    ${profile}    ${class}
    Phone EAS sync    ${profile}    ${class}
    Phone EAS sync has nothing new    ${profile}    ${class}

Phone adds
    [Arguments]    ${profile}    ${class}    ${name}
    IF    '${class}' == 'Calendar'
        ${r} =    Phonesync    eas    add    ${profile}    --class    Calendar    --name    ${name}
        ...    --start    ${LOCAL_START}    --end    ${LOCAL_END}    --tz    ${TZ}
    ELSE
        ${r} =    Phonesync    eas    add    ${profile}    --class    ${class}    --name    ${name}
    END
    RETURN    ${r['server_id']}

Contact created on phone reaches WebTop
    [Arguments]    ${profile}
    ${name} =    Unique name    ${profile} new
    Phone adds    ${profile}    Contacts    ${name}
    Contact exists in WebTop    ${name}

Non-ASCII contact round-trips
    [Arguments]    ${writer}    ${reader}
    Phone EAS sync    ${reader}    Contacts
    ${name} =    Unique name    Niccolò Ürsula ☕
    Phone adds    ${writer}    Contacts    ${name}
    Contact exists in WebTop    ${name}
    ${r} =    Phone EAS sync    ${reader}    Contacts
    ${names} =    Names in    ${r['added']}
    Should Be Equal    ${names}    ${{[$name]}}

Contact changed in WebTop reaches phone
    [Arguments]    ${profile}
    Phone EAS sync    ${profile}    Contacts
    ${name} =    Unique name    ${profile} before
    Create contact in WebTop    ${name}
    ${r} =    Phone EAS sync    ${profile}    Contacts
    ${names} =    Names in    ${r['added']}
    Should Be Equal    ${names}    ${{[$name]}}
    ${new} =    Unique name    ${profile} after
    Rename contact in WebTop    ${name}    ${new}
    ${r} =    Phone EAS sync    ${profile}    Contacts
    ${names} =    Names in    ${r['changed']}
    Should Be Equal    ${names}    ${{[$new]}}

Contact deleted in WebTop leaves phone
    [Arguments]    ${profile}
    Phone EAS sync    ${profile}    Contacts
    ${name} =    Unique name    ${profile} doomed
    Create contact in WebTop    ${name}
    ${r} =    Phone EAS sync    ${profile}    Contacts
    ${ids} =    Server ids in    ${r['added']}
    Length Should Be    ${ids}    1
    Delete contact in WebTop    ${name}
    ${r} =    Phone EAS sync    ${profile}    Contacts
    Should Be Equal    ${r['deleted']}    ${ids}

Contact deleted on phone leaves WebTop
    [Arguments]    ${profile}
    ${name} =    Unique name    ${profile} removed
    ${id} =    Phone adds    ${profile}    Contacts    ${name}
    Contact exists in WebTop    ${name}
    Phonesync    eas    delete    ${profile}    --class    Contacts    --server-id    ${id}
    Contact does not exist in WebTop    ${name}

Second phone sees first phone's item
    [Arguments]    ${writer}    ${reader}    ${class}
    Phone EAS sync    ${reader}    ${class}
    ${name} =    Unique name    from ${writer}
    Phone adds    ${writer}    ${class}    ${name}
    ${r} =    Phone EAS sync    ${reader}    ${class}
    ${names} =    Names in    ${r['added']}
    Should Be Equal    ${names}    ${{[$name]}}

Large address book pages
    [Arguments]    ${profile}
    Phone EAS sync    ${profile}    Contacts
    @{created} =    Create List
    FOR    ${i}    IN RANGE    12
        ${name} =    Unique name    ${profile} bulk ${i}
        Create contact in WebTop    ${name}
        Append To List    ${created}    ${name}
    END
    ${r} =    Phone EAS sync    ${profile}    Contacts    --window    5
    ${names} =    Names in    ${r['added']}
    Lists Should Be Equal    ${names}    ${created}    ignore_order=True

Event created on phone reaches WebTop
    [Arguments]    ${profile}
    ${name} =    Unique name    ${profile} meeting
    Phone adds    ${profile}    Calendar    ${name}
    ${event} =    Event in WebTop    ${name}
    Should Be Equal    ${event['start_utc']}    ${UTC_START}

Phone reads event back
    [Arguments]    ${writer}    ${reader}
    Phone EAS sync    ${reader}    Calendar
    ${name} =    Unique name    ${writer} readback
    Phone adds    ${writer}    Calendar    ${name}
    ${r} =    Phone EAS sync    ${reader}    Calendar
    Length Should Be    ${r['added']}    1
    Should Be Equal    ${r['added'][0]['name']}    ${name}
    Should Be Equal    ${r['added'][0]['start']}    ${UTC_START}

Event modified on phone reaches WebTop
    [Arguments]    ${profile}
    ${name} =    Unique name    ${profile} draft
    ${id} =    Phone adds    ${profile}    Calendar    ${name}
    ${new} =    Unique name    ${profile} final
    Phonesync    eas    change    ${profile}    --class    Calendar    --server-id    ${id}    --name    ${new}
    ${event} =    Event in WebTop    ${new}
    Should Be Equal    ${event['start_utc']}    ${UTC_START}
    Event does not exist in WebTop    ${name}

Non-ASCII event round-trips
    [Arguments]    ${writer}    ${reader}
    Phone EAS sync    ${reader}    Calendar
    ${name} =    Unique name    Riunione Niccolò Ürsula ☕
    Phone adds    ${writer}    Calendar    ${name}
    Event in WebTop    ${name}
    ${r} =    Phone EAS sync    ${reader}    Calendar
    ${names} =    Names in    ${r['added']}
    Should Be Equal    ${names}    ${{[$name]}}

Event changed in WebTop reaches phone
    [Arguments]    ${profile}
    Phone EAS sync    ${profile}    Calendar
    ${name} =    Unique name    ${profile} before
    Create event in WebTop    ${name}    ${UTC_START}    ${UTC_END}
    ${r} =    Phone EAS sync    ${profile}    Calendar
    ${names} =    Names in    ${r['added']}
    Should Be Equal    ${names}    ${{[$name]}}
    ${new} =    Unique name    ${profile} after
    Rename event in WebTop    ${name}    ${new}
    ${r} =    Phone EAS sync    ${profile}    Calendar
    ${names} =    Names in    ${r['changed']}
    Should Be Equal    ${names}    ${{[$new]}}

Event deleted in WebTop leaves phone
    [Arguments]    ${profile}
    Phone EAS sync    ${profile}    Calendar
    ${name} =    Unique name    ${profile} cancelled
    Create event in WebTop    ${name}    ${UTC_START}    ${UTC_END}
    ${r} =    Phone EAS sync    ${profile}    Calendar
    ${ids} =    Server ids in    ${r['added']}
    Length Should Be    ${ids}    1
    Delete event in WebTop    ${name}
    ${r} =    Phone EAS sync    ${profile}    Calendar
    Should Be Equal    ${r['deleted']}    ${ids}

Event deleted on phone leaves WebTop
    [Arguments]    ${profile}
    ${name} =    Unique name    ${profile} removed
    ${id} =    Phone adds    ${profile}    Calendar    ${name}
    Event in WebTop    ${name}
    Phonesync    eas    delete    ${profile}    --class    Calendar    --server-id    ${id}
    Event does not exist in WebTop    ${name}
