*** Settings ***
Test Timeout      5 minutes
Documentation     Pair every phone with the stable module, before 22_update.robot upgrades it
Resource          phonesync_sync.resource
Suite Setup       Run Keywords    Skip unless update scenario    AND    Set up phone suite    AND    Start from unpaired phones

*** Variables ***
# one message both ActiveSync phones read before the upgrade and must not download again after it
${PRE_UPGRADE_MAIL}    e2e-pre-upgrade-mail

*** Test Cases ***
Mail arrives before the upgrade
    Deliver mail    ${PHONE_USER}    ${PRE_UPGRADE_MAIL}
    Mailbox has message    ${PHONE_USER}    ${PRE_UPGRADE_MAIL}

DAV phones sync before the upgrade
    [Template]    DAV phone pairs
    davx5
    ios-dav

ActiveSync phones sync before the upgrade
    [Template]    ActiveSync phone pairs
    ios-eas
    android-eas

All phones catch up before the upgrade
    # every phone must know every pre-upgrade item, so after the upgrade nothing is new
    FOR    ${profile}    IN    davx5    ios-dav
        Phone DAV sync    ${profile}    contact
        Phone DAV sync    ${profile}    event
    END
    FOR    ${profile}    IN    ios-eas    android-eas
        Phone EAS sync    ${profile}    Contacts
        Phone EAS sync    ${profile}    Calendar
        Phone EAS sync    ${profile}    Tasks
        Phone EAS sync    ${profile}    Email
    END

*** Keywords ***
DAV phone pairs
    [Arguments]    ${profile}
    Phonesync    dav    discover    ${profile}
    ${contact} =    Pre-upgrade name    ${profile}    contact
    ${event} =    Pre-upgrade name    ${profile}    event
    Phonesync    dav    put    ${profile}    --kind    contact    --name    ${contact}
    Phonesync    dav    put    ${profile}    --kind    event    --name    ${event}
    ...    --start    2026-07-15T10:00:00    --end    2026-07-15T11:00:00    --tz    Europe/Rome
    Phone DAV sync    ${profile}    contact
    Phone DAV sync    ${profile}    event

ActiveSync phone pairs
    [Arguments]    ${profile}
    Phonesync    eas    setup    ${profile}
    Phone EAS sync    ${profile}    Contacts
    Phone EAS sync    ${profile}    Calendar
    Phone EAS sync    ${profile}    Tasks
    ${r} =    Phone EAS sync    ${profile}    Email
    ${subjects} =    Names in    ${r['added']}
    Should Contain    ${subjects}    ${PRE_UPGRADE_MAIL}
    ${contact} =    Pre-upgrade name    ${profile}    contact
    ${event} =    Pre-upgrade name    ${profile}    event
    Phonesync    eas    add    ${profile}    --class    Contacts    --name    ${contact}
    Phonesync    eas    add    ${profile}    --class    Calendar    --name    ${event}
    ...    --start    2026-07-15T10:00:00    --end    2026-07-15T11:00:00    --tz    Europe/Rome
    ${task} =    Pre-upgrade name    ${profile}    task
    Phonesync    eas    add    ${profile}    --class    Tasks    --name    ${task}    --due    2026-07-20T08:00:00Z
    Phone EAS sync    ${profile}    Contacts
    Phone EAS sync    ${profile}    Calendar
    Phone EAS sync    ${profile}    Tasks
