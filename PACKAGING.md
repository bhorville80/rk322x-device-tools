# Packaging

> How to build and install the `.dpk` deliverable for `rk322x-device-tools` (version 3).

A `.dpk` package is a single `tar.gz` archive containing the full toolkit. It is readable by both toybox and busybox on the device, so it can be installed without any external dependency.

---

## Deliverable

Each build produces two files in `dist/` plus a copy of the newest one in `dist/latest/`:

```text
dist/rk322x-tools_v<version>_<BUILD_ID>.dpk          archive tar.gz du toolkit
dist/rk322x-tools_v<version>_<BUILD_ID>.dpk.sha256   empreinte de controle
dist/latest/<même nom>.dpk (+ .sha256)               dernier build seul
dist/rk322x-cle_v<version>_<BUILD_ID>.zip            cle USB prete a l'emploi
```

- `<version>` comes from `DEPLOY_VERSION` in `config/device.conf` (currently `3`).
- `<BUILD_ID>` is the build timestamp at format **YY.MM.ddHH.MMss** (ex : `26.08.2221.4320`) - fixed-width fields keep lexicographic sort chronological.
- `dist/latest/` is overwritten on every build; `dist/` root keeps the full history.
- `.bak` files are excluded from the archive.
- A failed build leaves nothing behind in `dist/` (no partial `.dpk`).

### Zip cle USB (`tools/usb_zip.sh`)

Assemble apres chaque build un zip a dezipper directement a la racine de la cle :

```text
AMORCE  deploy.sh  <dernier>.dpk (+ .sha256)  admin/{linux,windows}/
```

Le dossier `admin/` sert au PC (Windows ou Linux) avant branchement de la box ; `admin/*/set_box_time` force la remise a l'heure de la box depuis le PC via adb (set_time SET, fallback date -u -s) ; le panneau web n'est pas inclus car il voyage dans le `.dpk` et est copie a la racine de la cle par INSTALL/PKG.

```bash
tools/usb_zip.sh               # construit dist/rk322x-cle_v<version>_<BUILD_ID>.zip
```

### Archive contents

```text
AMORCE                 bootstrap quick-start (cat /mnt/media_rw/*/AMORCE)
deploy.sh              INSTALL | PKG | RESTORE | EXPOSE | STOP | SEND_LOGS | VERSION
web/                   panneau web : index.html copie a la racine de la cle (INSTALL/PKG)
scripts/               all tools + core modules: cut_services, system_rw,
                       front_led, inspect_all, amorce, motd, net_diag,
                       vitals, disable_wireless, set_network, set_time (AUTO/FILE/RTC/INIT/SET)
server/                HTTP server + control API + GUI remote + ssh_server (optional)
config/device.conf     device profile
BUILD-INFO.txt         build metadata (version, build_id YY.MM.ddHH.MMss, date, git commit + state)
```

---

## Build

From a git-bash / POSIX shell, at the repository root:

```bash
tools/build.sh                # full pipeline: lint (sh -n) -> pack -> verify
tools/check.sh                # static checks only (sh -n, shellcheck if present)
tools/pack.sh                 # package only
tools/dpk.sh build            # same thing, through the dpk front controller
```

A failed check aborts the pipeline before anything is written to `dist/`.

Manage builds with `tools/dpk.sh`:

```bash
tools/dpk.sh list             # list dist/ packages, mark the latest one
tools/dpk.sh latest           # print the path of the latest package
tools/dpk.sh verify [f]       # check archive readability, deploy.sh presence, sha256
```

If no file argument is given, `verify`, `push` and `install` pick the latest package in `dist/`.

---

## Install

Two ways to get the package onto the device.

### Option A - USB key

1. Copy the `.dpk` at the root of the USB key.
2. On the device (root shell), run:

```bash
deploy PKG                    # picks the newest .dpk at the key root
deploy PKG /path/to/file.dpk  # explicit path
```

Installation goes through the same tracked path as `INSTALL`: backup of `/data/scripts`, manifest written to the key, command links refreshed in `/data/bin`.

### Option B - ADB from the PC

Requires `adb` in `PATH` and a reachable device (USB debugging or `adb connect <ip>:5555`, default device IP: `192.168.50.20:5555`).

```bash
tools/dpk.sh push                     # push .dpk + deploy.sh to /data/local/tmp
tools/dpk.sh install                  # push then remote-install (deploy PKG), cleanup after
tools/dpk.sh install -t 192.168.50.20:5555   # explicit adb target
DPK_TARGET=192.168.50.20:5555 tools/dpk.sh install   # target via environment
tools/dpk.sh install path/to/file.dpk # explicit package instead of latest
```

What `install` does:

1. Verifies the package (archive + sha256).
2. Checks the adb device (auto-retries `adb connect` for `-t` targets).
3. Pushes the `.dpk` and a copy of `deploy.sh` to `/data/local/tmp`.
4. Runs `su -c 'sh /data/local/tmp/deploy.sh PKG /data/local/tmp/<pkg>'` remotely.
5. Removes the pushed files on success.

This works even when nothing is installed yet on the box, since `deploy.sh` is pushed along with the package.

---

## Verify an installation

On the device:

```bash
cat /data/scripts/VERSION     # version + install date + source
show_key                      # compares key packages vs installed version
selftest                      # every tool answers
check_state                   # network / wireless / HDMI target state
```

Integrity check on the PC (or on-device, next to the file):

```bash
cd dist && sha256sum -c rk322x-tools_v2_<TS>.dpk.sha256
# ou depuis la racine du depot
tools/dpk.sh verify
```

---

## Rollback

Every install (USB or package) backs up the previous `/data/scripts` into `/data/backup/scripts_<TS>/`. To restore:

```bash
deploy RESTORE
```

---

## Versioning

Bump `DEPLOY_VERSION` in `config/device.conf` before packaging a release:

```text
DEPLOY_VERSION=2
```

The version ends up in the package filename, in `/data/scripts/VERSION` after install and in the install manifests on the USB key (`manifests/current/install_<TS>.manifest`).

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `aucun device adb` | Run `adb connect 192.168.50.20:5555` first, or pass `-t`. |
| `archive illisible` | Rebuild: the transfer was truncated (`tools/dpk.sh verify`). |
| `sha256 differents` | Stale/corrupted copy; rebuild and re-transfer. |
| `aucun .dpk dans dist/` | Build first: `tools/dpk.sh build`. |
| `privileges root requis` | Install must run from a root shell (`su`) on the device. |
| Old commands still linked | Re-run `deploy PKG`; links are rebuilt by `link_bin`. |

See also: [README.txt](README.txt) (full usage), [roadmap.md](roadmap.md) (planned work).
