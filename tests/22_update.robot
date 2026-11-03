*** Settings ***
Library    SSHLibrary
Resource    webtop.resource

*** Test Cases ***
Update webtop to the image under test
    Skip If    '${SCENARIO}' != 'update'    scenario is ${SCENARIO}, nothing to update
    ${rc} =    Execute Command
    ...    api-cli run update-module --data '{"force":true,"module_url":"${IMAGE_URL}","instances":["${webtop_module_id}"]}'
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0
    # the phone suites after this point run on the new containers: 85_php_logs checks their logs from here
    Mark the start of the phone run    again=${True}

Check the configuration survives the update
    Skip If    '${SCENARIO}' != 'update'    scenario is ${SCENARIO}, nothing to update
    ${config} =    Run task    module/${webtop_module_id}/get-configuration    {}
    Should Be Equal    ${config['hostname']}    webtop.domain.com
    Should Be Equal    ${config['timezone']}    Europe/Rome
    Should Be Equal    ${config['locale']}    en_US
    ${mail_module} =    Evaluate    "${mail_modules_id}".split(",")[0]
    Should Be Equal    ${config['mail_module']}    ${mail_module}

Check webtop works after the update
    Skip If    '${SCENARIO}' != 'update'    scenario is ${SCENARIO}, nothing to update
    Retry test    Backend URL is reachable
    Retry test    Login as u1

Check u1 keeps its database row after the update
    Skip If    '${SCENARIO}' != 'update'    scenario is ${SCENARIO}, nothing to update
    ${uid} =    Get the database id of u1
    Should Be Equal    ${uid}    ${u1_uid}
