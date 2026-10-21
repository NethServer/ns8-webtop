*** Settings ***
Test Timeout      5 minutes
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
${TASK_DUE}       2026-07-20T08:00:00Z

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

Contact renamed on phone reaches WebTop
    [Documentation]    Known issue: WebTop updates the first name but keeps the old display name.
    ...                Skipped while it fails; it passes once the server is fixed.
    [Tags]    known-issue    robot:skip-on-failure
    [Template]    Contact renamed on phone reaches WebTop
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

Tasks initial sync
    [Template]    Initial sync
    ios-eas    Tasks
    android-eas    Tasks

Task created on phone reaches WebTop
    [Template]    Task created on phone reaches WebTop
    ios-eas
    android-eas

Task changed in WebTop reaches phone
    [Template]    Task changed in WebTop reaches phone
    ios-eas
    android-eas

Task completed on phone shows completed
    [Template]    Task completed on phone shows completed
    ios-eas    android-eas
    android-eas    ios-eas

Task completed in WebTop reaches phone
    [Template]    Task completed in WebTop reaches phone
    ios-eas
    android-eas

Task deleted in WebTop leaves phone
    [Template]    Task deleted in WebTop leaves phone
    ios-eas
    android-eas

Task deleted on phone leaves WebTop
    [Template]    Task deleted on phone leaves WebTop
    ios-eas
    android-eas

Contact with details reaches WebTop
    [Template]    Contact with details reaches WebTop
    ios-eas
    android-eas

Contact details reach the second phone
    [Template]    Contact details reach the second phone
    ios-eas    android-eas
    android-eas    ios-eas

Large contact photo round-trips
    [Template]    Large contact photo round-trips
    ios-eas    android-eas
    android-eas    ios-eas

All-day event keeps its day
    [Template]    All-day event keeps its day
    ios-eas    android-eas
    android-eas    ios-eas

Recurring event with reminder
    [Template]    Recurring event with reminder
    ios-eas    android-eas
    android-eas    ios-eas

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
    Should Be True    $types & {'7', '15'}    no tasks folder

Initial sync
    [Arguments]    ${profile}    ${class}
    Phone EAS sync    ${profile}    ${class}
    Phone EAS sync has nothing new    ${profile}    ${class}

Phone adds
    [Arguments]    ${profile}    ${class}    ${name}
    IF    '${class}' == 'Tasks'
        ${r} =    Phonesync    eas    add    ${profile}    --class    Tasks    --name    ${name}    --due    ${TASK_DUE}
        RETURN    ${r['server_id']}
    END
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

Contact renamed on phone reaches WebTop
    [Arguments]    ${profile}
    ${name} =    Unique name    ${profile} draft
    ${id} =    Phone adds    ${profile}    Contacts    ${name}
    ${new} =    Unique name    ${profile} final
    Phonesync    eas    change    ${profile}    --class    Contacts    --server-id    ${id}    --name    ${new}
    Contact exists in WebTop    ${new}
    Contact does not exist in WebTop    ${name}

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
    # 12 items with a window of 5 must come in at least 3 pages chained by MoreAvailable
    Should Be True    ${r['pages']} >= 3    expected at least 3 pages, got ${r['pages']}
    Should Be True    ${r['max_page']} <= 5    a page held ${r['max_page']} items, more than the window

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
    # Europe/Rome: one hour ahead of UTC, one more hour in summer
    Should Be Equal As Integers    ${r['added'][0]['tz_bias']}    -60
    Should Be Equal As Integers    ${r['added'][0]['tz_dst_bias']}    -60

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

Task created on phone reaches WebTop
    [Arguments]    ${profile}
    ${name} =    Unique name    ${profile} task
    Phone adds    ${profile}    Tasks    ${name}
    ${task} =    Task in WebTop    ${name}
    Should Be Equal    ${task['due_utc']}    ${TASK_DUE}
    Should Not Be True    ${task['completed']}

Task changed in WebTop reaches phone
    [Arguments]    ${profile}
    Phone EAS sync    ${profile}    Tasks
    ${name} =    Unique name    ${profile} task before
    Create task in WebTop    ${name}    ${TASK_DUE}
    ${r} =    Phone EAS sync    ${profile}    Tasks
    ${names} =    Names in    ${r['added']}
    Should Be Equal    ${names}    ${{[$name]}}
    Should Be Equal    ${r['added'][0]['due']}    ${TASK_DUE}
    ${new} =    Unique name    ${profile} task after
    Rename task in WebTop    ${name}    ${new}
    ${r} =    Phone EAS sync    ${profile}    Tasks
    ${names} =    Names in    ${r['changed']}
    Should Be Equal    ${names}    ${{[$new]}}

Task completed on phone shows completed
    [Arguments]    ${writer}    ${reader}
    Phone EAS sync    ${reader}    Tasks
    ${name} =    Unique name    ${writer} task done
    ${id} =    Phone adds    ${writer}    Tasks    ${name}
    ${r} =    Phone EAS sync    ${reader}    Tasks
    Length Should Be    ${r['added']}    1
    Should Not Be True    ${r['added'][0]['complete']}
    Phonesync    eas    change    ${writer}    --class    Tasks    --server-id    ${id}    --complete
    ${task} =    Task in WebTop    ${name}
    Should Be True    ${task['completed']}
    Should Be Equal    ${task['status']}    CO
    ${r} =    Phone EAS sync    ${reader}    Tasks
    Length Should Be    ${r['changed']}    1    the other phone was not told the task is done
    Should Be True    ${r['changed'][0]['complete']}

