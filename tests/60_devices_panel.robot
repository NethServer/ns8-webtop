*** Settings ***
Documentation     Data the WebTop admin Devices panel reads from z-push-admin
Test Timeout      5 minutes
Resource          phonesync_sync.resource
Suite Setup       Run Keywords    Set up phone suite    AND    Pair ActiveSync phones

*** Variables ***
@{DEVICES}        e2eiphone0000001    e2eandroid000001

*** Test Cases ***
Devices panel lists the paired phones
    ${r} =    Devices panel data    lastsync    -a lastsync
    ${today} =    Execute Command    date -u +%F
    FOR    ${device}    IN    @{DEVICES}
        ${rows} =    Evaluate    list(filter(lambda d, dev=$device, usr=$PHONE_USER: d['device'] == dev and d['user'] == usr, $r['devices']))
        Length Should Be    ${rows}    1    ${device} of ${PHONE_USER} not listed by lastsync
        Should Not Be Equal    ${rows[0]['last_sync']}    ${None}    ${device} shows no last sync
        ${days} =    Evaluate    abs((datetime.date.fromisoformat($rows[0]['last_sync'][:10]) - datetime.date.fromisoformat($today)).days)    modules=datetime
        Should Be True    ${days} <= 1    last sync ${rows[0]['last_sync']} is not today
    END

Devices list shows the paired phones
    ${r} =    Devices panel data    list    -a list
    FOR    ${device}    IN    @{DEVICES}
        Dictionary Should Contain Key    ${r['devices']}    ${device}
        List Should Contain Value    ${r['devices']['${device}']}    ${PHONE_USER}
    END

Device details are shown
    FOR    ${device}    IN    @{DEVICES}
        ${r} =    Devices panel data    info    -a list -d ${device} -u ${PHONE_USER}
        Should Start With    ${r['info']}    Synchronized by user: ${PHONE_USER}
        Should Contain    ${r['info']}    ${device}
    END

User device list shows the paired phones
    # `-a list -u` is offered by WebTop's ZPushManager but not used by the panel; check what an admin sees
    ${text}    ${status} =    Run z-push-admin    -a list -u ${PHONE_USER}
    Should Be Equal    ${status}    200
    Should Contain    ${text}    ${PHONE_USER}
    FOR    ${device}    IN    @{DEVICES}
        Should Contain    ${text}    ${device}
    END

zfaker rejects shell syntax
    ${marker} =    Set Variable    /tmp/e2e-injected
    Execute Command    runagent -m ${webtop_module_id} podman exec z-push rm -f ${marker}
    ${text}    ${status} =    Run z-push-admin    -a lastsync; touch ${marker}
    ${rc} =    Execute Command    runagent -m ${webtop_module_id} podman exec z-push test -e ${marker}    return_stdout=False    return_rc=True
    Should Not Be Equal As Integers    ${rc}    0    the injected command ran inside the z-push container
    Should Be Equal    ${status}    400

*** Keywords ***
Pair ActiveSync phones
    FOR    ${profile}    IN    ios-eas    android-eas
        Phonesync    eas    setup    ${profile}
        Phone EAS sync    ${profile}    Contacts
    END
