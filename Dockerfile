FROM  debian:stable-slim
LABEL maintainer="Dirk Stander <dst+dev@glaskugel.org>"

# Environment
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=C.UTF-8 \
    LANGUAGE=en_US.UTF-8

# Install runtime packages
RUN apt-get update \
    && apt-get install -y perl

# Update system and install packages
RUN apt-get update \
    && apt-get install -yq libpoe-perl libproc-daemon-perl libjson-perl libdevice-serialport-perl

COPY    . /opt/serial2mqtt
WORKDIR   /opt/serial2mqtt
CMD [ "perl", "./bin/serial2mqtt.pl", "-l", "data/serial2mqtt.log", "-c", "conf/serial2mqtt.json" ]
