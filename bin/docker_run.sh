#!/bin/sh

docker run -d --rm --name serial2mqtt --device=/dev/serial_wde:/dev/serial_wde serial2mqtt
