*** Settings ***
Test Timeout      5 minutes
Documentation     Calendar over CalDAV, as DAVx5 (Android) and iOS sync it
Resource          phonesync_sync.resource
Suite Setup       Set up phone suite
Suite Teardown    Delete all test items in WebTop

*** Variables ***
# Summer time: 10:00 in Rome is 08:00 UTC
${LOCAL_START}    2026-07-15T10:00:00
${LOCAL_END}      2026-07-15T11:00:00
${TZ}             Europe/Rome
${UTC_START}      2026-07-15T08:00:00Z
${UTC_END}        2026-07-15T09:00:00Z

*** Test Cases ***

Phone discovers calendar
    [Template]    Phone discovers calendar
    davx5
    ios-dav

Phone initial sync
    [Template]    Phone initial sync
    davx5
    ios-dav

Event created on phone reaches WebTop
    [Template]    Event created on phone reaches WebTop
    davx5
    ios-dav

Phone reads event back
    [Template]    Phone reads event back
    davx5
    ios-dav

Event modified on phone reaches WebTop
    [Template]    Event modified on phone reaches WebTop
    davx5
    ios-dav

Non-ASCII event round-trips
    [Template]    Non-ASCII event round-trips
    davx5
    ios-dav

Event changed in WebTop reaches phone
    [Template]    Event changed in WebTop reaches phone
    davx5
    ios-dav

Event deleted in WebTop leaves phone
    [Template]    Event deleted in WebTop leaves phone
    davx5
    ios-dav

All-day event keeps its day
    [Template]    All-day event keeps its day
    davx5    ios-dav
    ios-dav    davx5

Recurring event with reminder
    [Template]    Recurring event with reminder
    davx5    ios-dav
    ios-dav    davx5

Event deleted on phone leaves WebTop
    [Template]    Event deleted on phone leaves WebTop
    davx5
    ios-dav

Second phone sees first phone's event
    [Template]    Second phone sees first phone's event
    davx5    ios-dav
    ios-dav    davx5

*** Keywords ***
Phone creates event
    [Arguments]    ${profile}    ${name}
    ${r} =    Phonesync    dav    put    ${profile}    --kind    event    --name    ${name}
    ...    --start    ${LOCAL_START}    --end    ${LOCAL_END}    --tz    ${TZ}
    RETURN    ${r}

Phone discovers calendar
    [Arguments]    ${profile}
    ${r} =    Phonesync    dav    discover    ${profile}
    Should Not Be Empty    ${r['calendars']}

Phone initial sync
    [Arguments]    ${profile}
    Phone DAV sync    ${profile}    event
    Phone DAV sync has nothing new    ${profile}    event

Event created on phone reaches WebTop
    [Arguments]    ${profile}
    ${name} =    Unique name    ${profile} meeting
    Phone creates event    ${profile}    ${name}
    ${event} =    Event in WebTop    ${name}
    Should Be Equal    ${event['start_utc']}    ${UTC_START}

Phone reads event back
    [Arguments]    ${profile}
    ${name} =    Unique name    ${profile} readback
    ${r} =    Phone creates event    ${profile}    ${name}
    ${got} =    Phonesync    dav    get    ${profile}    --href    ${r['href']}
    Should Be Equal    ${got['name']}    ${name}
    Should Be Equal    ${got['start']}    ${LOCAL_START}
    Should Be Equal    ${got['tz']}    ${TZ}

Event modified on phone reaches WebTop
    [Arguments]    ${profile}
    ${name} =    Unique name    ${profile} draft
    ${r} =    Phone creates event    ${profile}    ${name}
    ${new} =    Unique name    ${profile} final
    Phonesync    dav    update    ${profile}    --href    ${r['href']}    --name    ${new}
    ${event} =    Event in WebTop    ${new}
    Should Be Equal    ${event['start_utc']}    ${UTC_START}
    Event does not exist in WebTop    ${name}

Non-ASCII event round-trips
    [Arguments]    ${profile}
    ${name} =    Unique name    Riunione Niccolò Ürsula ☕
    ${r} =    Phone creates event    ${profile}    ${name}
    Event in WebTop    ${name}
    ${got} =    Phonesync    dav    get    ${profile}    --href    ${r['href']}
    Should Be Equal    ${got['name']}    ${name}

