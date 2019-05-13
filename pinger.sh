#!/bin/bash

let numerr=0

if [ -f /var/local/ping_err ]; 
    then 
        let numerr=$(cat /var/local/ping_err); 
    else
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

fi; 
let lasterr=numerr;
if [[ $(curl --url $PING_URI) == $EXPECTED_RESPONSE ]] ; then let numerr=0; else let numerr=$((numerr + 1)); fi;
if [ $numerr -ge $THRESHOLD_FAILS_FOR_EMAIL ]; 
    then 
        echo "Sending ERR email. Ping errors: $numerr" >> /proc/1/fd/1
cat <<EOF | /usr/sbin/sendmail -t
To: $TO_EMAIL_ADDR
Subject: ERR - $ENDPOINT_DESCRIPTION
From: $RELAY_SENDER_INFORMAL_NAME <$RELAY_SENDER_EMAIL_ADDRESS>

Ping has failed on: $PING_URI
Failed Times: $numerr
$([ "$numerr" == "$THRESHOLD_FAILS_FOR_EMAIL" ] && echo "(Send email threshold: $THRESHOLD_FAILS_FOR_EMAIL)" || echo "")


EOF
    fi
if [[ $numerr -eq 0 && $lasterr -ge $THRESHOLD_FAILS_FOR_EMAIL ]]; 
    then
        echo "Sending OK email. Condition ok. Prior errors: $numerr" >> /proc/1/fd/1
cat <<EOF | /usr/sbin/sendmail -t
To: $TO_EMAIL_ADDR
Subject: OK - $ENDPOINT_DESCRIPTION
From: $RELAY_SENDER_INFORMAL_NAME <$RELAY_SENDER_EMAIL_ADDRESS>

Ping is now OK on: $PING_URI
  (previous # errors: $lasterr)

EOF
    fi;

echo "$(date +%s),$(( $numerr==0 ? 1 : 0 ))" >> "/var/log/pinger/${ENDPOINT_DESCRIPTION// /_}.log"

echo $numerr > /var/local/ping_err