*** Settings ***
Documentation     Contacts over CardDAV, as DAVx5 (Android) and iOS sync them
Resource          phonesync_sync.resource
Suite Setup       Set up phone suite
Suite Teardown    Delete all test items in WebTop

*** Test Cases ***
Phone discovers address book
    [Template]    Phone discovers address book
    davx5
    ios-dav

Phone initial sync
    [Template]    Phone initial sync
    davx5
    ios-dav

Contact created on phone reaches WebTop
    [Template]    Contact created on phone reaches WebTop
    davx5
    ios-dav

Non-ASCII contact round-trips
    [Template]    Non-ASCII contact round-trips
    davx5
    ios-dav

Contact changed in WebTop reaches phone
    [Template]    Contact changed in WebTop reaches phone
    davx5
    ios-dav

Contact deleted in WebTop leaves phone
    [Template]    Contact deleted in WebTop leaves phone
    davx5
    ios-dav

Contact deleted on phone leaves WebTop
    [Template]    Contact deleted on phone leaves WebTop
    davx5
    ios-dav

Second phone sees first phone's contact
    [Template]    Second phone sees first phone's contact
    davx5    ios-dav
    ios-dav    davx5

*** Keywords ***
Phone discovers address book
    [Arguments]    ${profile}
    ${r} =    Phonesync    dav    discover    ${profile}
    Should Not Be Empty    ${r['addressbooks']}

Phone initial sync
    [Arguments]    ${profile}
    Phone DAV sync    ${profile}    contact
    Phone DAV sync has nothing new    ${profile}    contact

Contact created on phone reaches WebTop
    [Arguments]    ${profile}
    ${name} =    Unique name    ${profile} new
    Phonesync    dav    put    ${profile}    --kind    contact    --name    ${name}
    Contact exists in WebTop    ${name}

Non-ASCII contact round-trips
    [Arguments]    ${profile}
    ${name} =    Unique name    Niccolò Ürsula ☕
    ${r} =    Phonesync    dav    put    ${profile}    --kind    contact    --name    ${name}
    Contact exists in WebTop    ${name}
    ${got} =    Phonesync    dav    get    ${profile}    --href    ${r['href']}
    Should Be Equal    ${got['name']}    ${name}

Contact changed in WebTop reaches phone
    [Arguments]    ${profile}
    Phone DAV sync    ${profile}    contact
    ${name} =    Unique name    ${profile} before
    Create contact in WebTop    ${name}
    ${r} =    Phone DAV sync    ${profile}    contact
    ${names} =    Names in    ${r['added']}
    Should Be Equal    ${names}    ${{[$name]}}
    ${new} =    Unique name    ${profile} after
    Rename contact in WebTop    ${name}    ${new}
    ${r} =    Phone DAV sync    ${profile}    contact
    ${names} =    Names in    ${r['changed']}
    Should Be Equal    ${names}    ${{[$new]}}

Contact deleted in WebTop leaves phone
    [Arguments]    ${profile}
    Phone DAV sync    ${profile}    contact
    ${name} =    Unique name    ${profile} doomed
    Create contact in WebTop    ${name}
    ${r} =    Phone DAV sync    ${profile}    contact
    ${hrefs} =    Hrefs in    ${r['added']}
    Length Should Be    ${hrefs}    1
    Delete contact in WebTop    ${name}
    ${r} =    Phone DAV sync    ${profile}    contact
    Should Be Equal    ${r['deleted']}    ${hrefs}

Contact deleted on phone leaves WebTop
    [Arguments]    ${profile}
    ${name} =    Unique name    ${profile} removed
    ${r} =    Phonesync    dav    put    ${profile}    --kind    contact    --name    ${name}
    Contact exists in WebTop    ${name}
    Phonesync    dav    delete    ${profile}    --href    ${r['href']}
    Contact does not exist in WebTop    ${name}

Second phone sees first phone's contact
    [Arguments]    ${writer}    ${reader}
    Phone DAV sync    ${reader}    contact
    ${name} =    Unique name    from ${writer}
    Phonesync    dav    put    ${writer}    --kind    contact    --name    ${name}
    ${r} =    Phone DAV sync    ${reader}    contact
    ${names} =    Names in    ${r['added']}
    Should Be Equal    ${names}    ${{[$name]}}
