FROM alpine:3.12
LABEL maintainer="Marc Lefkon"

RUN apk add postfix cyrus-sasl cyrus-sasl-plain bc curl
        #syslogd, cron already installed in base.

COPY pinger.sh \
     entrypoint.sh \
        /usr/local/

RUN chmod 755   /usr/local/entrypoint.sh \
                /usr/local/pinger.sh \
 && date      > /usr/local/pinger.build \
 && mkdir -p /var/log/pinger 


ENTRYPOINT ["/usr/local/entrypoint.sh"]