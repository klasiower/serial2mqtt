#!/bin/sh

docker run -d --rm --name serial2mqtt                   \
    --restart=unless-stopped                            \
    --device=/dev/serial_wde:/dev/serial_wde            \
    -v /etc/localtime:/etc/localtime:ro                 \
    serial2mqtt
