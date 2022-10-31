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
         ALLOW_INSECURE=\"${ALLOW_INSECURE:=0}\"
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

echo "Sending init/test email..."
    emailText="To: $TO_EMAIL_ADDR
        Subject: ${initText} - $ENDPOINT_NAME
        From: $RELAY_SENDER_INFORMAL_NAME <$RELAY_SENDER_EMAIL_ADDRESS>

        Ping has been successfully initialized 
        (Pinger version built on: $buildDate)

        Name: $ENDPOINT_NAME
        URL: $PING_URL $(if [ $ALLOW_INSECURE -eq 0 ]; then echo ''; else echo '(invalid certs allowed)'; fi;)
        Expected Response: \"$EXPECTED_RESPONSE\"
        Ping every: $INTERVAL_MIN minunte(s)
        Threshold: $THRESHOLD_FAILS_FOR_EMAIL failure(s) will be required to send an email.
        Reference Ping Host: $RELIABLE_REFERENCE_PING_HOST will be pinged to verify source server's connection when no response from URL.
        Status Report: Emailed every ${STATUS_EMAIL_DAYS} day(s).
        History: $logfiletext
        - Note: mount /var/log/pinger/ as a docker volume to preserve history between reboots.
        "
    echo -e "$emailText" | awk '{$1=$1;print}' | curl -s -T "-" --ssl-reqd --url "$RELAY_HOST" --mail-from "$RELAY_SENDER_EMAIL_ADDRESS" --mail-rcpt "$TO_EMAIL_ADDR" --user "${RELAY_USERNAME}:${RELAY_PASSWORD}"
	echo "  sent."

echo "Starting cron, awaiting ping jobs..."
    crond -f   # keep process in -(f)oreground
