*** Settings ***
Library    SSHLibrary
Resource   ../api.resource

*** Test Cases ***
Check if WevTop can be configured correctly
    Run task    module/${module_id}/configure-module    {"hostname":"webtop.ns8.local","mail_module":"${mail_module_id}","mail_domain":"${mail_domain}"}
    ...    decode_json=False    rc_expected=0
