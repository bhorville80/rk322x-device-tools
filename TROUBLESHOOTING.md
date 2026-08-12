# Troubleshooting

> Known issues, diagnostics and solutions for `rk322x-device-tools`.

This document contains problems encountered during development, deployment and administration of RK322x-based Android devices.

When a new issue is identified, document it here together with the observed behavior, diagnosis and solution.

---

## ADB

### ADB device not detected

Check whether the device is visible:

```bash
adb devices
```

If the device does not appear:

1. Check the USB connection.
2. Check that Android debugging is enabled.
3. Restart the ADB server:

```bash
adb kill-server
adb start-server
```

Then check again:

```bash
adb devices
```

---

## ROOT

### `su` does not provide root access

Check:

```bash
adb shell
```

Then:

```bash
su
```

Verify the current user:

```bash
id
```

A successful root shell should report:

```text
uid=0(root)
```

If root access is unavailable, check the device image and root configuration.

---

## DATE / TIME

### `date` returns a permission error

The system date requires root privileges.

Use:

```bash
su
```

Then:

```bash
date
```

Or execute the command directly as root:

```bash
su -c 'date 080820262026.00'
```

---

## NETWORK

### Ethernet interface has no expected IP

Check the interface:

```bash
ip addr show eth0
```

Also check all interfaces:

```bash
ip addr
```

Expected configuration:

```text
192.168.50.20
```

Check the interface state:

```bash
ip link show eth0
```

---

### Cannot access the HTTP server

First verify that the server is running:

```bash
ps | grep httpd
```

Start it manually:

```bash
busybox httpd -f -p 0.0.0.0:8000 \
    -h /mnt/media_rw/4E28-7C59
```

If root privileges are required:

```bash
su -c 'busybox httpd -f -p 0.0.0.0:8000 -h /mnt/media_rw/4E28-7C59'
```

From another machine, test:

```text
http://192.168.50.20:8000/
```

---

## USB

### USB storage is not available

Check mounted filesystems:

```bash
mount
```

Check the media directory:

```bash
ls -la /mnt/media_rw/
```

Expected USB path:

```text
/mnt/media_rw/4E28-7C59
```

Verify that the directory exists:

```bash
ls -la /mnt/media_rw/4E28-7C59
```

---

### USB synchronization fails

Run the synchronization script manually:

```bash
/data/bin/sync_usb
```

Check the generated logs:

```text
/mnt/media_rw/4E28-7C59/log/
```

Also verify that the USB drive has sufficient free space.

---

## WIFI / BLUETOOTH

### Wi-Fi or Bluetooth is still active

Run:

```bash
/data/bin/disable_wireless
```

Then check interfaces:

```bash
ip link
```

Look for:

```text
wlan0
p2p0
hci0
```

Check related processes:

```bash
ps | grep -iE 'bluetooth|wpa|wifi'
```

---

## DEPLOYMENT

### `deploy.sh` does not execute

Check that the file exists:

```bash
ls -la /mnt/media_rw/4E28-7C59/deploy.sh
```

Run the help command:

```bash
sh /mnt/media_rw/4E28-7C59/deploy.sh HELP
```

If the script depends on other files, verify that the complete USB directory structure is present.

---

### Deployment logs are missing

Check:

```bash
ls -la /mnt/media_rw/4E28-7C59/log/
```

Then collect logs:

```bash
sh /mnt/media_rw/4E28-7C59/deploy.sh SEND_LOGS
```

Verify that the USB storage is writable.

---

## SCRIPT EXECUTION

### Script returns `Permission denied`

Check permissions:

```bash
ls -la /data/bin/
```

Try executing the script through the shell:

```bash
sh /data/bin/<script>
```

If the script is stored on the USB drive:

```bash
sh /mnt/media_rw/4E28-7C59/<script>
```

---

## DIAGNOSTIC COMMANDS

### Device information

```bash
getprop
```

### Current user

```bash
id
```

### Network

```bash
ip addr
```

```bash
ip link
```

### Processes

```bash
ps
```

### Mounted filesystems

```bash
mount
```

### Storage

```bash
df -h
```

### Current date

```bash
date
```

---

## Logging Issues

When reporting a problem, collect the following information whenever possible:

```text
Device model:
RK322x variant:
Android version:
Date/time:
IP address:
ADB status:
Root status:
USB status:
Deployment command:
Error message:
Relevant logs:
```

Logs should preferably be collected using:

```bash
sh /mnt/media_rw/4E28-7C59/deploy.sh SEND_LOGS
```

---

## Issue History

Document confirmed issues below.

### Template

```text
Date:
Device:
Version:
Problem:
Symptoms:
Diagnosis:
Solution:
Status:
```

---

## Notes

This document should evolve with the project.

Every recurring issue should eventually have:

1. A clear description.
2. The symptoms observed.
3. The diagnostic commands used.
4. The identified cause.
5. The solution or workaround.
6. The affected version, when known.
