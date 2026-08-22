
# rk322x-device-tools

> Toolkit for administering, deploying and maintaining RK322x-based Android devices via USB, ADB and HTTP.

This repository contains the scripts and tools used to administer, configure, deploy and maintain RK322x-based Android devices.

The toolkit is designed to be used directly from a USB drive connected to the device. The USB key is detected automatically: any mounted key containing `deploy.sh` is accepted (no hardcoded volume ID).

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

> **Note:** All commands are expected to run from a root shell. The scripts do not elevate privileges internally.

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

The main deployment script is located at the root of the USB drive.

### Display help

```bash
sh /mnt/media_rw/<USB_ID>/deploy.sh
```

### Install the tools on the device

Copies the scripts from the USB key to `/data/scripts`, then creates command links in `/data/bin` (including `deploy` itself):

```bash
sh /mnt/media_rw/<USB_ID>/deploy.sh INSTALL
```

The list of commands exposed in `/data/bin` is defined by `INSTALL_LIST` at the top of `deploy.sh`.

### Install from a package

The toolkit is packaged as a single `.dpk` file (a tar.gz archive readable by toybox and busybox), with a `.sha256` sidecar for integrity checks.

Build the package on the PC (from a git-bash/POSIX shell):

```bash
tools/build.sh                # full pipeline: shell checks -> pack -> verify
tools/check.sh                # static checks only (sh -n, shellcheck if present)
tools/pack.sh                 # package only
tools/dpk.sh build            # same thing, through the dpk front controller
```

Output: `dist/rk322x-tools_v<version>_<TS>.dpk` (+ `.sha256`, `BUILD-INFO.txt` inside).

Manage builds:

```bash
tools/dpk.sh list             # list dist/ packages, latest marked
tools/dpk.sh latest           # path of the latest package
tools/dpk.sh verify [f]       # archive + deploy.sh + sha256 check
```

Drop the `.dpk` at the root of the USB key (or anywhere) and install:

```bash
deploy PKG
deploy PKG /path/to/file.dpk
```

Or push and install straight over ADB:

```bash
tools/dpk.sh install                          # build output -> device, then cleanup
tools/dpk.sh install -t 192.168.50.20:5555    # explicit adb target
DPK_TARGET=192.168.50.20:5555 tools/dpk.sh install
tools/dpk.sh push                             # push only (install manually later)
```

Installation from a package goes through the same tracked path as `INSTALL` (backup, manifest, links). Full workflow documented in **[PACKAGING.md](PACKAGING.md)**.

### Show what is available on the key

Lists the `.dpk` packages on the key, marks the one `deploy PKG` would pick, compares with the installed version and shows pending triggers / log counts:

```bash
show_key
```

### Expose the USB key over HTTP

Starts the BusyBox HTTP server (port 8000) serving the key contents:

```bash
deploy EXPOSE
```

### Stop the servers

```bash
deploy STOP
```

### Restore the previous installation

`INSTALL` automatically backs up the existing `/data/scripts` before overwriting (into `/data/backup/scripts_<TS>/`). To restore the last backup:

```bash
deploy RESTORE
```

Each installation also writes a manifest into `manifests/current/install_<TS>.manifest` (previous ones are rotated to `manifests/history/`).

### Collect logs

Collects `logcat`, `dmesg`, `getprop`, `ip link`, `mount` and `ps` into the USB key:

```bash
deploy SEND_LOGS
```

Collected logs are stored in:

```text
/mnt/media_rw/<USB_ID>/log/log_<TS>/
```

---

## PC ADMIN

Provisioning scripts that run on the PC (Linux, or Windows with PowerShell) and drive the box over ADB. Each step reads the actual value, compares it against `config/device.conf`, optionally fixes it, then re-verifies.

Steps: subnet reachability of the box (optional address add on the PC), ADB connection, root access, installed version vs profile, interface/IP/gateway/DNS, Wi-Fi/Bluetooth off, clock drift (< 5 min, auto-resync from PC UTC clock), HDMI state (informational).

### Linux

Requires `adb` in PATH (root/sudo only for `--net`):

