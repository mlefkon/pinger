FROM centos:6.10
MAINTAINER Marc Lefkon

RUN yum -y install rsyslog postfix cronie cyrus-sasl cyrus-sasl-plain bc

COPY pinger.sh \
     entrypoint.sh \
        /usr/local/

RUN chmod 755   /usr/local/entrypoint.sh \
                /usr/local/pinger.sh 

ENTRYPOINT ["/usr/local/entrypoint.sh"]