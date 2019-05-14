#!/bin/bash

numerr=$([ -f /var/local/pinger_err ] && cat /var/local/pinger_err || echo 0);
lastnumerr=numerr;
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
if [[ $numerr -eq 0 && $lastnumerr -ge $THRESHOLD_FAILS_FOR_EMAIL ]]; 
    then
        echo "Sending OK email. Condition ok. Prior errors: $numerr" >> /proc/1/fd/1
cat <<EOF | /usr/sbin/sendmail -t
To: $TO_EMAIL_ADDR
Subject: OK - $ENDPOINT_DESCRIPTION
From: $RELAY_SENDER_INFORMAL_NAME <$RELAY_SENDER_EMAIL_ADDRESS>

Ping is now OK on: $PING_URI
  (previous # errors: $lastnumerr)

EOF
    fi;

if [ $SAVE_HISTORY == 1 ]; then
    ts=$(date +%s)
    logfile="/var/log/pinger/${ENDPOINT_DESCRIPTION// /_}.log"
    laststatus=$([ -f $logfile ] && head -n1 $logfile | sed 's/,.*//' || echo 0)
    echo "${ts},$(( $numerr==0 ? 1 : 0 ))" >> "$logfile"
    if [[ $laststatus != 0 && $laststatus < $(($ts-${STATUS_EMAIL_DAYS:=30}*86400)) ]];  # 86400=one day in seconds
        then 
            numfails=$(grep ",0" $logfile | wc -l)
            failsecs=$(($numfails*$INTERVAL_MIN*60))
            totalsecs=$(($ts-$laststatus))
            percentup=`echo "scale=4; 100-100*$failsecs/$totalsecs" | bc -l`
            startdate=$(date -d @$laststatus +%D)
            enddate=$(date -d @$ts +%D)
            echo "Sending status email: Uptime ${percentup}% from $startdate to $enddate" >> /proc/1/fd/1
            cat <<EOF | /usr/sbin/sendmail -t
To: $TO_EMAIL_ADDR
Subject: STATUS REPORT - $ENDPOINT_DESCRIPTION
From: $RELAY_SENDER_INFORMAL_NAME <$RELAY_SENDER_EMAIL_ADDRESS>

Pinger Status Report

Uptime ${percentup}% from $startdate to $enddate

Failed Pings: $numfails (interval: ${INTERVAL_MIN})

EOF

        mv -f "$logfile" "${logfile}.old"
    fi;
fi;

echo $numerr > /var/local/pinger_err

