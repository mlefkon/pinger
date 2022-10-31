FROM alpine:3.16.2 
LABEL maintainer="Marc Lefkon"

RUN apk add bc curl
  #cron already installed in base.

COPY pinger.sh \
     entrypoint.sh \
        /usr/local/

RUN chmod 755   /usr/local/entrypoint.sh \
                /usr/local/pinger.sh \
 && date      > /usr/local/pinger.build \
 && mkdir -p /var/log/pinger 

ENTRYPOINT ["/usr/local/entrypoint.sh"]