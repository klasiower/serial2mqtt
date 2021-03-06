# serial2mqtt

Serial to MQTT message router 

This script was originally written to include an ancient temperature / humidity receiver into [home assistant](https://www.home-assistant.io/).
The receiver is a ["ELV USB-WDE1 Wetterdatenempfänger"](https://de.elv.com/elv-usb-wetterdaten-empfaenger-usb-wde1-092030), which gets its readings via a 868MHz link and reports it to a serial port.
This scripts listens on a serial port, parses the USB-WDE1 reading and reports them via MQTT to a broker.

The repository provides multiple ways to run the script:

* manually
* via systemd as a service
* as a Docker container

## quick start (manually)

* `git clone` this repository to a directory of your choice and edit the configuration file `conf/serial2mqtt.json`
* install prerequisites: `apt install libpoe-perl libproc-daemon-perl libjson-perl libdevice-serialport-perl`
* start the script with `bin/serial2mqtt.pl -D -l data/serial2mqtt.log -c conf/serial2mqtt.json`

### command line parameters

```
usage: bin/serial2mqtt.pl
    -c, --config-file=file      config file to use (default: ./conf/serial2mqtt.json)
    -l, --log-file=file         log file           (default: -)
    -D, --daemonize             run in background  (default: no)
    -h, --help                  this help
```

## running as Docker container

* build docker image: `bin/docker_build.sh`
* run image: `bin/docker_run.sh`

to watch logs, run `docker exec -it serial2mqtt tail -F data/serial2mqtt.log`

## boot persistance via systemd

* edit, then copy the provided template `conf/serial2mqtt.service` to `/etc/systemd/system/`
* reload systemd `systemctl daemon-reload`
* start the new service `serial2mqtt.service` manually
* check if everything went right: `systemctl status serial2mqtt.service`
* if not, check the logs: `journalctl -u serial2mqtt.service`
* add persistance on boot: `systemctl enable serial2mqtt.service` (not needed, already done)

# Configuration

```
# *main module*
{
    # logging settings: where to log, what to log:
    "log_file"   : "./data/serial2mqtt.log",
    "debug"      : 1,
    "verbose"    : 1,
    # POE internal unique name, do not change
    "name"       : "main",
    # daemonization options
    "daemonize"  : 1,
    # user to run the daemon as
    # on a debian system, the user needs to be part of the dialout group
    "setuid"     : "my_user",
    "setgid"     : "my_group1 my_group2 dialout",
    "pid_file"   : "./data/serial2mqtt.pid",

    # *statistics output module*:
    "stats"         : {
        # en-/disable module
        "enable"    : 1,
        # emit statistics every this seconds
        "every"     : 300,
        # POE internal unique name / callbacks, do not change
        "name"      : "stats",
        "every_callback" : {
            "event"      : "ev_got_stats",
            "session"    : "main"
        }
    },

    # *serial input module:*
    "serial" : {
        # en-/disable module
        "enable" : 1,
        # serial port name, see below how to configure a static name
        "port" : "/dev/serial_wde",
        # serial port params: 9600 8N1
        "baudrate" : 9600,
        "databits" : 8,
        "parity" : "none",
        "stopbits" : 1
        "datatype" : "raw",
        "handshake" : "none",
        # watchdog, restarts on error after this number of seconds
        "restart_on_error_delay" : 20,
        # POE internal unique name / callbacks, do not change
        "name" : "serial",
        "input_callback" : {
            "session" : "main",
            "event" : "ev_got_input"
        }
    },
    # *mqtt output module:*
    "mqtt" : {
        # en-/disable module
        "enable" : 1,
        # IP / hostname of broker
        "broker" : "192.168.2.2",
        # topic to publish readings
        "topic" : "/custom/sensor1"
        # retain mqtt messages
        "retain" : 1,
        # POE internal unique name / callbacks, do not change
        "name" : "mqtt",
    },
    # *file* input module:
    # used for debugging
    "file" : {
        # en-/disable module
        "enable" : 0,
        "path" : "./data/serial_input.txt",
        # POE internal unique name / callbacks, do not change
        "name" : "file",
        "input_callback" : {
            "event" : "ev_got_input",
            "session" : "main"
        }
    }
}
```

# tips and tricks

## integration of GMC-200E Plus Geiger counter

`bin/serial2mqtt-geiger.pl` is configured to read and report Counts Per Minute / Second of a [GMC-200E Plus](https://www.gqelectronicsllc.com/GMC_300E_Plus_User_Guide.pdf) Geiger Counter

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
