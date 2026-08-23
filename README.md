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

> **Note :** `deploy`, `amorce` et la plupart des outils sensibles s'elevent automatiquement via `su` pour les actions privilegiees - plus besoin de taper `su` d'abord.

---

## DEMARRAGE RAPIDE

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

### Panneau web (EXPOSE)

`deploy EXPOSE` (ou `amorce EXPOSE`) lance toute la pile : HTTP 8000,
control API 8080, GUI TV 8081 et le watcher USB.

Six pages sur `http://<ip-box>:8000` :

* **index.html** - accueil/bilan : versions installee vs cle, verdict
  conf_check, dernier etat reseau
* **cle.html** - presentation de la cle, catalogue des outils,
  **televersement** de fichiers (.dpk/.sha256/.txt/.log, max 20 Mo,
  sha256 verifie par la box) + **APPLIQUER LE DPK** (extraction tar.gz
  sur la cle = mise a jour sans la debrancher ; puis deploy INSTALL +
  REBOX) + liens de telechargement directs (rapport materiel, bilans,
  manifest, config, navigation log/)
* **commandes.html** - commandes minimales + boutons de recette par phase
  (P1..P7, global, RETOUR LOGS, GENERER MANIFEST a 7/7) + rapport
  materiel complet telechargeable (hw_report)
* **metriques.html** - vitals / check state / conf check
* **telecommande.html** - ecran TV en miroir (rafraichissement captures
  screencap, clic = TAP), touches (dpad/back/home/vol/power), TEXT/URL
  plein ecran, console distante (API RUN : une ligne shell, bornee
  15 s/8 Ko, requiert WEB_RUN=1 dans device.conf ET token actif)
* **infos.html** - donnees statiques : identite systeme + versions,
  rapport materiel complet (generation + consultation), device.conf
  actif, manifest recette certifie

### Recette

```bash
recette                 # sequence complete + "CLE PRETE POUR ANALYSE RETOUR"
recette P5              # ou phase par phase ; etat : log/recette_phases.txt
recette CONFIG          # sections thematiques : CONFIG (P3+P4), DIAG (P5+P6)
recette HELP            # liste des phases/sections launchables
```

A la fin : manifest certifie (phases + conf_check + sha256 des scripts
deployes), snapshot device/allconf, diff de derive vs precedent -
dans `manifests/recette/`. Fiche de recette imprimable dans le livrable :
`docs/RECETTE.md`.

### Outils