Task completed in WebTop reaches phone
    [Arguments]    ${profile}
    Phone EAS sync    ${profile}    Tasks
    ${name} =    Unique name    ${profile} task done in WebTop
    Create task in WebTop    ${name}    ${TASK_DUE}
    ${r} =    Phone EAS sync    ${profile}    Tasks
    Length Should Be    ${r['added']}    1
    Should Not Be True    ${r['added'][0]['complete']}
    Complete task in WebTop    ${name}
    ${r} =    Phone EAS sync    ${profile}    Tasks
    Length Should Be    ${r['changed']}    1    the phone was not told the task is done
    Should Be True    ${r['changed'][0]['complete']}

Task deleted in WebTop leaves phone
    [Arguments]    ${profile}
    Phone EAS sync    ${profile}    Tasks
    ${name} =    Unique name    ${profile} task doomed
    Create task in WebTop    ${name}    ${TASK_DUE}
    ${r} =    Phone EAS sync    ${profile}    Tasks
    ${ids} =    Server ids in    ${r['added']}
    Length Should Be    ${ids}    1
    Delete task in WebTop    ${name}
    ${r} =    Phone EAS sync    ${profile}    Tasks
    Should Be Equal    ${r['deleted']}    ${ids}

Task deleted on phone leaves WebTop
    [Arguments]    ${profile}
    ${name} =    Unique name    ${profile} task removed
    ${id} =    Phone adds    ${profile}    Tasks    ${name}
    Task in WebTop    ${name}
    Phonesync    eas    delete    ${profile}    --class    Tasks    --server-id    ${id}
    Task does not exist in WebTop    ${name}

Contact with details reaches WebTop
    [Arguments]    ${profile}
    ${name} =    Unique name    ${profile} detailed
    ${json} =    Evaluate    json.dumps($DETAILS)    modules=json
    Phonesync    eas    add    ${profile}    --class    Contacts    --name    ${name}    --fields    ${json}
    ${got} =    Contact fields in WebTop    ${name}
    ${expected} =    Expected details
    Dictionaries Should Be Equal    ${got}    ${expected}

Contact details reach the second phone
    [Arguments]    ${writer}    ${reader}
    Phone EAS sync    ${reader}    Contacts
    ${name} =    Unique name    from ${writer} detailed
    ${json} =    Evaluate    json.dumps($DETAILS)    modules=json
    Phonesync    eas    add    ${writer}    --class    Contacts    --name    ${name}    --fields    ${json}
    ${r} =    Phone EAS sync    ${reader}    Contacts
    Length Should Be    ${r['added']}    1
    ${expected} =    Expected details
    Dictionaries Should Be Equal    ${r['added'][0]['fields']}    ${expected}

All-day event keeps its day
    [Arguments]    ${writer}    ${reader}
    Phone EAS sync    ${reader}    Calendar
    ${name} =    Unique name    ${writer} holiday
    Phonesync    eas    add    ${writer}    --class    Calendar    --name    ${name}
    ...    --start    2026-07-15    --end    2026-07-16    --tz    ${TZ}    --all-day
    ${db} =    Event details in WebTop    ${name}
    Should Be True    ${db['all_day']}
    Should Be Equal    ${db['start_local']}    2026-07-15T00:00:00
    ${r} =    Phone EAS sync    ${reader}    Calendar
    Length Should Be    ${r['added']}    1
    Should Be True    ${r['added'][0]['details']['all_day']}
    Should Be Equal    ${r['added'][0]['details']['start']}    2026-07-15

Recurring event with reminder
    [Arguments]    ${writer}    ${reader}
    Phone EAS sync    ${reader}    Calendar
    ${name} =    Unique name    ${writer} weekly
    Phonesync    eas    add    ${writer}    --class    Calendar    --name    ${name}
    ...    --start    ${LOCAL_START}    --end    ${LOCAL_END}    --tz    ${TZ}    --rrule    FREQ=WEEKLY;COUNT=4    --alarm    15
    ${db} =    Event details in WebTop    ${name}
    Should Contain    ${db['rrule']}    FREQ=WEEKLY
    Should Contain    ${db['rrule']}    COUNT=4
    Should Be Equal As Integers    ${db['reminder']}    15
    ${r} =    Phone EAS sync    ${reader}    Calendar
    Length Should Be    ${r['added']}    1
    Should Be Equal    ${r['added'][0]['details']['rrule']}    FREQ=WEEKLY;COUNT=4
    Should Be Equal As Integers    ${r['added'][0]['details']['alarm']}    15

Large contact photo round-trips
    [Arguments]    ${writer}    ${reader}
    Phone EAS sync    ${reader}    Contacts
    ${name} =    Unique name    ${writer} large photo
    Phonesync    eas    add    ${writer}    --class    Contacts    --name    ${name}    --fields    {"photo": "large"}
    ${size} =    Photo size    large
    ${got} =    Contact fields in WebTop    ${name}
    Should Be Equal As Integers    ${got['photo_size']}    ${size}
    ${r} =    Phone EAS sync    ${reader}    Contacts
    Length Should Be    ${r['added']}    1
    Should Be Equal As Integers    ${r['added'][0]['fields']['photo_size']}    ${size}
