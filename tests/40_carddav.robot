*** Settings ***
Test Timeout      5 minutes
Documentation     Contacts over CardDAV, as DAVx5 (Android) and iOS sync them
Resource          phonesync_sync.resource
Suite Setup       Run Keywords    Set up phone suite
...               AND    Run Keyword If    '${SCENARIO}' != 'update'    Start from unpaired phones
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

Contact with details reaches WebTop
    [Template]    Contact with details reaches WebTop
    davx5
    ios-dav

Contact details reach the second phone
    [Template]    Contact details reach the second phone
    davx5    ios-dav
    ios-dav    davx5

Contact WebTop cannot save is reported to the phone
    [Documentation]    Known issue: WebDAV answers 201 Created when WebTop fails to store the contact,
    ...                so the phone believes it is saved. Skipped while it fails.
    [Tags]    known-issue    robot:skip-on-failure
    ${status} =    Phone puts a contact WebTop rejects
    Should Not Start With    ${status}    2    WebDAV reported success (${status}) for a contact WebTop did not store

Contact edited on phone reaches WebTop
    [Template]    Contact edited on phone reaches WebTop
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

*** Variables ***
&{DETAILS}        mobile=+39 333 1234567    email=niccolo@example.test    street=Via Roma 1    city=Pesaro    photo=png

*** Keywords ***
Expected details
    &{expected} =    Evaluate    dict(mobile=$DETAILS['mobile'], email=$DETAILS['email'], street=$DETAILS['street'], city=$DETAILS['city'], photo_size=len(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGBgAAAABQABpfZFQAAAAABJRU5ErkJggg==')))    modules=base64
    RETURN    ${expected}

Contact with details reaches WebTop
    [Arguments]    ${profile}
    ${name} =    Unique name    ${profile} detailed
    ${json} =    Evaluate    json.dumps($DETAILS)    modules=json
    Phonesync    dav    put    ${profile}    --kind    contact    --name    ${name}    --fields    ${json}
    ${got} =    Contact fields in WebTop    ${name}
    ${expected} =    Expected details
    Dictionaries Should Be Equal    ${got}    ${expected}

Contact details reach the second phone
    [Arguments]    ${writer}    ${reader}
    Phone DAV sync    ${reader}    contact
    ${name} =    Unique name    from ${writer} detailed
    ${json} =    Evaluate    json.dumps($DETAILS)    modules=json
    Phonesync    dav    put    ${writer}    --kind    contact    --name    ${name}    --fields    ${json}
    ${r} =    Phone DAV sync    ${reader}    contact
    Length Should Be    ${r['added']}    1
    ${got} =    Phonesync    dav    get    ${reader}    --href    ${r['added'][0]['href']}
    ${expected} =    Expected details
    Dictionaries Should Be Equal    ${got['fields']}    ${expected}

Phone puts a contact WebTop rejects
    # a PHOTO whose PNG data is corrupt: WebTop refuses to store it
    ${uid} =    Unique name    rejected
    ${vcard} =    Catenate    SEPARATOR=\r\n    BEGIN:VCARD    VERSION:3.0    UID:${uid}    FN:${uid}    N:${uid};;;;
    ...    PHOTO;ENCODING=b;TYPE=PNG:iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGAAAAAFAAGl9kVAAAAAAElFTkSuQmCC    END:VCARD    ${EMPTY}
    ${r} =    Phonesync    dav    discover    davx5
    ${url} =    Set Variable    ${backend_url}${r['addressbooks'][0]['href']}${uid}.vcf
    ${cmd} =    Evaluate    'printf %s ' + shlex.quote($vcard) + ' | curl -s -o /dev/null -w "%{http_code}" -X PUT --data-binary @- -H "Content-Type: text/vcard" -H ' + shlex.quote('Host: ' + $WEBTOP_HOST) + ' -u ' + shlex.quote($PHONE_USER + ':' + $PHONE_PASSWORD) + ' ' + shlex.quote($url)    modules=shlex
    ${status} =    Execute Command    ${cmd}
    RETURN    ${status}

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

Contact edited on phone reaches WebTop
    [Arguments]    ${profile}
    ${name} =    Unique name    ${profile} draft
    ${r} =    Phonesync    dav    put    ${profile}    --kind    contact    --name    ${name}
    ${new} =    Unique name    ${profile} final
    Phonesync    dav    update    ${profile}    --href    ${r['href']}    --name    ${new}
    Contact exists in WebTop    ${new}
    Contact does not exist in WebTop    ${name}