| Outil | Role |
|---|---|
| `menu [sujet [action]]` | dispatcher par sujet : install recette optim inspect diag logs serveur cle ; vue d'ensemble sans argument, aide par sujet, lancement par action (ex : `menu optim mem`, `menu recette tout`) |
| `boot INSTALL/REMOVE/STATUS/TEST` | persistance au boot : hook `/system/etc/init/*.rc` (repli install-recovery.sh), actions `BOOT_*` du device.conf (mem_tune, cut_services, pile web) |
| `reboot [s]/CANCEL/STATUS/RECOVERY/BOOTLOADER` | redemarrage controle (immediat, differe annulable, recovery/fastboot) |
| `remote_map STATUS/DEVICES/LIST/LEARN/MAP/RESET` | personnalisation telecommande IR : remap scancode->KEYCODE dans le .kl cible (backup auto, effectif au reboot) |
| `front_digit PROBE/SHOW/CLOCK/ROTATE [s]/RAW/STOP` | afficheur 4 digits custom (FD655) : texte 7-seg, horloge HH.MM, rotation toutes les N s (TIME IP RAM UP) ; format trame auto-detecte par PROBE |
| `stress_ram [mo] [s]/STATUS/CLEAN` | provocation RAM surveillee : remplissage tmpfs, kills lmkd, recuperation |
| `net_watch STATUS/WATCH/DAEMON/LOGSCAN/BAN` | surveillance reseau temps reel zero-dependance : connexions, alertes scan/bruteforce, blocage iptables |
| `capture STATUS/START/LIST/CLEAN` | captures pcap via tcpdump depose (non fourni), rotation 80 Mo, analyse PC |
| `crowdsec STATUS/GUIDE/NATIVE` | IDS comportemental : faisabilite proot vs mode natif net_watch |
| `investigate DISPLAY/REMOTE/ALL` | enquetes forensiques : processus ecrivant sur /dev/fd655_dev (+strace), noyau IR/getevent, rapports sauvegardes |
| `cut_services STATUS/CUT [SAFE\|FULL]/APPS [MAX]/RESTORE` | allègement services init + paquets usine, gain RAM mesure |
| `system_rw RW/RO/STATUS` | bascule /system lecture-ecriture |
| `front_led STATUS/LED/TRIGGER/BLINK/OFF/DEMO STOP` | afficheur frontal (leds sysfs + horloge FD655) |
| `net_diag STATUS/PORTS/PING/THROUGHPUT` | diagnostics reseau |
| `vitals STATUS/WATCH [N] [S]` | signes vitaux : temperatures, CPU/charge, RAM, usure eMMC, lien reseau, alimentation |
| `sys_diag` | sante systeme : horloge 1970, lmkd, entropie, eMMC, securite |
| `sd_inspect STATUS/DMESG` | carte SD : enumeration mmc, montage/vold, traces du boot bloque |
| `device_info` | inventaire puces/materiel trie par fonctionnalite + services par fonction |
| `thermal STATUS/ECO/PERF` | profil CPU/thermique (eco conseille en 24/7) |
| `conf_check` | validation config (+profils+secrets) et etat d'application des optimisations |
| `mem_tune STATUS/OPTIMIZE/RESTORE` | memoire : zram (degrade propre si backend kernel casse), swap disque optionnel (`MEM_SWAP_DEV` partition SD brute / `MEM_SWAP_FILE` fichier cle, prio 1), swappiness, lmk, buffers logd |
| `run_state` | outils lances / jamais lances / echecs (analyse log/exec) |
| `recette [P1..P7/RETOUR/MANIFEST/CONFIG/DIAG]` | recette bout-en-bout, phases ou sections thematiques, manifest certifie ; liste : `recette HELP` |
| `nreg [theme]` | non-regression executable (10 themes, miroir docs/NON-REG.md) : deploiement, outils, configuration, memoire, boot, reseau, wifi, diagnostic, sd, traces ; un seul theme possible (`nreg 4`, `nreg mem`) ; bilan PASS/FAIL |
| `config [SHOW/GET/SET/CHECK]` | configuration interactive : page complete numerotee puis modification par numero avec validation par type (IP/port/booleen/enum) ; `config SET CLE val` pour scripts |
| `manage [service/web/ports]` | etat & gestion centralises : services (wifi/bt/ssh/front_digit), sante pile web (ports 8000/8080/8081, panneau, api, token), actions (`manage web restart`, `manage service wifi-off`) ; delegue aux outils dedies sans les dupliquer |
| `hw_report [SAVE]` | rapport materiel COMPLET pour recherche web des puces (datasheets/ROM) : device_info + getprop filtre + noyau (modules/dmesg) + bus i2c/spi/input/partitions ; `SAVE` ecrit `log/hardware_latest.txt` sur la cle, telechargeable via le panneau (bouton page Commandes ou http://ip:8000/log/hardware_latest.txt) |
| `aliases [INSTALL/REMOVE/STATUS/LIST]` | raccourcis pour l'utilisateur 2000 (adb shell) : depose un wrapper `/system/bin/<outil>` par outil du depot -> taper `help`, `manage`, `nreg`, `recette`... depuis adb shell execute `su -c sh /data/scripts/<outil>.sh` ; binaire systeme existant jamais ecrase (collisions signalees) ; persistant aux reboots |
| `inspect_all [FORCE]` | rapport standard : coeur de verification (10 outils) + synthese rc ; analyses one-shot exclues (gui/display/remote/user) ; `LIST` = classification avec raison/attentes, `FORCE` = tout apres presentation + confirmation (`FORCE YES` scriptable) |
| `motd ON/SET/DEFAULT` | banniere adb (cadre ASCII) : URL panneau web, etat ports 8000/8080/8081, ip/ram/boot/recette ; activation manuelle uniquement (`ON`, jamais automatique) |
| `ssh_server START/STOP/STATUS` | SSH dropbear optionnel - binaire non fourni, jamais lance auto |
| `deploy VERSION/STATUS/CLEAN [DRY]` | versions, etat deploiement, assainissement |
| `deploy TOKEN ON/OFF/<valeur>/STATUS` | protection optionnelle API 8080 + GUI 8081 par secret partage (`server/token`) ; panneau : saisie unique par navigateur |

| `sync_usb` `disable_wireless` `media` `check_state` `inspect_*` `hdmi` `field_mode` `show_key` `rotate_logs` `set_network` `set_time` | outils d'origine (v1-v2) - documentes dans les sections ADB/Reseau/Wireless ci-dessus |

### Nouveautes v13..v17

* **Dispatcher `menu`** : un point d'entree par sujet (install, recette,
  optim, inspect, diag, logs, serveur, cle) avec etat rapide et aides.
