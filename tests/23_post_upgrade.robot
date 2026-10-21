*** Settings ***
Documentation     Phones paired by 21_pre_upgrade.robot keep working right after 22_update.robot, before any other suite changes data
Test Timeout      5 minutes
Resource          phonesync_sync.resource
Suite Setup       Run Keywords    Skip unless update scenario    AND    Set up phone suite
Suite Teardown    Run Keywords    Delete all test items in WebTop    AND    Delete pre-upgrade items in WebTop

*** Variables ***
@{PROFILES}       davx5    ios-dav    ios-eas    android-eas

*** Test Cases ***
Paired phone keeps syncing after upgrade
    [Template]    Paired phone keeps syncing
    davx5    contact
    davx5    event
    ios-dav    contact
    ios-dav    event
    ios-eas    Contacts
    ios-eas    Calendar
    android-eas    Contacts
    android-eas    Calendar

Pre-upgrade items survive in WebTop
    FOR    ${profile}    IN    @{PROFILES}
        ${contact} =    Pre-upgrade name    ${profile}    contact
        ${event} =    Pre-upgrade name    ${profile}    event
        Contact exists in WebTop    ${contact}
        ${found} =    Event in WebTop    ${event}
        Should Be Equal    ${found['start_utc']}    2026-07-15T08:00:00Z
    END

Phones still know every pre-upgrade item once
    [Template]    Phone knows every pre-upgrade item once
    davx5
    ios-dav
    ios-eas
    android-eas

DAV phone edits a pre-upgrade contact
    [Template]    DAV phone edits its pre-upgrade contact
    davx5
    ios-dav

ActiveSync phone edits a pre-upgrade event
    [Template]    ActiveSync phone edits its pre-upgrade event
    ios-eas
    android-eas

*** Keywords ***
Paired phone keeps syncing
    [Arguments]    ${profile}    ${what}
    IF    $profile.endswith('-eas')
        ${r} =    Phone EAS sync    ${profile}    ${what}
        Should Be Equal As Integers    ${r['status']}    1
    ELSE
        ${r} =    Phone DAV sync    ${profile}    ${what}
    END
    Should Be Empty    ${r['added']}
    Should Be Empty    ${r['changed']}
    Should Be Empty    ${r['deleted']}

Phone knows every pre-upgrade item once
    [Arguments]    ${phone}
    FOR    ${owner}    IN    @{PROFILES}
        ${contact} =    Pre-upgrade name    ${owner}    contact
        ${event} =    Pre-upgrade name    ${owner}    event
        IF    $phone.endswith('-eas')
            Phonesync    eas    lookup    ${phone}    --class    Contacts    --name    ${contact}
            Phonesync    eas    lookup    ${phone}    --class    Calendar    --name    ${event}
        ELSE
            # the stored href must still resolve on the server, not just sit in the phone's state
            ${r} =    Phonesync    dav    lookup    ${phone}    --kind    contact    --name    ${contact}
            ${got} =    Phonesync    dav    get    ${phone}    --href    ${r['href']}
            Should Be Equal    ${got['name']}    ${contact}
            ${r} =    Phonesync    dav    lookup    ${phone}    --kind    event    --name    ${event}
            ${got} =    Phonesync    dav    get    ${phone}    --href    ${r['href']}
            Should Be Equal    ${got['name']}    ${event}
        END
    END

DAV phone edits its pre-upgrade contact
    [Arguments]    ${profile}
    ${name} =    Pre-upgrade name    ${profile}    contact
    ${r} =    Phonesync    dav    lookup    ${profile}    --kind    contact    --name    ${name}
    ${new} =    Unique name    ${profile} edited after upgrade
    Phonesync    dav    update    ${profile}    --href    ${r['href']}    --name    ${new}
    Contact exists in WebTop    ${new}
    Contact does not exist in WebTop    ${name}

ActiveSync phone edits its pre-upgrade event
    [Arguments]    ${profile}
    ${name} =    Pre-upgrade name    ${profile}    event
    ${r} =    Phonesync    eas    lookup    ${profile}    --class    Calendar    --name    ${name}
    ${new} =    Unique name    ${profile} edited after upgrade
    Phonesync    eas    change    ${profile}    --class    Calendar    --server-id    ${r['server_id']}    --name    ${new}
    ${found} =    Event in WebTop    ${new}
    Should Be Equal    ${found['start_utc']}    2026-07-15T08:00:00Z
    Event does not exist in WebTop    ${name}
