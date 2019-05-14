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
  - **INTERVAL_MIN:**                 default: 5, Ping interval
  - **THRESHOLD_FAILS_FOR_EMAIL:**    default: 1, Threshold # of failures for failure email
- Email
  - **ENDPOINT_DESCRIPTION:**         default: "Pinger", will appear as 'subject' in emails
  - **TO_EMAIL_ADDR:**                required
- History 
  - **SAVE_HISTORY**                 default: 0 (val: 1 or 0)

## Save Data
If enabled, history is saved as a CSV file in to: /var/log/pinger/. A docker volume can be mounted here to persist. There are two fields with the format:
- Unix Timestamp
- State (1- endpoint is up, 0- endpoint is down)

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
    -e SAVE_HISTORY=1 \
    mlefkon/pinger 
```
or

> specify env vars in `./pinger.env` :
```
    $ docker run --name mypinger --env-file pinger.env -d mlefkon/pinger 
```
or

> use compose:
```
    $ docker-compose -f compose.pinger.yml up -d
```
