# rk322x-device-tools
Toolkit for administering, deploying and maintaining RK322x-based Android devices via USB and ADB.


# rk322x-device-tools

> Toolkit for administering, deploying and maintaining RK322x-based Android devices via USB and ADB.

This repository contains the scripts and tools used to administer, configure, deploy and maintain RK322x-based Android devices.

The toolkit is designed to be used directly from a USB drive connected to the device, with support for ADB, root access, network configuration, USB synchronization, logging, Wi-Fi/Bluetooth management and file serving.

---

## ADB

ADB is used to access the Android device from a PC.

### Open an ADB shell

From the PC:

```bash
adb shell
```

### Switch to root

```bash
su
```

### Check the current date and time

```bash
date
```

### Check the Ethernet interface

```bash
ip addr show eth0
```

Expected IP address:

```text
192.168.50.20
```

---

## DEPLOY

The main deployment script is located on the USB drive.

### Display help

```bash
sh /mnt/media_rw/4E28-7C59/deploy.sh HELP
```

### Collect logs

```bash
sh /mnt/media_rw/4E28-7C59/deploy.sh SEND_LOGS
```

Collected logs are stored in:

```text
/mnt/media_rw/4E28-7C59/log/
```

---

## SCRIPTS

The toolkit provides several scripts installed in `/data/bin`.

### Synchronize DATA → USB

```bash
/data/bin/sync_usb
```

### Add a script to the USB drive

```bash
/data/bin/add_script_to_usb <script>
```

### Disable Wi-Fi / Bluetooth

```bash
/data/bin/disable_wireless
```

---

## HEURE

Changing the system date requires root privileges on the RK322x device.

### Set the date and time

Example:

```bash
su -c 'date 080820262026.00'
```

### Format

```text
MMDDhhmmCCYY.ss
```

Where:

```text
MM   = Month
DD   = Day
hh   = Hour
mm   = Minute
CCYY = Year
ss   = Seconds
```

Example:

```text
08 08 20 26 2026 .00
```

Command:

```text
080820262026.00
```

> **Note:** The `date` command must be executed with root privileges.

---

## WIFI / BLUETOOTH

The `disable_wireless.sh` script is used to disable wireless connectivity.

The script handles:

```text
Wi-Fi
Bluetooth
wlan0
p2p0
hci0
```

### Disable wireless interfaces

```bash
/data/bin/disable_wireless
```

### Check network interfaces

```bash
ip link
```

### Check related processes

```bash
ps | grep -iE 'bluetooth|wpa|wifi'
```

---

## RESEAU / SERVEUR DE FICHIERS

The RK322x device can expose the contents of the USB drive using the BusyBox HTTP server.

### Configuration

**Device IP:**

```text
192.168.50.20
```

**Port:**

```text
8000
```

**URL:**

http://192.168.50.20:8000/

### Start the HTTP server

```bash
busybox httpd -f -p 0.0.0.0:8000 \
    -h /mnt/media_rw/4E28-7C59
```

If root privileges are required:

```bash
su -c 'busybox httpd -f -p 0.0.0.0:8000 -h /mnt/media_rw/4E28-7C59'
```

---

## STRUCTURE

```text
/
├── README.md
├── ROADMAP.md
├── TROUBLESHOOTING.md
│
├── deploy.sh
├── set_time.sh
├── set_network.sh
├── disable_wireless.sh
├── index.html
├── setHEURE_INIT.sh
├── setHEURE_FILE.sh
│
├── scripts/
│   ├── core/
│   │   ├── log.sh
│   │   ├── media.sh
│   │   └── usb.sh
│   │
│   ├── sync_usb.sh
│   ├── add_script_to_usb.sh
│   ├── add_to_bin.sh
│   ├── boxhelp.sh
│   ├── test.sh
│   └── disable_wireless.sh
│
├── log/
│   └── log_YYYYMMDD_HHMMSS/
│
├── config/
│   ├── profiles/
│   └── device.conf
│
├── history/
│   ├── config/
│   ├── deploy/
│   └── scripts/
│
├── incoming/
│
└── manifests/
    ├── history/
    └── current/
```

---

## ROADMAP

Future development and planned improvements are tracked in:

**[ROADMAP.md](ROADMAP.md)**

The roadmap covers planned improvements such as:

* New deployment features
* Additional RK322x device support
* Network configuration improvements
* Diagnostic tools
* Logging improvements
* USB management enhancements
* Device configuration profiles
* Manifest management
* Deployment automation

---

## TROUBLESHOOTING

Known issues, encountered problems and solutions are documented in:

**[TROUBLESHOOTING.md](TROUBLESHOOTING.md)**

This document should be updated whenever a new problem is identified, diagnosed or resolved.

It covers issues related to:

* ADB
* Root access
* USB mounting
* Network configuration
* Wi-Fi / Bluetooth
* Date and time
* BusyBox HTTP server
* Script execution
* Deployment
* Device-specific behavior

---

## Project Status

This project is intended as a practical administration and deployment toolkit for RK322x-based Android devices.

The toolkit is continuously evolving alongside the deployment process.

New features, fixes and known issues should be documented through the roadmap and troubleshooting documentation.
