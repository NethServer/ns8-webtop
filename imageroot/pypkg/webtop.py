#!/usr/bin/env python3

#
# Copyright (C) 2022 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#

import json
import os
import subprocess
import agent.tasks

def configure_module(mail_module, penv):
    """Run the own configure-module action with the input environment and mail module ID"""
    return agent.tasks.run(agent_id=os.environ['AGENT_ID'], action='configure-module', data={
        "hostname": penv['WEBTOP_HOSTNAME'],
        "locale": penv['WEBTOP_LOCALE'],
        "timezone": penv['WEBTOP_TIMEZONE'],
        "mail_module": mail_module,
        "mail_domain": penv['MAIL_DOMAIN'],
        "ejabberd_module": penv.get('EJABBERD_MODULE',''),
        "webapp": {
            "debug": penv['WEBAPP_JS_DEBUG'] == 'True',
            "min_memory": int(penv['WEBAPP_MIN_MEMORY']),
            "max_memory": int(penv['WEBAPP_MAX_MEMORY']),
        },
        "webdav": {
            "debug": penv['WEBDAV_DEBUG'] == 'True',
            "loglevel": penv['WEBDAV_LOG_LEVEL'],
        },
        "zpush": {
            "loglevel": penv['Z_PUSH_LOG_LEVEL'],
        },
        "pecbridge_admin_mail": penv.get('PECBRIDGE_ADMIN_MAIL',''),
    })

def configure_nethvoice_chat(instance):
    """Write the NethVoice chat settings for a NethVoice instance ('' turns the chat off).
    Returns True when a setting changed (the webapp reads them at startup)."""
    script = os.path.join(os.environ['AGENT_INSTALL_DIR'], 'bin', 'configure-nethvoice-chat')
    proc = subprocess.run([script], env=dict(os.environ, CHAT_INSTANCE=instance), stdout=subprocess.PIPE, text=True, check=True)
    return json.loads(proc.stdout)['changed']
