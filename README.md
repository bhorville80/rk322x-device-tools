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

> **Note (v3):** `deploy` et `amorce` s'elevent automatiquement via `su` pour les actions privilegiees - plus besoin de taper `su` d'abord.

---

## V3 / DEMARRAGE RAPIDE

La cle est montee en **noexec** : toujours `sh <chemin>`, jamais `./script`.

Premiere fois, depuis le PC :

```bash
adb shell
su -c 'sh /mnt/media_rw/*/deploy.sh INSTALL'
exit
```

Le glob `*` detecte seul l'ID de la cle. Ensuite, sur la box :

```bash
amorce                # etat : versions cle/box + rappel des commandes
amorce INSTALL        # mise a jour depuis la cle
amorce EXPOSE         # HTTP 8000 (+ GUI 8081)
amorce SELFTEST       # tous les outils repondent ?
```

Aide memoire complete : `cat /mnt/media_rw/*/AMORCE`

### Outils v3

| Outil | Role |
|---|---|
| `cut_services STATUS/CUT [SAFE\|FULL]/APPS [MAX]/RESTORE` | allègement services init + paquets usine, gain RAM mesure |
| `system_rw RW/RO/STATUS` | bascule /system lecture-ecriture |
| `front_led STATUS/LED/TRIGGER/BLINK/OFF/DEMO STOP` | afficheur frontal (leds sysfs + horloge FD655) |
| `net_diag STATUS/PORTS/PING/THROUGHPUT` | diagnostics reseau |
| `vitals STATUS/WATCH [N] [S]` | signes vitaux : temperatures, CPU/charge, RAM, usure eMMC, lien reseau, alimentation |
| `sys_diag` | sante systeme : horloge 1970, lmkd, entropie, eMMC, securite |
| `sd_inspect STATUS/DMESG` | carte SD : enumeration mmc, montage/vold, traces du boot bloque |
| `inspect_all` | rapport global : tous les inspect/check avec rc par outil |
| `motd ON/SET/DEFAULT` | message d'accueil adb shell (type MOTD ssh) |
| `ssh_server START/STOP/STATUS` | SSH dropbear optionnel - binaire non fourni, jamais lance auto |
| `deploy VERSION/STATUS/CLEAN [DRY]` | versions, etat deploiement, assainissement |

### Sequence d'allegement 24/7

```bash
selftest            # tout repond
cut_services CUT    # services SAFE + paquets usine
cut_services APPS   # GMS/Play/katniss/DLNA/usine (UI conservee)
check_state         # vue globale
# phase 2 (headless total) :
cut_services CUT FULL && cut_services APPS MAX
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

### Unified command : set_time

```bash
set_time STATUS      # heure actuelle + sources disponibles
set_time AUTO        # ordre : INIT (codee) -> FILE (cle) -> adb (poussee PC)
set_time FILE        # force la lecture du fichier SET_HEURE sur la cle
set_time RTC         # force l'heure depuis l'horloge materielle (manuel)
set_time INIT        # valeur codee de secours
set_time SET <v>     # valeur passee par le PC (adb / panneau web)
```

`SET_HEURE` is written at the USB key root by the PC before deployment (`admin/*/write_set_heure`), one line, for example :

```text
20260822.143000
```

### Raw date command (still available)

```bash
su -c 'date 080820262026.00'
```

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
├── ROADMAP-fr.md
├── TROUBLESHOOTING.md
├── PACKAGING.md
│
├── AMORCE                  aide-memoire affiche sur la box
├── deploy.sh               installeur / point d'entree cle USB
│
├── web/
│   └── index.html          panneau web (copie a la racine de la cle par INSTALL/PKG)
│
├── scripts/                tous les outils + core/ (deployes dans /data/scripts)
├── server/                 httpd 8000, control API 8080, GUI 8081, watch_usb
├── config/                 device.conf + profiles/
├── tools/                  build / check / pack / dpk (cote PC)
├── admin/                  provisioning Windows / Linux
│
├── dist/                   paquets .dpk construits + latest/
├── incoming/               fichiers temoins (triggers) - cree a l'usage
├── log/                    logs ecrits sur la cle - cree a l'usage
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
