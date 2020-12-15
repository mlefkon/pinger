#!/bin/bash

timestamp=$(date +%s)

pingErrFile="/var/log/pinger/${ENDPOINT_NAME// /_}.num.fails.log"
numErrs=$([ -f $pingErrFile ] && cat $pingErrFile);
    re='^[0-9]+$'
    if ! [[ $numErrs =~ $re ]]; then numErrs=0; fi;
lastNumErrs=$numErrs;

pingStart=$(date +%s%N)
response=$(curl -s --url $PING_URL)
curlErrCode=$?
pingNano=$((($(date +%s%N) - $pingStart)))
pingTime=`echo "scale=4; $pingNano/1000000000" | bc -l | sed 's/^\./0./'`

connectionErrCode=0
if [ $curlErrCode -eq 0 ]; then
        if [ "$response" = "$EXPECTED_RESPONSE" ] ; then
            let numErrs=0; 
        else
            # tgt response error
            let numErrs=$((numErrs + 1));
        fi;
    else
        ping -c 1 -q -w 1 $RELIABLE_REFERENCE_PING_HOST &> /dev/null
        connectionErrCode=$?
        if [ $connectionErrCode -eq 0 ]; then
            # tgt connection error
            let numErrs=$((numErrs + 1));
        #else
        #    src connection err
        #    so do nothing. $numErrs remains unchanged because is src problem. tgt status is unknown.
        fi;
    fi;

if [ $numErrs -ge $THRESHOLD_FAILS_FOR_EMAIL ] && [ $connectionErrCode -eq 0 ];
    then 
        echo "`date +"%Y-%m-%d %R"`: Sending ERR email. Pinger errors: $numErrs" >> /proc/1/fd/1
cat <<EOF | /usr/sbin/sendmail -t
To: $TO_EMAIL_ADDR
Subject: ERR - $ENDPOINT_NAME
From: $RELAY_SENDER_INFORMAL_NAME <$RELAY_SENDER_EMAIL_ADDRESS>

Ping has failed on: $PING_URL
Failed Times: $numErrs
$([ "$numErrs" == "$THRESHOLD_FAILS_FOR_EMAIL" ] && echo "(Threshold to send email: $THRESHOLD_FAILS_FOR_EMAIL fails)" || echo "")


EOF
    fi

if [ $numErrs -eq 0 ] && [ $lastNumErrs -ge $THRESHOLD_FAILS_FOR_EMAIL ]; 
    then
        echo "`date +"%Y-%m-%d %R"`: Sending OK email. Condition ok. Prior errors: $numErrs" >> /proc/1/fd/1
cat <<EOF | /usr/sbin/sendmail -t
To: $TO_EMAIL_ADDR
Subject: OK - $ENDPOINT_NAME
From: $RELAY_SENDER_INFORMAL_NAME <$RELAY_SENDER_EMAIL_ADDRESS>

Ping is now OK on: $PING_URL
  (previous # errors: $lastNumErrs)

EOF
    fi;

# LOGGING
pingLogFile="/var/log/pinger/${ENDPOINT_NAME// /_}.ping.curr.log"
pingPriorLogFile="/var/log/pinger/${ENDPOINT_NAME// /_}.ping.prior.log"
firstFileTimestamp=$([ -f $pingLogFile ] && head -n1 $pingLogFile | sed 's/,.*//' || echo 0)
# STATUS REPORT EMAIL
if [ $firstFileTimestamp -ne 0 ] && [ $firstFileTimestamp -le $(($timestamp-${STATUS_EMAIL_DAYS:=30}*86400)) ];  # 86400=one day in seconds
    then 
        #Time Period
        startDate=$(date -d @$firstFileTimestamp +%D)
        endDate=$(date -d @$timestamp +%D)
        #Percent Up
        numFails=$(cat $pingLogFile | awk --field-separator=, 'BEGIN {count=0} { if ($2 == 0) { count++ } } END {print count}' )
        numConnErr=$(cat $pingLogFile | awk --field-separator=, 'BEGIN {count=0} { if ($2 == 2) { count++ } } END {print count}' )
        ttlPings=$(cat $pingLogFile | wc -l)
        failMin=$(($numFails*$INTERVAL_MIN))
        failSecs=$(($failMin*60))
        totalSecs=$(( $timestamp-$firstFileTimestamp )) 
        if [ $ttlPings -eq $numFails ]; then 
            percentUp=0  # avoid rounding errors
        else    
            percentUp=`echo "scale=4; 100-100*$failSecs/$totalSecs" | bc -l`
        fi;
        avgPingTime=$(cat $pingLogFile | awk --field-separator=, 'BEGIN {total=0; count=0;} { if ($2 == 1) { total += $3; count++;} } END { print (count == 0) ? "-" : total/count }')
        medianPingTime=$(cat $pingLogFile | sort -n -t, -k3 | awk --field-separator=, 'BEGIN {i=0;} { if ($2 == 1) { a[i++]=$3;} } END { print (i == 0) ? "-" : a[int(i/2)]; }')
        #Outages
        failureList=$(cat $pingLogFile | awk --field-separator=, '{if ($2 == 0) {print "- Outage on " strftime("%Y-%m-%d at %H:%M:%S", $1) } }')

        statusLogFile="/var/log/pinger/${ENDPOINT_NAME// /_}.summary.history.log"
        statusReportHistory=$(tail -n50 "$statusLogFile" | tac | awk --field-separator=, '{print "- " $1 " ~ " $2 ", " $3 "%, " (($4 == "-") ? "---" : $4 "s"), " (($5 == "-") ? "---" : $5 "s")}')
        echo "$startDate,$endDate,${percentUp},${medianPingTime},${avgPingTime}" >> "$statusLogFile"

        echo "`date +"%Y-%m-%d %R"`: Sending status email - $startDate to $endDate: Uptime ${percentUp}%, Median Ping Time $( [ $medianPingTime == '-' ] && echo '---' || echo ${medianPingTime}sec ), Avg Ping Time $( [ $avgPingTime == '-' ] && echo '---' || echo ${avgPingTime}sec )" >> /proc/1/fd/1
        cat <<EOF | /usr/sbin/sendmail -t
To: $TO_EMAIL_ADDR
Subject: STATUS REPORT - $ENDPOINT_NAME
From: $RELAY_SENDER_INFORMAL_NAME <$RELAY_SENDER_EMAIL_ADDRESS>

Pinger Status Report

$ENDPOINT_NAME

Time Period: $startDate to $endDate

Failed Pings: $numFails $([ "$failMin" == 0 ] && echo "" || echo " (down approx ${failMin} minutes)")
Outgoing Connection Problems: $numConnErr
- Pinging every $INTERVAL_MIN min
- Total Pings: $ttlPings
Uptime Percent: ${percentUp}% 
Median Ping Time: $([ "$medianPingTime" == "-" ] && echo "---" || echo "${medianPingTime}s")
Avg Ping Time: $([ "$avgPingTime" == "-" ] && echo "---" || echo "${avgPingTime}s")

Ping Failures:
$([ "$failureList" == "" ] && echo "  (None)" || echo "${failureList}")

Recent History:
> Time Period, Pct Up, Median Ping Time, Avg Ping Time
${statusReportHistory}

EOF

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

echo $numErrs > $pingErrFile

