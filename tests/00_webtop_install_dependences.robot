*** Settings ***
Library    SSHLibrary
Resource   ./api.resource

*** Test Cases ***
Setup internal user provider
    ${response} =     Run task    cluster/add-internal-provider    {"image":"openldap","node":1}
    Set Global Variable    ${openldap_module_id}    ${response['module_id']}
    Set Global Variable    ${users_domain}    domain.ns8.local
    Run task    module/${openldap_module_id}/configure-module    {"domain":"${users_domain}","admuser":"admin","admpass":"Nethesis,1234","provision":"new-domain"}

Check if mail is installed correctly
    ${output}  ${rc} =    Execute Command    add-module mail
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0
    &{output} =    Evaluate    ${output}
    Set Global Variable    ${mail_module_id}    ${output.module_id}
    Set Global Variable    ${mail_domain}    ns8.local
    Set Global Variable    ${mail_hostname}    mail.ns8.local
    Run task    module/${mail_module_id}/configure-module    {"hostname":"${mail_hostname}","user_domain":"${users_domain}","mail_domain":"${mail_domain}"}
    ...    decode_json=False    rc_expected=0
