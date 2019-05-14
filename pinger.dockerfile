FROM centos:6.10
MAINTAINER Marc Lefkon

COPY pinger.sh \
     entrypoint.sh \
        /usr/local/

RUN chmod 755   /usr/local/entrypoint.sh \
                /usr/local/pinger.sh \
 && yum -y install rsyslog postfix cronie cyrus-sasl cyrus-sasl-plain

ENTRYPOINT ["/usr/local/entrypoint.sh"]