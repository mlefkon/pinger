#!/bin/bash

buildDate=$(cat /usr/local/pinger.build)
echo "Image Build Date: $buildDate"
echo "Endpoint: ${ENDPOINT_DESCRIPTION:=Pinger}"

echo "Checking required Environment Variables..."
    fatal=0
    if [ "${PING_URI:-missing}"                   == "missing" ]; then fatal=1; echo "Env var PING_URI is required.";                   fi;
    if [ "${EXPECTED_RESPONSE:-missing}"          == "missing" ]; then fatal=1; echo "Env var EXPECTED_RESPONSE is required.";          fi;
    if [ "${RELAY_HOST:-missing}"                 == "missing" ]; then fatal=1; echo "Env var RELAY_HOST is required.";                 fi;
    if [ "${RELAY_USERNAME:-missing}"             == "missing" ]; then fatal=1; echo "Env var RELAY_USERNAME is required.";             fi;
    if [ "${RELAY_PASSWORD:-missing}"             == "missing" ]; then fatal=1; echo "Env var RELAY_PASSWORD is required.";             fi;
    if [ "${RELAY_SENDER_EMAIL_ADDRESS:-missing}" == "missing" ]; then fatal=1; echo "Env var RELAY_SENDER_EMAIL_ADDRESS is required."; fi;
    if [ "${TO_EMAIL_ADDR:-missing}"              == "missing" ]; then fatal=1; echo "Env var TO_EMAIL_ADDR is required.";              fi;
    if [ $fatal -eq 1 ]; then echo "FATAL ERROR: missing environment variables need to be defined."; exit; fi;

echo "Configuring Postfix..."  
    # /etc/postfix/main.cf
    postconf -e "relayhost = ${RELAY_HOST}"
    postconf -e "mydomain = local.domain"
    postconf -e "myhostname = host.local.domain"
    postconf -e "myorigin = \$myhostname"
    postconf -e "smtp_use_tls = yes"
    postconf -e "smtp_sasl_auth_enable = yes"
    postconf -e "smtp_sasl_security_options = noanonymous"
    postconf -e "smtp_sasl_type = cyrus"
    postconf -e "smtp_tls_CAfile = /etc/ssl/certs/ca-bundle.crt"
    postconf -e "inet_protocols = ipv4"
    postconf -e "inet_interfaces = localhost"

    # sender_canonical
    postconf -e "sender_canonical_maps = regexp:/etc/postfix/sender_canonical" 
    echo "/.+/ ${RELAY_SENDER_EMAIL_ADDRESS}" > /etc/postfix/sender_canonical; 
    # smtp_header_checks
    postconf -e "smtp_header_checks = regexp:/etc/postfix/smtp_header_checks"
    echo "/From:.*/ REPLACE From: ${RELAY_SENDER_INFORMAL_NAME} <${RELAY_SENDER_EMAIL_ADDRESS}>" > /etc/postfix/smtp_header_checks; 
    # sasl_passwd
    postconf -e "smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd" 
    echo "${RELAY_HOST} ${RELAY_USERNAME}:${RELAY_PASSWORD}" \
                  > /etc/postfix/sasl_passwd; 
    postmap         /etc/postfix/sasl_passwd;                              
    chown root:root /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db; 
    chmod 0600      /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db; 

echo "Initializing logs..."
pingLogFile="/var/log/pinger/${ENDPOINT_DESCRIPTION// /_}.ping.log"
rm -f $pingLogFile

echo "Configuring Crontab job..."
set -f
cronjob="
\nENDPOINT_DESCRIPTION=\"${ENDPOINT_DESCRIPTION:=Pinger}\"
\nINTERVAL_MIN=\"${INTERVAL_MIN:=5}\"
\nTHRESHOLD_FAILS_FOR_EMAIL=\"${THRESHOLD_FAILS_FOR_EMAIL:=1}\"
\nPING_URI=\"${PING_URI}\"
\nEXPECTED_RESPONSE=\"${EXPECTED_RESPONSE}\"
\nRELAY_SENDER_EMAIL_ADDRESS=\"${RELAY_SENDER_EMAIL_ADDRESS}\"
\nRELAY_SENDER_INFORMAL_NAME=\"${RELAY_SENDER_INFORMAL_NAME:=Pinger}\"
\nTO_EMAIL_ADDR=\"${TO_EMAIL_ADDR}\"
\nSTATUS_EMAIL_DAYS=\"${STATUS_EMAIL_DAYS:=30}\"
\n
\n# m h dom mon dow command
\n*/${INTERVAL_MIN:=5} * * * * /usr/local/pinger.sh
\n
"
    crontab -u root -r > /dev/null
    echo -e $cronjob | crontab -u root -; 
    echo "Crontab has been set."
    set +f

echo "Normal Startup..."
    service rsyslog start
    service postfix start
    service crond start

echo "Sending init/test email..."
    cat <<EOF | /usr/sbin/sendmail -t
To: $TO_EMAIL_ADDR
Subject: INIT - $ENDPOINT_DESCRIPTION
From: $RELAY_SENDER_INFORMAL_NAME <$RELAY_SENDER_EMAIL_ADDRESS>

Ping has been successfully initialized.

$ENDPOINT_DESCRIPTION

URI: $PING_URI
Expected Response: "$EXPECTED_RESPONSE"
Ping every: $INTERVAL_MIN minuntes
Threshold: $THRESHOLD_FAILS_FOR_EMAIL failures will be required to send an email.

Status Report (% up, average ping time)
Emailed every ${STATUS_EMAIL_DAYS} days.
History is saved in /var/log/pinger/.  Mount a docker volume for persistance.

EOF

sleep infinity