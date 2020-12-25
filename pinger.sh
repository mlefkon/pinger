#!/bin/sh

timestamp=$(date +%s)

pingErrFile=$( echo "/var/log/pinger/${ENDPOINT_NAME}.num.fails.log" | tr "[:blank:]" _ )
numErrs=$([ -f "$pingErrFile" ] && cat "$pingErrFile");
    if echo "$numErrs" | test ! "$(grep -e "^[0-9]\{1,\}$")"; 
        then numErrs=0;
    fi;
lastNumErrs=$numErrs;

#busybox `date` fn does not support nanoseconds (+%s%N), so use sys-time  
#    https://unix.stackexchange.com/questions/167968/date-in-milliseconds-on-openwrt-on-arduino-yun
sys_uptime() {
    sysSec=$(adjtimex | grep time.tv_sec | awk -F : '{print $2}' | tr -d ' ')
    sysUSec=$(adjtimex | grep time.tv_usec | awk -F : '{printf("%06d\n", $2)}' | tr -d ' ')
    echo "$sysSec.$sysUSec"
}

pingStart=$( sys_uptime )
response=$(curl -s --url "$PING_URL")
curlErrCode=$?
pingEnd=$( sys_uptime )
pingTimeRaw=$( awk "BEGIN {print $pingEnd-$pingStart}" )
pingTime=$( echo "scale=4; $pingTimeRaw/1" | bc -l | sed 's/^\./0./' ) # round to 4 decimals and add ones-place zero if needed

connectionErrCode=0
if [ $curlErrCode -eq 0 ]; then
        if [ "$response" = "$EXPECTED_RESPONSE" ] ; then
            numErrs=0;
        else
            echo "tgt response error"
            numErrs=$((numErrs + 1));
        fi;
    else
        ping -c 1 -q -w 1 "$RELIABLE_REFERENCE_PING_HOST" > /dev/null 2>&1
        connectionErrCode=$?
        if [ $connectionErrCode -eq 0 ]; then
            echo "tgt connection error"
            numErrs=$((numErrs + 1));
        else
            echo "src connection err"
            # so do nothing. $numErrs remains unchanged because is src problem. tgt status is unknown.
        fi;
    fi;

if [ $numErrs -ge "$THRESHOLD_FAILS_FOR_EMAIL" ] && [ $connectionErrCode -eq 0 ];
    then 
        echo "$(date +"%Y-%m-%d %R"): Sending ERR email. Pinger errors: $numErrs" >> /proc/1/fd/1
        emailText="To: $TO_EMAIL_ADDR
            Subject: ERR - $ENDPOINT_NAME
            From: $RELAY_SENDER_INFORMAL_NAME <$RELAY_SENDER_EMAIL_ADDRESS>

            Ping has failed on: $PING_URL
            Failed Times: $numErrs
            $([ "$numErrs" = "$THRESHOLD_FAILS_FOR_EMAIL" ] && echo "(Threshold to send email: $THRESHOLD_FAILS_FOR_EMAIL fails)" || echo "")
            "
        echo "$emailText" | awk '{$1=$1;print}' | /usr/sbin/sendmail -t
    fi

