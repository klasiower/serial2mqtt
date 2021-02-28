# serial2mqtt

Serial to MQTT message router 

This script was originally written to include an ancient temperature / humidity receiver into [home assistant](https://www.home-assistant.io/).
The receiver is a ["ELV USB-WDE1 Wetterdatenempfänger"](https://de.elv.com/elv-usb-wetterdaten-empfaenger-usb-wde1-092030), which gets its readings via a 868MHz link and reports it to a serial port.
This scripts listens on a serial port, parses the USB-WDE1 reading and reports them via MQTT to a broker.

## Usage

* `git clone` this repository to a directory of your choice and edit the configuration file `conf/serial2mqtt.json`
* start the script with `bin/serial2mqtt.pl -c conf/serial2mqtt.json -D`

## Configuration

*main module*<br>
`{`<br>
logging settings: where to log, what to log:<br>
`   "log_file"   : "./data/serial2mqtt.log",`<br>
`   "debug"      : 1,`<br>
`   "verbose"    : 1,`<br>
POE internal unique name, do not change<br>
`   "name"       : "main",`<br>
daemonization options<br>
`   "pid_file"   : "./data/serial2mqtt.pid",`<br>
<br>
*statistics module*<br>
`   "stats"         : {`<br>
en-/disable statistics<br>
`       "enable"    : 1,`<br>
emit statistics every this seconds<br>
`       "every"     : 300,`<br>
POE internal unique name / callbacks, do not change<br>
`        "name"      : "stats",`<br>
`        "every_callback" : {`<br>
`            "event"      : "ev_got_stats",`<br>
`            "session"    : "main"`<br>
`        }`<br>
`   },`<br>
*serial module*<br>
`   "serial" : {`<br>
`      "enable" : 1,`<br>
`      "name" : "serial",`<br>
`      "port" : "/dev/serial_wde",`<br>
`      "datatype" : "raw",`<br>
`      "baudrate" : 9600,`<br>
`      "databits" : 8,`<br>
`      "parity" : "none",`<br>
`      "handshake" : "none",`<br>
`      "restart_on_error_delay" : 20,`<br>
`      "stopbits" : 1`<br>
`      "input_callback" : {`<br>
`         "session" : "main",`<br>
`         "event" : "ev_got_input"`<br>
`      }`<br>
`   },`<br>
*mqtt module*<br>
`   "mqtt" : {`<br>
`      "enable" : 1,`<br>
`      "retain" : 1,`<br>
`      "name" : "mqtt",`<br>
`      "broker" : "192.168.2.2",`<br>
`      "topic" : "/custom/sensor1"`<br>
`   },`<br>
*file module (used for debugging)*<br>
`   "file" : {`<br>
`      "enable" : 0,`<br>
`      "path" : "./data/serial_input.txt",`<br>
`      "name" : "file",`<br>
`      "input_callback" : {`<br>
`         "event" : "ev_got_input",`<br>
`         "session" : "main"`<br>
`      }`<br>
`   }`<br>
`}`<br>

## udev rule for a fixed device name

edit or create the file /etc/udev/rules.d/10-local.rules

```
# usb 1-4.3: new full-speed USB device number 13 using xhci_hcd
# usb 1-4.3: New USB device found, idVendor=10c4, idProduct=ea60, bcdDevice= 1.00
# usb 1-4.3: New USB device strings: Mfr=1, Product=2, SerialNumber=3
# usb 1-4.3: Product: ELV USB-WDE1 Wetterdatenempfänger
# usb 1-4.3: Manufacturer: Silicon Labs
# usb 1-4.3: SerialNumber: 0xxxxxxxxxxxxxP
ACTION=="add", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", SYMLINK+="serial_wde"
```

this will link a static device name of /dev/serial_wde to /dev/ttyUSBxy

reload udev rules:
sudo udevadm trigger

## power cycle USB ports

```
root@nuc:/home/dst# uhubctl 
Current status for hub 2-4 [0451:8140, USB 3.00, 4 ports]
  Port 1: 06a0 power Rx.Detect
  Port 2: 06a0 power Rx.Detect
  Port 3: 06a0 power Rx.Detect
  Port 4: 0203 power 5gbps U0 enable connect [0bda:8153 Realtek USB 10/100/1000 LAN 000001000000]
Current status for hub 1-4 [0451:8142 7xxxxxxxxxxD, USB 2.10, 4 ports]
  Port 1: 0100 power
  Port 2: 0100 power
  Port 3: 0103 power enable connect [10c4:ea60 Silicon Labs ELV USB-WDE1 Wetterdatenempf?nger 0xxxxxxxxxxxxxP]
  Port 4: 0100 power
```

the WDE serial is connected to hub 1-4 port 3

to switch power off, use:

uhubctl -a 0 -l 1-4 -p 3

to power it on again, use:

uhubctl -a 1 -l 1-4 -p 3

## add to home assistant

```
sensor:
  - platform: mqtt
    name: "wde_sensor1_temp"
    unique_id: "wde_sensor1_temp"
    state_topic: "/custom/sensor1"
    device_class: temperature
    unit_of_measurement: "°C"
    expire_after: 600
    force_update: true
    value_template: "{{ value_json.temp }}"
  - platform: mqtt
    name: "wde_sensor1_hum"
    unique_id: "wde_sensor1_hum"
    state_topic: "/custom/sensor1"
    device_class: humidity
    unit_of_measurement: "%"
    expire_after: 600
    force_update: true
    value_template: "{{ value_json.hum}}"
```