* **Deploy fiabilise** : `INSTALL` bascule tout seul sur le `.dpk` quand
  la cle est au layout zip (deploy.sh + paquet, sans `scripts/`) ;
  le "dernier .dpk" est trie sur le BUILD_ID (le lexical plaçait v9
  apres v13) cote box comme cote PC.
* **Recette P7 honnete** : detection de ports en cascade netstat ->
  /proc/net/tcp -> sonde wget fonctionnelle (les ports fantomes 0/3
  des vieux firmwares sont elimines).
* **mem_tune durci + swap disque** : backend lz4 casse -> WARN +
  marqueur `zram_unavailable` au lieu d'un echec de phase ; nouveau
  swap sur espace physique (`MEM_SWAP_DEV`/`MEM_SWAP_FILE/MEM_SWAP_MB`,
  desactive par defaut, usure flash a considerer).

### Nouveautes v5..v12

* **Persistance** : `boot INSTALL` pose un hook `/system/etc/init/*.rc`
  (repli install-recovery) qui relance au boot mem_tune, cut_services,
  la pile web et l'horloge frontale (`BOOT_*` du device.conf).
  `reboot [s]/RECOVERY/BOOTLOADER` complete.
* **Display frontal** : `front_digit PROBE` identifie le format de trame
  FD655 puis SHOW/CLOCK/ROTATE (texte 7-seg, horloge HH.MM, rotation 5 s).
* **Telecommande IR** : `remote_map LEARN/MAP/RESET` remap les touches
  dans le .kl cible (backup auto, effectif au reboot).
* **Reseau / securite** : `net_watch` (surveillance connexions, alertes
  scan/bruteforce, BAN iptables), `capture` (pcap si tcpdump depose),
  `crowdsec` (verdict natif/proot + guide).
* **Diagnostic** : `investigate DISPLAY/REMOTE/ALL` (qui ecrit quoi ou),
  `stress_ram` (provocation RAM surveillee, kills lmkd, recuperation).

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
├── docs/                   RECETTE.md + PJ-releve-energie.csv (livrable)
│
├── web/
│   ├── index.html          accueil/bilan (copie racine cle par INSTALL/PKG)
│   ├── cle.html            presentation cle + catalogue outils
│   ├── commandes.html      commandes + recette par phases + manifest
│   └── metriques.html      vitals / state / conf check
│
├── scripts/                tous les outils + core/ (deployes dans /data/scripts)
├── server/                 httpd 8000, control API 8080, GUI 8081, watch_usb
├── config/                 device.conf + profiles/ + secrets.conf (jamais livre)
├── tools/                  build / check / pack / dpk + hooks git (cote PC)
├── admin/                  provisioning Windows / Linux
│
├── dist/                   paquets .dpk construits + latest/
├── incoming/               fichiers temoins (triggers) - cree a l'usage
├── log/                    logs ecrits sur la cle - cree a l'usage
│
└── manifests/
    ├── history/
    ├── current/
    └── recette/            manifest certifie + allconf + diff derive
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