Event changed in WebTop reaches phone
    [Arguments]    ${profile}
    Phone DAV sync    ${profile}    event
    ${name} =    Unique name    ${profile} before
    Create event in WebTop    ${name}    ${UTC_START}    ${UTC_END}
    ${r} =    Phone DAV sync    ${profile}    event
    ${names} =    Names in    ${r['added']}
    Should Be Equal    ${names}    ${{[$name]}}
    ${new} =    Unique name    ${profile} after
    Rename event in WebTop    ${name}    ${new}
    ${r} =    Phone DAV sync    ${profile}    event
    ${names} =    Names in    ${r['changed']}
    Should Be Equal    ${names}    ${{[$new]}}

Event deleted in WebTop leaves phone
    [Arguments]    ${profile}
    Phone DAV sync    ${profile}    event
    ${name} =    Unique name    ${profile} cancelled
    Create event in WebTop    ${name}    ${UTC_START}    ${UTC_END}
    ${r} =    Phone DAV sync    ${profile}    event
    ${hrefs} =    Hrefs in    ${r['added']}
    Length Should Be    ${hrefs}    1
    Delete event in WebTop    ${name}
    ${r} =    Phone DAV sync    ${profile}    event
    Should Be Equal    ${r['deleted']}    ${hrefs}

Event deleted on phone leaves WebTop
    [Arguments]    ${profile}
    ${name} =    Unique name    ${profile} removed
    ${r} =    Phone creates event    ${profile}    ${name}
    Event in WebTop    ${name}
    Phonesync    dav    delete    ${profile}    --href    ${r['href']}
    Event does not exist in WebTop    ${name}

Second phone sees first phone's event
    [Arguments]    ${writer}    ${reader}
    Phone DAV sync    ${reader}    event
    ${name} =    Unique name    from ${writer}
    Phone creates event    ${writer}    ${name}
    ${r} =    Phone DAV sync    ${reader}    event
    ${names} =    Names in    ${r['added']}
    Should Be Equal    ${names}    ${{[$name]}}

Event read by second phone
    [Arguments]    ${reader}
    ${r} =    Phone DAV sync    ${reader}    event
    Length Should Be    ${r['added']}    1
    ${got} =    Phonesync    dav    get    ${reader}    --href    ${r['added'][0]['href']}
    RETURN    ${got['details']}

All-day event keeps its day
    [Arguments]    ${writer}    ${reader}
    Phone DAV sync    ${reader}    event
    ${name} =    Unique name    ${writer} holiday
    Phonesync    dav    put    ${writer}    --kind    event    --name    ${name}
    ...    --start    2026-07-15    --end    2026-07-16    --all-day
    ${db} =    Event details in WebTop    ${name}
    Should Be True    ${db['all_day']}
    Should Be Equal    ${db['start_local']}    2026-07-15T00:00:00
    ${got} =    Event read by second phone    ${reader}
    Should Be True    ${got['all_day']}
    Should Be Equal    ${got['start']}    2026-07-15

Recurring event with reminder
    [Arguments]    ${writer}    ${reader}
    Phone DAV sync    ${reader}    event
    ${name} =    Unique name    ${writer} weekly
    Phonesync    dav    put    ${writer}    --kind    event    --name    ${name}
    ...    --start    ${LOCAL_START}    --end    ${LOCAL_END}    --tz    ${TZ}    --rrule    FREQ=WEEKLY;COUNT=4    --alarm    15
    ${db} =    Event details in WebTop    ${name}
    Should Contain    ${db['rrule']}    FREQ=WEEKLY
    Should Contain    ${db['rrule']}    COUNT=4
    Should Be Equal As Integers    ${db['reminder']}    15
    ${got} =    Event read by second phone    ${reader}
    Should Contain    ${got['rrule']}    FREQ=WEEKLY
    Should Contain    ${got['rrule']}    COUNT=4
    Should Be Equal As Integers    ${got['alarm']}    15
