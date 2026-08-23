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

Under `su`, both **uid and gid are 0**: `uid=0(root) gid=0(root) groups=...`.

### Root detected as missing even under `su` (`privileges root requis`)

**Observed:** after `su -c "sh deploy.sh INSTALL"`, the script still reports
`[ERREUR] privileges root requis`, although plain `id` shows `uid=0(root) gid=0(root)`.

**Diagnosis:** old Android toolbox builds (common on RK322x boxes, Android 4.4/5.1)
do not support the `-u` option: `id -u` fails and outputs nothing, so any
`[ "$(id -u)" != "0" ]` test evaluates as "not root".

**Solution (applied in the codebase):** every root check now uses a robust
`is_root()` helper that first tries `id -u`, then falls back to parsing the
raw `id` output:

```sh
is_root()
{
    case "$(id -u 2>/dev/null)" in
        0) return 0 ;;
    esac
    case "$(id 2>/dev/null)" in
        "uid=0("*) return 0 ;;
    esac
    return 1
}
```

If a very old copy of the scripts is still installed on the box
(`/data/scripts/core/config.sh` without `is_root`), re-run INSTALL from an
up-to-date key/package.

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

### `tmp-mksh: ... No such file or directory` / `syntax error: 'do' unexpected`

Signature of **CRLF line endings** (Windows) corrupting the shebang:
the kernel tries to execute `/system/bin/sh\r`, which does not exist.

* Fixed permanently: `.gitattributes` forces LF (`eol=lf`) for everything
  deployed to the box; `tools/pack.sh` refuses a build containing `\r`;
  the pre-commit hook converts CRLF->LF automatically.
* If an old copy still shows the symptom: rebuild the key/package from
  a clean checkout and re-run INSTALL.

Reminder: `/mnt/media_rw/*` is mounted **noexec** - always run scripts
via `sh <path>`, never `./script` (Permission denied is expected there).

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

## SD CARD / BOOT BLOCKED

### Box does not boot when the SD card is inserted at power-on

**Symptômes observés :**

```text
LED rouge figée, logo bloqué, ou boot très long avec carte SD insérée.
Sans la carte : la box démarre normalement sur l'eMMC (Android).
```

**Causes connues sur RK322x :**

1. Le BootROM/loader essaie de démarrer sur la SD avant l'eMMC
   (carte avec signature de boot, MBR exotique, ou ordre de boot du loader).
2. Le driver mmc des noyaux 3.10/4.4 se bloque sur certaines cartes
   (SDXC / UHS-I rapides) pendant l'énumération.
3. Android (vold) voit la carte mais ne la monte jamais
   (stockage adopté résiduel, format non supporté).

**Procédure d'investigation :**

```bash
# 0) après un boot bloqué puis redémarré SANS la carte :
deploy SEND_LOGS          # capture pstore/last_kmsg + logs sur la clé
admin/*/logpull           # récupération vers le PC sans débrancher la clé

# 1) état actuel (avec carte insérée à chaud si possible) :
sd_inspect                # enumeration mmc, montage/vold, traces pstore
sd_inspect DMESG          # messages noyau live mmc/sdhci
```

Interprétation :

```text
Carte absente de l'énumération + blocage au logo  -> stade loader (cause 1)
Erreurs timeout/crc dans le pstore                -> driver/carte (cause 2)
Carte vue par le noyau mais rien de monté         -> vold/format (cause 3)
```

**Contournements / solutions :**

| Cause | Solution |
|---|---|
| Loader | Formater la carte en **FAT32, MBR, une seule partition primaire, sans flag boot** ; sinon reflasher le loader via RKDevTool (PC, câble OTG, point reset) |
| Driver/carte | Essayer une autre carte : SDHC plutôt que SDXC, classe 10 sans UHS, marque connue |
| vold/format | Format portable FAT32 (pas de "stockage interne") ; vérifier `sd_inspect` section adoption |

**Objectif :** pouvoir laisser la carte insérée au démarrage et l'utiliser comme stockage. La voie logicielle dépend de la cause identifiée par `sd_inspect` ; documenter ici le résultat obtenu.

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