```bash
admin/linux/provision.sh                     # read-only report
admin/linux/provision.sh --fix               # apply fixes then re-validate each step
admin/linux/provision.sh --net --fix         # also add <subnet>.1/24 to the PC if missing
admin/linux/provision.sh -t 192.168.50.20:5555 check
admin/linux/provision.sh help
```

### Windows

```powershell
powershell -ExecutionPolicy Bypass -File admin\windows\provision.ps1           # check
powershell -ExecutionPolicy Bypass -File admin\windows\provision.ps1 -Fix      # corrections
powershell -ExecutionPolicy Bypass -File admin\windows\provision.ps1 -Net -Fix # + adresse PC (console admin)
```

---

## TOOLS

After `INSTALL`, the following commands are available in `/data/bin`.

### Help

Full documentation of the toolkit:

```bash
help
```

### State verification

Checks network/IP, wireless/bluetooth and HDMI state against the target configuration. Exit code is 1 if at least one check fails:

```bash
check_state
```

Sections verified:

```text
NETWORK / IP      eth0 link, IP vs expected, gateway ping, DNS
WIRELESS / BT     wifi_on, bluetooth_on, wlan0/p2p0/hci0
HDMI              fb0 blank, Rockchip sysfs nodes, resolution
SYSTEM            uptime, available RAM
```

### Selftest

Read-only check that every tool of the toolkit answers correctly:

```bash
selftest
```

### User creation inspection

Reports which user-creation methods exist on the system (`pm create-user`, `cmd user`, busybox/toybox applets), existing users, max users and sudo/sudoers presence:

```bash
inspect_user [name]
```

### Hardware inspection

Full performance report: memory, CPU frequencies/governors, Mali GPU, thermal zones, storage, display/HDMI, load/uptime and top RAM consumers:

```bash
inspect_system
```

### Services inspection

Init services with running/stopped states, package inventory (system/third-party/disabled), top RAM processes and SurfaceFlinger cost:

```bash
inspect_services
```

### Digital display inspection

Front LED/VFD display inventory: sysfs LEDs (brightness/trigger + writability), candidate `/dev` nodes, kernel drivers (`fd65x`/`tm16x`), related daemons and device-tree nodes — with the actionable ways to modify what it shows:

```bash
inspect_display
```

### Graphical interface inspection

On-screen (HDMI) capability inventory: framebuffer devices + blank state, window manager (resolution, focused activity), headless rendering proof via `screencap`, apps able to display content (launcher/browser/kodi), remote input injection (`input keyevent|tap`), boot visual customization paths (bootanimation.zip, logo partition) — plus two explicit actions:

```bash
inspect_gui                 # inventory + synthesis of what can be added on screen
inspect_gui SHOT            # screenshot -> USB key (works even with screen cut)
inspect_gui URL http://192.168.50.20:8000   # fullscreen page on the TV
```

### IR remote inspection

Input devices and IR receiver detection, `.kl` keylayout inventory with scancode-to-keycode content, expected `Vendor_Product.kl` name per device, `/system` remount status and the full key-remap procedure:

```bash
inspect_remote
```

### HDMI control

Cuts or restores the HDMI output using Rockchip sysfs nodes, with framebuffer blank fallback:

```bash
hdmi OFF
hdmi ON
hdmi STATUS
```

### Disable Wi-Fi / Bluetooth

Disables Wi-Fi service, bluetooth settings/services and brings down `wlan0`, `p2p0`, `hci0`:

```bash
disable_wireless
```

Verify afterwards with `check_state`.

### Field mode (headless operation)

One-shot preparation for unattended use: wireless + HDMI + servers + optional init services, in sequence:

```bash
field_mode OFF      # cut everything
field_mode ON       # restore display + restart watched services
field_mode STATUS   # HDMI / wireless / services summary
```

Services to stop are defined by `SERVICES_STOP` in `config/device.conf` (init.rc names, space separated; empty by default — pick them from `inspect_services`). `eth0` and ADB are kept for remote control.

### Media listing

Lists mounted media (USB/SD) with detected type:

```bash
media
```

### Maintenance

Synchronize `/data/scripts` back to the USB key:

```bash
sync_usb
```

Add a script to `/data/bin`:

```bash
add_to_bin <script>
```

Copy a file to the USB key root:

```bash
add_script_to_usb <file>
```

Rotate/prune USB key logs (active `.log` files > 512 KB, `log/exec/`, SEND_LOGS collections, manifest history):

```bash
rotate_logs          # keep 5 generations by default
rotate_logs 10       # custom keep count
```

CPU temperatures and profiles (24/7 operation):

```bash
thermal              # STATUS: temperatures, governor, frequency steps
thermal ECO          # cap max freq + powersave/conservative governor
thermal PERF         # native max freq + performance governor
```

`ECO` is the recommended profile for headless 24/7 use; the profile resets to firmware default on reboot. Temperatures and CPU state are also part of `check_state`.

---

## EXECUTION LOGS

Every tool writes one log file per execution:

```text
log/exec/<script>_<YYYYmmdd-HHMMSS>.log
```

Each log contains a header (script, start time, device, uid), the full output and a footer with the exit code.

If no USB key is present, logs fall back to:

```text
/data/local/tmp/rk322x_logs/exec/
```

Server-side persistent logs remain in `log/control_server.log`, `log/http_server.log` and `log/watch.log`.

---

## HEURE

Changing the system date requires root privileges on the RK322x device.

### Set the date and time from a file

Reads the `SET_HEURE` file at the USB key root:

```bash
setHEURE_FILE
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
080820262026.00
```

> **Note:** Run from a root shell (`su`). Scripts do not elevate privileges internally.

---

## WIFI / BLUETOOTH

The `disable_wireless` command handles:

```text
Wi-Fi
Bluetooth
wlan0
p2p0
hci0
```

### Verify the result

```bash
check_state
ip link
ps | grep -iE 'bluetooth|wpa|wifi'
```

---

## RESEAU / SERVEURS

### Static network configuration

Configures `eth0` with static IP, default route and DNS:

```bash
sh /mnt/media_rw/<USB_ID>/set_network.sh
```

Target values:

```text
IP      : 192.168.50.20
PREFIX  : 24
GATEWAY : 192.168.50.1
DNS     : 192.168.50.1 / 8.8.8.8
```

### HTTP file server

Exposes the USB key contents on port 8000 (also available via `deploy EXPOSE`):

```bash
sh /mnt/media_rw/<USB_ID>/server/start_server.sh
```

URL:

```text
http://192.168.50.20:8000/
```

### Control API

JSON control server on port 8080:

```bash
sh /mnt/media_rw/<USB_ID>/server/control_server.sh start
```

Trigger commands from a PC:

```bash
curl http://192.168.50.20:8080/api/CONFIG      # configuration active (reponse synchrone)
curl http://192.168.50.20:8080/api/HELP
curl http://192.168.50.20:8080/api/SEND_LOGS
curl http://192.168.50.20:8080/api/PURGE_LOG
curl http://192.168.50.20:8080/api/SYNC
curl http://192.168.50.20:8080/api/STATE       # check_state -> log/state_last.txt
curl http://192.168.50.20:8080/api/PANEL       # affiche l'index en plein ecran sur la TV
curl http://192.168.50.20:8080/api/HDMI_OFF    # ou HDMI_ON
curl http://192.168.50.20:8080/api/FIELD_OFF   # ou FIELD_ON (field_mode)
curl http://192.168.50.20:8080/api/REBOX       # reboot de la box
curl http://192.168.50.20:8080/api/ROTATE_LOGS # rotation/purge des logs de la cle
curl "http://192.168.50.20:8080/api/TIME_SYNC?t=20260822.171500"  # remise a l'heure (UTC, root)
curl http://192.168.50.20:8080/api/ECO_MODE    # profil CPU eco (24/7)
curl http://192.168.50.20:8080/api/PERF_MODE   # profil CPU performance
```

Each request drops a trigger file in `incoming/`. The watcher (`watch_usb.sh`, 1 s polling) executes the matching action and logs to `log/watch.log`. `STATE` writes its report to `log/state_last.txt` (fetchable over HTTP). `CONFIG` answers synchronously with the active `/data/scripts/config/device.conf` content.

