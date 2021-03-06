#!/bin/sh

buildDate=$(cat /usr/local/pinger.build)
echo "Image Build Date: $buildDate"
echo "Instance Endpoint Name: ${ENDPOINT_NAME:=Pinger}"

echo "Checking required Environment Variables..."
    fatal=0
    if [ "${PING_URL:-missing}"                     = "missing" ]; then fatal=1; echo "Env var PING_URL is required.";                                      fi;
    if [ "${EXPECTED_RESPONSE:-missing}"            = "missing" ]; then fatal=1; echo "Env var EXPECTED_RESPONSE is required.";                             fi;
    if [ "${RELAY_HOST:-missing}"                   = "missing" ]; then fatal=1; echo "Env var RELAY_HOST is required.";                                    fi;
    if [ "${RELAY_USERNAME:-missing}"               = "missing" ]; then fatal=1; echo "Env var RELAY_USERNAME is required.";                                fi;
    if [ "${RELAY_PASSWORD:-missing}"               = "missing" ]; then fatal=1; echo "Env var RELAY_PASSWORD is required.";                                fi;
    if [ "${RELAY_SENDER_EMAIL_ADDRESS:-missing}"   = "missing" ]; then fatal=1; echo "Env var RELAY_SENDER_EMAIL_ADDRESS is required.";                    fi;
    if [ "${TO_EMAIL_ADDR:-missing}"                = "missing" ]; then fatal=1; echo "Env var TO_EMAIL_ADDR is required.";                                 fi;
    if [ "${RELIABLE_REFERENCE_PING_HOST:-missing}" = "missing" ]; then fatal=1; echo "Env var RELIABLE_REFERENCE_PING_HOST is required (eg. google.com)."; fi;
    if [ -z "${RELIABLE_REFERENCE_PING_HOST##*/*}"              ]; then fatal=1; echo "Env var RELIABLE_REFERENCE_PING_HOST is a host, not a URL.";         fi;
    if [ $fatal -eq 1 ]; then echo "FATAL ERROR: missing/bad environment variables need to be corrected."; exit; fi;

echo "Configuring Postfix..."
    # /etc/postfix/main.cf
    postconf -e "relayhost = ${RELAY_HOST}"
    postconf -e "inet_protocols = ipv4"
    postconf -e "smtp_use_tls = yes"
    postconf -e "smtp_sasl_auth_enable = yes"
    postconf -e "smtp_sasl_security_options = noanonymous"
    postconf -e "smtp_sasl_type = cyrus"
    postconf -e "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"
    postconf -e "smtp_tls_security_level=encrypt"
    postconf -e "maillog_file=/var/log/maillog"

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

echo "Checking logs..."
    pingLogFile=$( echo "/var/log/pinger/${ENDPOINT_NAME}.ping.curr.log" | tr "[:blank:]" _ )
    firstStatusTS=$([ -f "$pingLogFile" ] && head -n1 "$pingLogFile" | sed 's/,.*//' || echo 0);
    if [ "$firstStatusTS" -eq 0 ]; 
        then 
            logfiletext="Ping log file does not exist.  A new file will be initialized."
            initText="INIT"
        else 
            logfiletext="Ping log file already exists, starting on $(date -d "@$firstStatusTS" +%D), with $(wc -l < "$pingLogFile") pings so far."; 
            initText="RE-INIT (reboot)"
        fi;

echo "Configuring Crontab job..."
set -f
cronjob="ENDPOINT_NAME=\"${ENDPOINT_NAME:=Pinger}\"
         INTERVAL_MIN=\"${INTERVAL_MIN:=5}\"
         THRESHOLD_FAILS_FOR_EMAIL=\"${THRESHOLD_FAILS_FOR_EMAIL:=1}\"
         PING_URL=\"${PING_URL}\"
         RELIABLE_REFERENCE_PING_HOST=\"${RELIABLE_REFERENCE_PING_HOST}\"
         EXPECTED_RESPONSE=\"${EXPECTED_RESPONSE}\"
         RELAY_SENDER_EMAIL_ADDRESS=\"${RELAY_SENDER_EMAIL_ADDRESS}\"
         RELAY_SENDER_INFORMAL_NAME=\"${RELAY_SENDER_INFORMAL_NAME:=Pinger}\"
         TO_EMAIL_ADDR=\"${TO_EMAIL_ADDR}\"
         STATUS_EMAIL_DAYS=\"${STATUS_EMAIL_DAYS:=30}\"

         # m h dom mon dow command
         */${INTERVAL_MIN:=5} * * * * /usr/local/pinger.sh
         "

    if crontab -u root -r > /dev/null 2>&1
        then
            echo "Prior Crontab has been removed."
        fi
    echo "$cronjob" | awk '{$1=$1;print}' | crontab -u root -; 
    echo "Crontab has been set."
    set +f

echo "Start Services..."
    syslogd -O /var/log/messages -l 6 -s 200 -b 1 # -Output to /var/log/messages, -log lvl 6 or more severe, max file -size 200kb, -b keep 1 rotated log
    /usr/sbin/postfix start

echo "Sending init/test email..."
    emailText="To: $TO_EMAIL_ADDR
        Subject: ${initText} - $ENDPOINT_NAME
        From: $RELAY_SENDER_INFORMAL_NAME <$RELAY_SENDER_EMAIL_ADDRESS>

        Ping has been successfully initialized 
        (Pinger version built on: $buildDate)

        Name: $ENDPOINT_NAME
        URL: $PING_URL
        Expected Response: \"$EXPECTED_RESPONSE\"
        Ping every: $INTERVAL_MIN minunte(s)
        Threshold: $THRESHOLD_FAILS_FOR_EMAIL failure(s) will be required to send an email.
        Reference Ping Host: $RELIABLE_REFERENCE_PING_HOST will be pinged to verify source server's connection when no response from URL.
        Status Report: Emailed every ${STATUS_EMAIL_DAYS} day(s).
        History: $logfiletext
        - Note: mount /var/log/pinger/ as a docker volume to preserve history between reboots.
        "
    echo "$emailText" | awk '{$1=$1;print}' | /usr/sbin/sendmail -t

    sleep 30
    echo "  If email not received, examine Postfix mail logs: /var/log/maillog"
    grep -E "to=.* relay=.* status=" < /var/log/maillog | grep -v root | tail -n1

echo "Starting cron, awaiting ping jobs..."
    crond -f   # keep process in -(f)oreground
