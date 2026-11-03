*** Comments ***
Server-side truth for the phone sync tests, kept outside the PHP services.
Reads query WebTop's PostgreSQL database. Writes go through the WebTop Java
REST API (the one the DAV and ActiveSync servers call) via the phonesync
helper: raw SQL writes would skip WebTop's history and sync bookkeeping.

*** Settings ***
Library     SSHLibrary
Resource    phonesync.resource

*** Keywords ***
WebTop SQL
    [Arguments]    ${sql}
    # psql -c, so names are inlined with dollar quoting; test names never contain "$q$"
    ${cmd} =    Evaluate    shlex.join(['runagent', '-m', $webtop_module_id, 'podman', 'exec', 'postgres', 'psql', '-U', 'postgres', '-tA', '-F', '|', 'webtop5', '-c', $sql])    modules=shlex
    ${out}    ${err}    ${rc} =    Execute Command    ${cmd}    return_stderr=True    return_rc=True
    Should Be Equal As Integers    ${rc}    0    psql failed: ${err}
    RETURN    ${out}

Phone user id
    ${uid} =    Evaluate    $PHONE_USER.split('@')[0]
    RETURN    ${uid}

Count contacts in WebTop
    [Arguments]    ${name}
    ${uid} =    Phone user id
    ${count} =    WebTop SQL    SELECT count(*) FROM contacts.contacts c JOIN contacts.categories k USING (category_id) WHERE k.user_id = $q$${uid}$q$ AND c.display_name = $q$${name}$q$ AND c.revision_status <> 'D'
    RETURN    ${count}

Contact exists in WebTop
    [Arguments]    ${name}
    ${count} =    Count contacts in WebTop    ${name}
    Should Be Equal As Integers    ${count}    1    expected exactly one contact named ${name}, found ${count}

Contact does not exist in WebTop
    [Arguments]    ${name}
    ${count} =    Count contacts in WebTop    ${name}
    Should Be Equal As Integers    ${count}    0    contact ${name} still in WebTop