if [ $numErrs -eq 0 ] && [ $lastNumErrs -ge "$THRESHOLD_FAILS_FOR_EMAIL" ]; 
    then
        echo "$(date +"%Y-%m-%d %R"): Sending OK email. Condition ok. Prior errors: $numErrs" >> /proc/1/fd/1
        emailText="To: $TO_EMAIL_ADDR
            Subject: OK - $ENDPOINT_NAME
            From: $RELAY_SENDER_INFORMAL_NAME <$RELAY_SENDER_EMAIL_ADDRESS>

            Ping is now OK on: $PING_URL
            (previous # errors: $lastNumErrs)
            "
        echo "$emailText" | awk '{$1=$1;print}' | /usr/sbin/sendmail -t
    fi;

# LOGGING
pingLogFile=$( echo "/var/log/pinger/${ENDPOINT_NAME}.ping.curr.log" | tr "[:blank:]" _ )
pingPriorLogFile=$( echo "/var/log/pinger/${ENDPOINT_NAME}.ping.prior.log" | tr "[:blank:]" _ )
firstFileTimestamp=$([ -f "$pingLogFile" ] && head -n1 "$pingLogFile" | sed 's/,.*//' || echo 0)
# STATUS REPORT EMAIL
if [ "$firstFileTimestamp" -ne 0 ] && [ "$firstFileTimestamp" -le $((timestamp-${STATUS_EMAIL_DAYS:=30}*86400)) ];  # 86400=one day in seconds
    then 
        #Time Period
        startDate=$(date -d "@$firstFileTimestamp" +%D)
        endDate=$(date -d "@$timestamp" +%D)
        #Percent Up
        numFails=$( awk -F , 'BEGIN {count=0} { if ($2 == 0) { count++ } } END {print count}' < "$pingLogFile" )
        numConnErr=$( awk -F , 'BEGIN {count=0} { if ($2 == 2) { count++ } } END {print count}' < "$pingLogFile" )
        ttlPings=$( wc -l < "$pingLogFile" )
        failMin=$(( numFails*INTERVAL_MIN ))
        failSecs=$(( failMin*60 ))
        totalSecs=$(( timestamp-firstFileTimestamp )) 
        if [ "$ttlPings" -eq "$numFails" ]; then 
            percentUp=0  # avoid rounding errors
        else    
            percentUp=$( echo "scale=4; 100-100*$failSecs/$totalSecs" | bc -l )
        fi;
        avgPingTime=$( <"$pingLogFile" awk -F , 'BEGIN {total=0; count=0;} { if ($2 == 1) { total += $3; count++;} } END { if (count == 0) {print "-"} else {printf "%.2f",total/count} }' )
        medianPingTime=$( <"$pingLogFile" sort -n -t, -k3 | awk -F , 'BEGIN {i=0;} { if ($2 == 1) { a[i++]=$3;} } END { if (i == 0) {print "-"} else {printf "%.2f",a[int(i/2)]} }' )
        #Outages
        failureList=$( <"$pingLogFile" awk -F , '{if ($2 == 0) {print "- Outage on " strftime("%Y-%m-%d at %H:%M:%S", $1) } }' )

        statusLogFile=$( echo "/var/log/pinger/${ENDPOINT_NAME}.summary.history.log" | tr "[:blank:]" _ )
        statusReportHistory=$(tail -n50 "$statusLogFile" | tac | awk -F , '{print "- " $1 " ~ " $2 ", " $3 "%, " (($4 == "-") ? "---" : $4 "s") ", " (($5 == "-") ? "---" : ($5 == "") ? "n/a" : $5 "s")}')
        echo "$startDate,$endDate,${percentUp},${avgPingTime},${medianPingTime}" >> "$statusLogFile"

        echo "$(date +"%Y-%m-%d %R"): Sending status email - $startDate to $endDate: Uptime ${percentUp}%, Median Ping Time $( [ "$medianPingTime" = '-' ] && echo '---' || echo "$medianPingTime"sec ), Avg Ping Time $( [ "$avgPingTime" = '-' ] && echo '---' || echo "$avgPingTime"sec )" >> /proc/1/fd/1
        emailText="To: $TO_EMAIL_ADDR
            Subject: STATUS REPORT - $ENDPOINT_NAME
            From: $RELAY_SENDER_INFORMAL_NAME <$RELAY_SENDER_EMAIL_ADDRESS>

            Pinger Status Report

            $ENDPOINT_NAME

            Time Period: $startDate to $endDate

            Failed Pings (at target): $numFails $([ "$failMin" -eq 0 ] && echo "" || echo " (down approx ${failMin} minutes)")
            Connection Problems (at source): $numConnErr
            - Pinging every $INTERVAL_MIN min
            - Total Pings: $ttlPings
            Uptime Percent: ${percentUp}% 
            Median Ping Time: $([ "$medianPingTime" = "-" ] && echo "---" || echo "${medianPingTime}s")
            Avg Ping Time: $([ "$avgPingTime" = "-" ] && echo "---" || echo "${avgPingTime}s")

            Ping Failures:
            $([ "$failureList" = "" ] && echo "  (None)" || echo "${failureList}")

            Recent History:
            > Time Period, Pct Up, Avg Ping Time, Median Ping Time
            ${statusReportHistory}
            "
        echo "$emailText" | awk '{$1=$1;print}' | /usr/sbin/sendmail -t

        mv -f "$pingLogFile" "${pingPriorLogFile}"
fi;

if [ $connectionErrCode -ne 0 ]; then
    statusCode=2
elif [ $numErrs -eq 0 ]; then
    statusCode=1
else
    statusCode=0
fi

echo "${timestamp},${statusCode},${pingTime}" >> "$pingLogFile"

echo $numErrs > "$pingErrFile"

