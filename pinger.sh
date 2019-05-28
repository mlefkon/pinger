#!/bin/bash

pingErrFile="/var/log/pinger/${ENDPOINT_NAME// /_}.ping.err"
numerr=$([ -f $pingErrFile ] && cat $pingErrFile || echo 0);
lastnumerr=numerr;

pingstart=$(date +%s%N)
response=$(curl --url $PING_URI)
if [[ $? == 0 && $response == $EXPECTED_RESPONSE ]] ; then let numerr=0; else let numerr=$((numerr + 1)); fi;
pingnano=$((($(date +%s%N) - $pingstart)))
pingtime=`echo "scale=4; $pingnano/1000000000" | bc -l | sed 's/^\./0./'`

if [ $numerr -ge $THRESHOLD_FAILS_FOR_EMAIL ]; 
    then 
        echo "`date +"%Y-%m-%d %R"`: Sending ERR email. Ping errors: $numerr" >> /proc/1/fd/1
cat <<EOF | /usr/sbin/sendmail -t
To: $TO_EMAIL_ADDR
Subject: ERR - $ENDPOINT_NAME
From: $RELAY_SENDER_INFORMAL_NAME <$RELAY_SENDER_EMAIL_ADDRESS>

Ping has failed on: $PING_URI
Failed Times: $numerr
$([ "$numerr" == "$THRESHOLD_FAILS_FOR_EMAIL" ] && echo "(Threshold to send email: $THRESHOLD_FAILS_FOR_EMAIL fails)" || echo "")


EOF
    fi

if [[ $numerr -eq 0 && $lastnumerr -ge $THRESHOLD_FAILS_FOR_EMAIL ]]; 
    then
        echo "`date +"%Y-%m-%d %R"`: Sending OK email. Condition ok. Prior errors: $numerr" >> /proc/1/fd/1
cat <<EOF | /usr/sbin/sendmail -t
To: $TO_EMAIL_ADDR
Subject: OK - $ENDPOINT_NAME
From: $RELAY_SENDER_INFORMAL_NAME <$RELAY_SENDER_EMAIL_ADDRESS>

Ping is now OK on: $PING_URI
  (previous # errors: $lastnumerr)

EOF
    fi;

# LOGGING
ts=$(date +%s)
pingLogFile="/var/log/pinger/${ENDPOINT_NAME// /_}.ping.log"
pingPriorLogFile="/var/log/pinger/${ENDPOINT_NAME// /_}.ping.prior.log"
firstStatusTS=$([ -f $pingLogFile ] && head -n1 $pingLogFile | sed 's/,.*//' || echo 0)
# STATUS REPORT EMAIL
if [[ $firstStatusTS -ne 0 && $firstStatusTS -le $(($ts-${STATUS_EMAIL_DAYS:=30}*60)) ]];  # 86400=one day in seconds 
    then 
        #Time Period
        startdate=$(date -d @$firstStatusTS +%D)
        enddate=$(date -d @$ts +%D)
        #Percent Up
        numfails=$(cat $pingLogFile | awk --field-separator=, 'BEGIN {count=0} { if ($2 == 0) { count++ } } END {print count}' )
        ttlpings=$(cat $pingLogFile | wc -l)
        failmin=$(($numfails*$INTERVAL_MIN))
        failsecs=$(($failmin*60))
        totalsecs=$(( $ts-$firstStatusTS )) 
        if [ $ttlpings == $numfails ]; then 
            percentup=0  # avoid rounding errors
        else    
            percentup=`echo "scale=4; 100-100*$failsecs/$totalsecs" | bc -l`
        fi;
        #Average Ping Time
        avgpingtime=$(cat $pingLogFile | awk --field-separator=, 'BEGIN {total=0; count=0;} { if ($2 == 1) { total += $3; count++;} } END { print (count == 0) ? "-" : total/count }')
        #Outages
        failurelist=$(cat $pingLogFile | awk --field-separator=, '{if ($2 == 0) {print "- Outage on " strftime("%Y-%m-%d at %H:%M:%S", $1) } }')

        statusLogFile="/var/log/pinger/${ENDPOINT_NAME// /_}.history.log"
        statusReportHistory=$(tail -n50 "$statusLogFile" | tac | awk --field-separator=, '{print "- " $1 " ~ " $2 ", " $3 "%, " (($4 == "-") ? "---" : $4 "s")}')
        echo "$startdate,$enddate,${percentup},${avgpingtime}" >> "$statusLogFile"

        echo "`date +"%Y-%m-%d %R"`: Sending status email - $startdate to $enddate: Uptime ${percentup}%, Avg Ping Time $( [ $avgpingtime == '-' ] && echo '---' || echo ${avgpingtime}sec )" >> /proc/1/fd/1
        cat <<EOF | /usr/sbin/sendmail -t
To: $TO_EMAIL_ADDR
Subject: STATUS REPORT - $ENDPOINT_NAME
From: $RELAY_SENDER_INFORMAL_NAME <$RELAY_SENDER_EMAIL_ADDRESS>

Pinger Status Report

$ENDPOINT_NAME

Time Period: $startdate to $enddate

Failed Pings: $numfails $([ "$failmin" == 0 ] && echo "" || echo " (down approx ${failmin} minutes)")
- Pinging every $INTERVAL_MIN min
- Total Pings: $ttlpings
Uptime Percent: ${percentup}% 
Avg Ping Time: $([ "$avgpingtime" == "-" ] && echo "---" || echo "${avgpingtime}s")

Ping Failures:
$([ "$failurelist" == "" ] && echo "  (None)" || echo "${failurelist}")

Recent History:
> Time Period, Pct Up, Avg Ping Time
${statusReportHistory}

EOF

        mv -f "$pingLogFile" "${pingPriorLogFile}"
fi;
echo "${ts},$(( $numerr==0 ? 1 : 0 )),$pingtime" >> "$pingLogFile"

echo $numerr > $pingErrFile

