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

Large contact photo round-trips
    [Template]    Large contact photo round-trips
    davx5    ios-dav
    ios-dav    davx5

Phone checks a contact with HEAD
    [Template]    Phone checks a contact with HEAD
    davx5

Phone searches principals
    [Template]    Phone searches principals
    ios-dav

Sparse contact from WebTop syncs
    [Documentation]    A contact with only a last name: on sabre/dav 4 a missing value must not break the sync
    [Template]    Sparse contact from WebTop syncs
    davx5
    ios-dav

Contact WebTop cannot save is reported to the phone
    ${status} =    Phone puts a contact WebTop rejects
    Should Not Start With    ${status}    2    WebDAV reported success (${status}) for a contact WebTop did not store

Contact edit WebTop cannot save is reported to the phone
    ${name} =    Unique name    rejected edit
    ${r} =    Phonesync    dav    put    davx5    --kind    contact    --name    ${name}
    ${status} =    Phone puts a contact WebTop rejects    ${r['href']}
    Should Not Start With    ${status}    2    WebDAV reported success (${status}) for a change WebTop did not store
    Contact exists in WebTop    ${name}

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

*** Keywords ***
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
    [Arguments]    ${href}=${EMPTY}
    # a PHOTO whose PNG data is corrupt: WebTop refuses to store it; a new contact, or a change to ${href}
    ${uid} =    Unique name    rejected
    ${vcard} =    Catenate    SEPARATOR=\r\n    BEGIN:VCARD    VERSION:3.0    UID:${uid}    FN:${uid}    N:${uid};;;;
    ...    PHOTO;ENCODING=b;TYPE=PNG:iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGAAAAAFAAGl9kVAAAAAAElFTkSuQmCC    END:VCARD    ${EMPTY}
    ${r} =    Phonesync    dav    discover    davx5
    ${url} =    Set Variable If    $href    ${backend_url}${href}    ${backend_url}${r['addressbooks'][0]['href']}${uid}.vcf
    ${cmd} =    Evaluate    'printf %s ' + shlex.quote($vcard) + ' | curl -s -o /dev/null -w "\%{http_code}" -X PUT --data-binary @- -H "Content-Type: text/vcard" -H ' + shlex.quote('Host: ' + $WEBTOP_HOST) + ' -u ' + shlex.quote($PHONE_USER + ':' + $PHONE_PASSWORD) + ' ' + shlex.quote($url)    modules=shlex
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

Large contact photo round-trips
    [Arguments]    ${writer}    ${reader}
    Phone DAV sync    ${reader}    contact
    ${name} =    Unique name    ${writer} large photo
    Phonesync    dav    put    ${writer}    --kind    contact    --name    ${name}    --fields    {"photo": "large"}
    ${size} =    Photo size    large
    ${got} =    Contact fields in WebTop    ${name}
    Should Be Equal As Integers    ${got['photo_size']}    ${size}
    ${r} =    Phone DAV sync    ${reader}    contact
    Length Should Be    ${r['added']}    1
    ${read} =    Phonesync    dav    get    ${reader}    --href    ${r['added'][0]['href']}
    Should Be Equal As Integers    ${read['fields']['photo_size']}    ${size}

Sparse contact from WebTop syncs
    [Arguments]    ${profile}
    Phone DAV sync    ${profile}    contact
    ${name} =    Unique name    ${profile} sparse
    Create sparse contact in WebTop    ${name}
    ${r} =    Phone DAV sync    ${profile}    contact
    Length Should Be    ${r['added']}    1
    ${got} =    Phonesync    dav    get    ${profile}    --href    ${r['added'][0]['href']}
    Should Be Equal    ${got['fields']['mobile']}    ${None}

Phone checks a contact with HEAD
    [Arguments]    ${profile}
    ${name} =    Unique name    ${profile} head
    ${r} =    Phonesync    dav    put    ${profile}    --kind    contact    --name    ${name}
    ${cmd} =    Evaluate    'curl -s -o /dev/null -w "\%{http_code}" -I -H ' + shlex.quote('Host: ' + $WEBTOP_HOST) + ' -u ' + shlex.quote($PHONE_USER + ':' + $PHONE_PASSWORD) + ' ' + shlex.quote($backend_url + $r['href'])    modules=shlex
    ${status} =    Execute Command    ${cmd}
    Should Be Equal    ${status}    200    HEAD on a contact answered ${status}

Phone searches principals
    [Arguments]    ${profile}
    ${r} =    Phonesync    dav    discover    ${profile}
    ${search} =    Set Variable    <?xml version="1.0" encoding="utf-8"?><d:principal-property-search xmlns:d="DAV:"><d:property-search><d:prop><d:displayname/></d:prop><d:match>u1</d:match></d:property-search><d:prop><d:displayname/></d:prop></d:principal-property-search>
    ${principals} =    Evaluate    $r['principal'].rstrip('/').rsplit('/', 1)[0] + '/'
    ${cmd} =    Evaluate    'printf %s ' + shlex.quote($search) + ' | curl -s -o /dev/null -w "\%{http_code}" -X REPORT --data-binary @- -H "Content-Type: application/xml" -H "Depth: 0" -H ' + shlex.quote('Host: ' + $WEBTOP_HOST) + ' -u ' + shlex.quote($PHONE_USER + ':' + $PHONE_PASSWORD) + ' ' + shlex.quote($backend_url + $principals)    modules=shlex
    ${status} =    Execute Command    ${cmd}
    Should Be Equal    ${status}    207    principal search answered ${status}
