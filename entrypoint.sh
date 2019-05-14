#!/bin/bash

echo "Checking required Environment Variables..."
    fatal=0
    if [ ${PING_URI:-missing}                   == "missing" ]; then fatal=1; echo "Env var PING_URI is required.";                   fi;
    if [ ${EXPECTED_RESPONSE:-missing}          == "missing" ]; then fatal=1; echo "Env var EXPECTED_RESPONSE is required.";          fi;
    if [ ${RELAY_HOST:-missing}                 == "missing" ]; then fatal=1; echo "Env var RELAY_HOST is required.";                 fi;
    if [ ${RELAY_USERNAME:-missing}             == "missing" ]; then fatal=1; echo "Env var RELAY_USERNAME is required.";             fi;
    if [ ${RELAY_PASSWORD:-missing}             == "missing" ]; then fatal=1; echo "Env var RELAY_PASSWORD is required.";             fi;
    if [ ${RELAY_SENDER_EMAIL_ADDRESS:-missing} == "missing" ]; then fatal=1; echo "Env var RELAY_SENDER_EMAIL_ADDRESS is required."; fi;
    if [ ${TO_EMAIL_ADDR:-missing}              == "missing" ]; then fatal=1; echo "Env var TO_EMAIL_ADDR is required.";              fi;
    if [ $fatal -eq 1 ]; then echo "FATAL ERROR: missing environment variables need to be defined."; exit; fi;

echo "Configuring Postfix..."
    # Comment out all existing entries
    ENTRIES="relayhost|sender_canonical_maps|smtp_header_checks|mydomain|myhostname|myorigin|smtp_use_tls|smtp_sasl_auth_enable|smtp_sasl_security_options|smtp_sasl_password_maps|smtp_sasl_type|smtp_tls_CAfile|inet_protocols|inet_interfaces"
    sed -ri "s/^\s*(($ENTRIES)\s*=.*)/# &/" /etc/postfix/main.cf;

    echo "relayhost = ${RELAY_HOST}                      " >> /etc/postfix/main.cf; 
    echo "mydomain   = local.domain                      " >> /etc/postfix/main.cf; 
    echo "myhostname = host.local.domain                 " >> /etc/postfix/main.cf; 
    echo "myorigin = \$myhostname                        " >> /etc/postfix/main.cf; 
    echo "smtp_use_tls = yes                             " >> /etc/postfix/main.cf; 
    echo "smtp_sasl_auth_enable = yes                    " >> /etc/postfix/main.cf; 
    echo "smtp_sasl_security_options = noanonymous       " >> /etc/postfix/main.cf; 
    echo "smtp_sasl_type = cyrus                         " >> /etc/postfix/main.cf; 
    echo "smtp_tls_CAfile = /etc/ssl/certs/ca-bundle.crt " >> /etc/postfix/main.cf; 
    echo "inet_protocols = ipv4                          " >> /etc/postfix/main.cf; 
    echo "inet_interfaces = localhost                    " >> /etc/postfix/main.cf; 

    # sender_canonical
    echo "sender_canonical_maps = regexp:/etc/postfix/sender_canonical" >> /etc/postfix/main.cf; 
    echo "/.+/ ${RELAY_SENDER_EMAIL_ADDRESS}"                                          > /etc/postfix/sender_canonical; 
    # smtp_header_checks
    echo "smtp_header_checks = regexp:/etc/postfix/smtp_header_checks" >> /etc/postfix/main.cf; 
    echo "/From:.*/ REPLACE From: ${RELAY_SENDER_INFORMAL_NAME} <${RELAY_SENDER_EMAIL_ADDRESS}>"             > /etc/postfix/smtp_header_checks; 
    # sasl_passwd
    echo "smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd" >> /etc/postfix/main.cf; 
    echo "${RELAY_HOST} ${RELAY_USERNAME}:${RELAY_PASSWORD}" > /etc/postfix/sasl_passwd; 
    postmap /etc/postfix/sasl_passwd;                              
    chown root:root                                                  /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db; 
    chmod 0600                                                       /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db; 

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
\nSAVE_HISTORY=\"${SAVE_HISTORY:=0}\"
\n
\n# m h dom mon dow command
\n*/${INTERVAL_MIN:=5} * * * * /usr/local/pinger.sh
\n
"
    crontab -u root -r > /dev/null
    echo -e $cronjob | crontab -u root -; 
    echo "Crontab has been set."
    set +f
    if [[ $SAVE_HISTORY == 1 && ! -d /var/log/pinger ]]; then mkdir /var/log/pinger; fi;

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
URI: $PING_URI
With an expected response of: $EXPECTED_RESPONSE
Ping test will be run every $INTERVAL_MIN minutes.
$THRESHOLD_FAILS_FOR_EMAIL failures will be required to send an email.
$([ "$SAVE_HISTORY" == 0 ] && echo "No history will be saved" || echo "History will be saved in /var/log/pinger/.  A docker volume can be mounted for persistance.")

EOF

echo "Run initial ping..."
/usr/local/pinger.sh > /dev/null 2>&1

sleep infinity