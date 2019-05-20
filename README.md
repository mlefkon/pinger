# Pinger - crontab curl requests & email on failure

Source repository [Github: mlefkon/pinger](https://github.com/mlefkon/pinger)

## What it does

A docker container cronjob runs `curl` to 'ping' your server/endpoint. An email is sent if there are any problems.

This was designed to work with Zoho mail's SMTP relay.  It may work with many others.

## Configuration (Environment Variables)
- Target Server
  - **PING_URI:**                     required, any valid curl URI
  - **EXPECTED_RESPONSE:**            required, expected text body returned from PING_URI
- Mail Relay
  - **RELAY_HOST:**                   required, format (incl sq brackets): [relay.host.tld]:port
  - **RELAY_USERNAME:**               required, user's login to relay mail host
  - **RELAY_PASSWORD:**               required
  - **RELAY_SENDER_EMAIL_ADDRESS:**   required, should be permitted to send mails by relay host, often same as username
  - **RELAY_SENDER_INFORMAL_NAME:**   default: Pinger
- Timing
  - **INTERVAL_MIN:**                 default: 5, minutes between pings
  - **THRESHOLD_FAILS_FOR_EMAIL:**    default: 1, num of failures before an alert email is sent
- Email
  - **ENDPOINT_DESCRIPTION:**         default: "Pinger", will appear as 'subject' in emails
  - **TO_EMAIL_ADDR:**                required, recipient of alert emails
- Status Report 
  - **STATUS_EMAIL_DAYS**             default: 30, Status report email will be send every X days
	
## Status Report
At the end of each `${STATUS_EMAIL_DAYS}` time period and email will be sent with:
- Start/End Dates
- Total down time
- Percent up  
- Average ping time

## Historical Data

Data is saved to `${ENDPOINT_DESCRIPTION}.log` files in `/var/log/pinger/`. A docker volume can be mounted here to persist. There are two CSV files with the formats:
- Ping History (only current period. Prior period is moved to ~.prior.log)
	- Unix Timestamp
	- State (1- endpoint is up, 0- endpoint is down)
	- Ping time
- Status History
	- From Date
	- To Date
	- Up Time Percentage
	- Average Ping Time

## Run
```
    $ docker run --name mypinger -d \
    -e ENDPOINT_DESCRIPTION="My Pinger" \
    -e INTERVAL_MIN=3 \
    -e THRESHOLD_FAILS_FOR_EMAIL=2 \
    -e PING_URI=https://my.url.com/myscript \
    -e EXPECTED_RESPONSE="eg: Ping succeeded" \
    -e RELAY_HOST=[mail.relay.com]:587 \
    -e RELAY_USERNAME=user \
    -e RELAY_PASSWORD=pass \
    -e RELAY_SENDER_EMAIL_ADDRESS=useremail@relay.com \
    -e RELAY_SENDER_INFORMAL_NAME="Pinger Alert" \
    -e TO_EMAIL_ADDR=destination@email.com \
    -e STATUS_EMAIL_DAYS=7 \
    mlefkon/pinger 
```
or

> specify env vars in `./pinger.env` (one per line as: VAR=val, no quotes needed for strings with spaces):
```
    $ docker run --name mypinger --env-file pinger.env -d mlefkon/pinger 
```