Events in WebTop
    [Arguments]    ${name}
    ${uid} =    Phone user id
    ${out} =    WebTop SQL    SELECT to_char(e.start AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'), e.title FROM calendar.events e JOIN calendar.calendars c USING (calendar_id) WHERE c.user_id = $q$${uid}$q$ AND e.title = $q$${name}$q$ AND e.revision_status <> 'D'
    @{rows} =    Evaluate    [line.split('|', 1) for line in $out.splitlines() if line]
    RETURN    ${rows}

Event in WebTop
    [Arguments]    ${name}
    @{rows} =    Events in WebTop    ${name}
    Length Should Be    ${rows}    1    expected exactly one event named ${name}
    &{event} =    Create Dictionary    start_utc=${rows[0][0]}    summary=${rows[0][1]}
    RETURN    ${event}

Event does not exist in WebTop
    [Arguments]    ${name}
    @{rows} =    Events in WebTop    ${name}
    Length Should Be    ${rows}    0    event ${name} still in WebTop

Open WebTop once as phone user
    # WebTop creates a user's address book only when its web app first loads, as on a user's first visit
    ${login} =    Catenate    curl -sk --resolve ${WEBTOP_HOST}:443:127.0.0.1 -b /tmp/e2e-cookies -c /tmp/e2e-cookies
    ${cmd} =    Evaluate    'rm -f /tmp/e2e-cookies && ' + $login + ' -o /dev/null -X POST https://' + $WEBTOP_HOST + '/webtop/login --data-urlencode wtusername=' + shlex.quote($PHONE_USER) + ' --data-urlencode wtpassword=' + shlex.quote($PHONE_PASSWORD) + ' -d wtdomain=NethServer -d location=https://' + $WEBTOP_HOST + '/webtop/ && ' + $login + ' https://' + $WEBTOP_HOST + '/webtop/ ; rm -f /tmp/e2e-cookies'    modules=shlex
    ${page} =    Execute Command    ${cmd}
    Should Contain    ${page}    "services":[    WebTop web app did not load for ${PHONE_USER}

Create contact in WebTop
    [Arguments]    ${name}
    Phonesync    webtop    contact-create    ${EMPTY}    --name    ${name}

Rename contact in WebTop
    [Arguments]    ${name}    ${new_name}
    Phonesync    webtop    contact-rename    ${EMPTY}    --name    ${name}    --new-name    ${new_name}

Delete contact in WebTop
    [Arguments]    ${name}
    Phonesync    webtop    contact-delete    ${EMPTY}    --name    ${name}

Create event in WebTop
    [Arguments]    ${name}    ${start_utc}    ${end_utc}    @{options}
    Phonesync    webtop    event-create    ${EMPTY}    --name    ${name}    --start    ${start_utc}    --end    ${end_utc}    @{options}

Create sparse contact in WebTop
    [Arguments]    ${last_name}
    Phonesync    webtop    contact-create-sparse    ${EMPTY}    --name    ${last_name}

Create untitled event in WebTop
    [Arguments]    ${key}    ${start_utc}    ${end_utc}
    Phonesync    webtop    event-create-untitled    ${EMPTY}    --name    ${key}    --start    ${start_utc}    --end    ${end_utc}

Rename event in WebTop
    [Arguments]    ${name}    ${new_name}
    Phonesync    webtop    event-rename    ${EMPTY}    --name    ${name}    --new-name    ${new_name}

Delete event in WebTop
    [Arguments]    ${name}
    Phonesync    webtop    event-delete    ${EMPTY}    --name    ${name}

Delete all test items in WebTop
    Phonesync    webtop    cleanup    ${EMPTY}    --name    e2e-

Put message in mailbox
    [Arguments]    ${user}    ${subject}    ${body}
    ${local} =    Evaluate    $user.split('@')[0]
    ${message} =    Catenate    SEPARATOR=\r\n    From: e2e@example.test    To: ${user}    Subject: ${subject}
    ...    Date: Wed, 21 Oct 2026 10:00:00 +0000    Message-ID: <${subject}@e2e.test>    ${EMPTY}    ${body}
    ${cmd} =    Evaluate    'printf %s ' + shlex.quote($message) + ' | ' + shlex.join(['runagent', '-m', $MID, 'podman', 'exec', '-i', 'dovecot', 'doveadm', 'save', '-u', $local, '-m', 'INBOX'])    modules=shlex
    ${out}    ${err}    ${rc} =    Execute Command    ${cmd}    return_stderr=True    return_rc=True
    Should Be Equal As Integers    ${rc}    0    doveadm save failed: ${err}

Mailbox search
    [Arguments]    ${local}    ${subject}
    ${cmd} =    Evaluate    shlex.join(['runagent', '-m', $MID, 'podman', 'exec', 'dovecot', 'doveadm', 'search', '-u', $local, 'mailbox', 'INBOX', 'subject', $subject])    modules=shlex
    ${out} =    Execute Command    ${cmd}
    Should Not Be Empty    ${out}    no message with subject ${subject} in ${local}'s inbox

Mailbox has message
    [Arguments]    ${user}    ${subject}
    ${local} =    Evaluate    $user.split('@')[0]
    Wait Until Keyword Succeeds    60 seconds    3 seconds    Mailbox search    ${local}    ${subject}

Delete test messages
    [Arguments]    ${user}
    ${local} =    Evaluate    $user.split('@')[0]
    ${cmd} =    Evaluate    shlex.join(['runagent', '-m', $MID, 'podman', 'exec', 'dovecot', 'doveadm', 'expunge', '-u', $local, 'mailbox', '*', 'subject', 'e2e-'])    modules=shlex
    Execute Command    ${cmd}

Delete pre-upgrade items in WebTop
    Phonesync    webtop    cleanup    ${EMPTY}    --name    pre-upgrade-

Contact fields in WebTop
    [Arguments]    ${name}
    ${uid} =    Phone user id
    ${out} =    WebTop SQL    SELECT c.work_mobile, c.work_email, c.work_address, c.work_city, coalesce((SELECT octet_length(p.bytes) FROM contacts.contacts_pictures p WHERE p.contact_id = c.contact_id), 0) FROM contacts.contacts c JOIN contacts.categories k USING (category_id) WHERE k.user_id = $q$${uid}$q$ AND c.display_name = $q$${name}$q$ AND c.revision_status <> 'D'
    @{rows} =    Evaluate    [line.split('|') for line in $out.splitlines() if line]
    Length Should Be    ${rows}    1    expected exactly one contact named ${name}
    &{fields} =    Evaluate    dict(zip(['mobile', 'email', 'street', 'city'], [v or None for v in $rows[0][:4]]), photo_size=int($rows[0][4]))
    RETURN    ${fields}

Event details in WebTop
    [Arguments]    ${name}
    ${uid} =    Phone user id
    ${out} =    WebTop SQL    SELECT e.all_day, to_char(e.start AT TIME ZONE 'Europe/Rome', 'YYYY-MM-DD"T"HH24:MI:SS'), coalesce(e.reminder::text, ''), coalesce(r.rule, '') FROM calendar.events e JOIN calendar.calendars c USING (calendar_id) LEFT JOIN calendar.events_recurrences r USING (event_id) WHERE c.user_id = $q$${uid}$q$ AND e.title = $q$${name}$q$ AND e.revision_status <> 'D'
    @{rows} =    Evaluate    [line.split('|') for line in $out.splitlines() if line]
    Length Should Be    ${rows}    1    expected exactly one event named ${name}
    &{details} =    Evaluate    {'all_day': $rows[0][0] == 't', 'start_local': $rows[0][1], 'reminder': int($rows[0][2]) if $rows[0][2] else None, 'rrule': $rows[0][3] or None}
    RETURN    ${details}

Tasks in WebTop
    [Arguments]    ${name}
    ${uid} =    Phone user id
    ${out} =    WebTop SQL    SELECT t.subject, coalesce(to_char(t.due AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'), ''), t.status, (t.completed_on IS NOT NULL) FROM tasks.tasks t JOIN tasks.categories k USING (category_id) WHERE k.user_id = $q$${uid}$q$ AND t.subject = $q$${name}$q$ AND t.revision_status <> 'D'
    @{rows} =    Evaluate    [line.split('|') for line in $out.splitlines() if line]
    RETURN    ${rows}

Task in WebTop
    [Arguments]    ${name}
    @{rows} =    Tasks in WebTop    ${name}
    Length Should Be    ${rows}    1    expected exactly one task named ${name}
    &{task} =    Evaluate    {'subject': $rows[0][0], 'due_utc': $rows[0][1] or None, 'status': $rows[0][2], 'completed': $rows[0][3] == 't'}
    RETURN    ${task}

Task does not exist in WebTop
    [Arguments]    ${name}
    @{rows} =    Tasks in WebTop    ${name}
    Length Should Be    ${rows}    0    task ${name} still in WebTop

Create task in WebTop
    [Arguments]    ${name}    ${due_utc}
    Phonesync    webtop    task-create    ${EMPTY}    --name    ${name}    --due    ${due_utc}

Rename task in WebTop
    [Arguments]    ${name}    ${new_name}
    Phonesync    webtop    task-rename    ${EMPTY}    --name    ${name}    --new-name    ${new_name}

Complete task in WebTop
    [Arguments]    ${name}
    Phonesync    webtop    task-complete    ${EMPTY}    --name    ${name}

Delete task in WebTop
    [Arguments]    ${name}
    Phonesync    webtop    task-delete    ${EMPTY}    --name    ${name}

Deliver mail
    # through the mail module's postfix, so it is a real delivery and not a mailbox write
    [Arguments]    ${to}    ${subject}
    ${message} =    Catenate    SEPARATOR=\n    From: e2e@example.test    To: ${to}    Subject: ${subject}    ${EMPTY}    Delivered by the e2e tests
    ${cmd} =    Evaluate    'printf %s ' + shlex.quote($message) + ' | ' + shlex.join(['runagent', '-m', $MID, 'podman', 'exec', '-i', 'postfix', 'sendmail', '-f', 'e2e@example.test', $to])    modules=shlex
    ${out}    ${err}    ${rc} =    Execute Command    ${cmd}    return_stderr=True    return_rc=True
    Should Be Equal As Integers    ${rc}    0    sendmail failed: ${err}

Run z-push-admin
    # exactly how WebTop's Devices panel reaches z-push-admin: zfaker on localhost, from the webapp container
    [Arguments]    ${params}
    ${body} =    Evaluate    json.dumps({'params': $params})    modules=json
    ${cmd} =    Evaluate    shlex.join(['runagent', '-m', $webtop_module_id, 'podman', 'exec', 'webapp', 'curl', '-s', '-w', '\\n\%{http_code}', '-H', 'Content-Type: application/json', '-d', $body, 'http://localhost:8081/z-push-admin'])    modules=shlex
    ${out} =    Execute Command    ${cmd}
    ${text}    ${status} =    Evaluate    $out.rsplit('\\n', 1) if '\\n' in $out else ('', $out)
    RETURN    ${text}    ${status}

Devices panel data
    [Arguments]    ${what}    ${params}
    ${text}    ${status} =    Run z-push-admin    ${params}
    Should Be Equal    ${status}    200    z-push-admin ${params} answered HTTP ${status}
    ${cmd} =    Evaluate    'printf %s ' + shlex.quote($text) + ' | ' + shlex.join(['python3', $PHONESYNC, 'devices', 'parse', '--what', $what])    modules=shlex
    ${out}    ${err}    ${rc} =    Execute Command    ${cmd}    return_stderr=True    return_rc=True
    ${result} =    Phonesync result    devices parse ${what}    ${out}    ${err}    ${rc}
    RETURN    ${result}