The web index (`http://192.168.50.20:8000`) exposes all of these as buttons: state view, active config viewer, maintenance actions, TV display control (panel/HDMI/field mode) and reboot.

All requests are recorded with timestamps in `log/control_server.log`.

### GUI control API (port 8081)

Dedicated remote control of what is displayed on the TV (`server/gui_server.sh`, auto-started by `deploy EXPOSE`, stopped by `deploy STOP`):

```bash
curl http://192.168.50.20:8081/gui/INDEX                # panneau web plein ecran sur la TV
curl "http://192.168.50.20:8081/gui/URL?u=https://example.org"
curl "http://192.168.50.20:8081/gui/TEXT?texte%20a%20afficher"   # param t= (message plein ecran)
curl "http://192.168.50.20:8081/gui/KEY?k=KEYCODE_DPAD_RIGHT"    # injection touche
curl "http://192.168.50.20:8081/gui/TAP?x=960&y=540"             # tap ecran
curl http://192.168.50.20:8081/gui/SHOT                 # capture -> /log/gui_shots/latest.png (HTTP 8000)
```

`TEXT` renders the message as a local fullscreen page (no app install needed). `URL` accepts only `http:`/`https:`/`file:` schemes. Same optional token protection as the control API. The web index has a matching remote section: URL/text display boxes, DPAD/Home/Back buttons and an inline TV screenshot viewer.

Optional security: if the file `server/token` exists on the key, every API call must carry the token:

```text
curl "http://192.168.50.20:8080/api/HELP?token=<valeur>"
```

---

## CONFIG

Device profile stored in `config/device.conf`:

```text
DEVICE_ID=RK322X_MXQ
DEVICE_NAME=Leelbox
PROFILE=mxq
RAM_MB=2048
NETWORK=static
INTERFACE=eth0
IP=192.168.50.20
NETMASK=255.255.255.0
DEPLOY_VERSION=1
```

---

## STRUCTURE

```text
/
├── README.md
├── README.txt
├── PACKAGING.md            build + install du livrable .dpk
├── roadmap.md
│
├── deploy.sh            INSTALL | EXPOSE | STOP | SEND_LOGS
├── set_network.sh
├── setHEURE_FILE.sh
├── setHEURE_INIT.sh
├── disable_wireless.sh
├── index.html
│
├── scripts/
│   ├── help.sh
│   ├── check_state.sh
│   ├── inspect_user.sh
│   ├── inspect_system.sh
│   ├── inspect_services.sh
│   ├── hdmi.sh
│   ├── sync_usb.sh
│   ├── disable_wireless.sh
│   ├── field_mode.sh
│   ├── add_script_to_usb.sh
│   ├── add_to_bin.sh
│   ├── boxhelp.sh
│   │
│   └── core/
│       ├── runlog.sh    shared per-execution logging module
│       ├── log.sh
│       ├── media.sh
│       └── usb.sh
│
├── bin/
│   ├── HELP
│   └── MEDIA
│
├── server/
│   ├── start_server.sh
│   ├── control_server.sh
│   └── watch_usb.sh
│
├── config/
│   ├── device.conf
│   └── profiles/
│
├── log/
│   ├── exec/                 <script>_<YYYYmmdd-HHMMSS>.log
│   └── log_<TS>/             SEND_LOGS collections
│
├── incoming/                 watcher trigger files
├── history/
├── manifests/
│
├── admin/                    outils cote PC
│   ├── linux/
│   │   └── provision.sh      provisioning box : reseau, adb, controles par etape
│   └── windows/
│       └── provision.ps1     equivalent Windows PowerShell
│
└── tools/
    ├── build.sh            pipeline complet : check -> pack -> verify
    ├── check.sh            controle statique des scripts shell (sh -n)
    ├── pack.sh             construit dist/*.dpk (+ sha256)
    └── dpk.sh              build|list|latest|verify|push|install (adb)
```

---

## ROADMAP

Future development and planned improvements are tracked in:

**[roadmap.md](roadmap.md)**

---

## Project Status

This project is intended as a practical administration and deployment toolkit for RK322x-based Android devices.

The toolkit is continuously evolving alongside the deployment process.

New features, fixes and known issues should be documented through the roadmap.
