# Pinger - crontab curl requests & email on failure

Image repository [Dockerhub: mlefkon/pinger](https://hub.docker.com/r/mlefkon/pinger) , Source repository [Github: mlefkon/pinger](https://github.com/mlefkon/pinger)

## What it does

A docker container cronjob runs `curl` to 'ping' your server/endpoint. An email is sent if there are any problems.

This was designed to work with Zoho mail's SMTP relay.  It may work with many others.

## Configuration (Environment Variables)

- Target Server
  - **ENDPOINT_NAME:**                default: "Pinger", used for email 'subject' & logfile names about this Pinger instance
  - **PING_URL:**                     required, any valid curl URL
  - **ALLOW_INSECURE:**               default: 0, allow for invalid certificate (set to '1')
  - **EXPECTED_RESPONSE:**            required, expected text body returned from PING_URL
  - **INTERVAL_MIN:**                 default: 5, minutes between pings
  - **RELIABLE_REFERENCE_PING_HOST:** required, for connectivity test in case of PING_URL failure. Must be a ping-responsive host, not a URL.
- Mail Relay
  - **RELAY_HOST:**                   required, format (incl sq brackets): [relay.host.tld]:port
  - **RELAY_USERNAME:**               required, user's login to relay mail host
  - **RELAY_PASSWORD:**               required
  - **RELAY_SENDER_EMAIL_ADDRESS:**   required, should be permitted to send mails by relay host, often same as username
  - **RELAY_SENDER_INFORMAL_NAME:**   default: Pinger
- Notification
  - **TO_EMAIL_ADDR:**                required, recipient of alert emails
  - **THRESHOLD_FAILS_FOR_EMAIL:**    default: 1, num of failures before an alert email is sent
  - **STATUS_EMAIL_DAYS**             default: 30, Status report email will be send every X days

## Status Report

At the end of each `${STATUS_EMAIL_DAYS}` time period and email will be sent with:

- Start/End Dates
- Total down time (& times of failures)
- Percent up  
- Median/Average ping time

## Historical Data

Data is saved to `${ENDPOINT_NAME}.{ping|fails|history}.log` files in `/var/log/pinger/`. A docker volume can be mounted here to persist. These are CSV files with the formats:

- Pings (~.ping.curr.log, has only current period. This is moved to ~.ping.prior.log after status report is sent.)
  - Unix Timestamp
  - Result (1- endpoint is up, 0- endpoint is down)
  - Ping Response Time
- Summary History (~.summary.history.log)
  - From Date
  - To Date
  - Up Time Percentage
  - Median Ping Time
  - Average Ping Time
- Fails (~.num.fails.log)
  - Number of current fails (reset to zero after a success)

## Run

```bash
    $ docker run --name mypinger -d \
    -e ENDPOINT_NAME="My Pinger" \
    -e INTERVAL_MIN=3 \
    -e THRESHOLD_FAILS_FOR_EMAIL=2 \
    -e PING_URL=https://my.url.com/myscript \
    -e ALLOW_INSECURE=0 \
    -e RELIABLE_REFERENCE_PING_HOST=google.com \
    -e EXPECTED_RESPONSE="eg: Ping succeeded" \
    -e RELAY_HOST=[mail.relay.com]:587 \
    -e RELAY_USERNAME=user \
    -e RELAY_PASSWORD=pass \
    -e RELAY_SENDER_EMAIL_ADDRESS=useremail@relay.com \
    -e RELAY_SENDER_INFORMAL_NAME="Pinger Alert" \
    -e TO_EMAIL_ADDR=recipient@email.com \
    -e STATUS_EMAIL_DAYS=7 \
    mlefkon/pinger 
```
