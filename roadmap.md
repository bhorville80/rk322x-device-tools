# Roadmap

> Planned improvements and future development for `rk322x-device-tools`.

This document tracks planned features, improvements and technical work for the project.

---

## Current Version

### Core administration

* [x] ADB access
* [x] Root access
* [x] Date/time management
* [x] Network inspection
* [x] USB synchronization
* [x] Script deployment
* [x] Wi-Fi / Bluetooth management
* [x] HDMI cut (headless field mode)
* [x] Logging
* [x] BusyBox HTTP file server

### Packaging

* [x] `.dpk` deliverable (`tools/pack.sh`, tar.gz readable by toybox/busybox)
* [x] Package integrity via `.sha256`
* [x] PC front controller `tools/dpk.sh` (build/list/latest/verify/push/install over ADB)
* [x] On-device install from package (`deploy PKG`)
* [x] Hardened `tools/pack.sh` (pre-flight checks, atomic output, embedded BUILD-INFO)
* [x] Build gate `tools/check.sh` (sh -n mandatory, shellcheck advisory / strict mode)
* [x] One-shot build pipeline `tools/build.sh` (check -> pack -> verify)
* [x] `.gitignore` hygiene (build + runtime artifacts)
* [ ] Signed packages
* [ ] Delta updates

---

## Short Term

### Deployment

* [x] Improve `deploy.sh` command handling
* [x] Fix `deploy.sh` root/busybox guards (source `core/config.sh` before `require_root`)
* [x] PC provisioning script with per-step verification/validation (`admin/linux/provision.sh`, `admin/windows/provision.ps1`)
* [ ] Add deployment status reporting
* [ ] Add deployment validation
* [ ] Add automatic error detection
* [ ] Improve rollback capabilities

### Configuration

* [ ] Improve device profiles
* [ ] Centralize device configuration
* [ ] Add configuration validation
* [ ] Support multiple device profiles

### Logging

* [x] Improve log formatting
* [ ] Add deployment summaries
* [ ] Add error levels
* [ ] Improve log collection
* [x] Add log rotation (`rotate_logs`, auto-run after SEND_LOGS, ROTATE_LOGS trigger)

---

## Network

* [ ] Improve network configuration scripts
* [ ] Add network diagnostics
* [ ] Add connectivity checks
* [ ] Add automatic IP detection
* [ ] Improve HTTP server management

---

## USB

* [x] Improve USB detection
* [ ] Improve USB synchronization
* [ ] Add synchronization status
* [ ] Add synchronization validation
* [ ] Improve handling of missing USB storage

---

## Wireless

* [ ] Improve Wi-Fi shutdown handling
* [ ] Improve Bluetooth shutdown handling
* [x] Add wireless state detection
* [x] Add verification after disabling interfaces

---

## Diagnostics

* [x] Add automated device diagnostics
* [x] Add hardware information collection
* [x] Add Android system information
* [x] Add storage diagnostics
* [x] Add memory diagnostics
* [x] Add process diagnostics
* [x] Digital display (front LED/VFD) inspection + modification paths
* [x] Graphical interface inspection (HDMI/fb stack, headless screencap, display-capable apps, input injection, boot visual paths, fullscreen URL action)
* [x] IR remote inspection + key remap procedure
* [ ] Add network diagnostics

---

## Manifests

* [ ] Define deployment manifests
* [ ] Add manifest validation
* [ ] Add manifest versioning
* [ ] Store deployment history
* [ ] Support reproducible deployments

---

## Automation

* [ ] Automate device initialization
* [ ] Automate time configuration
* [ ] Automate network configuration
* [ ] Automate script installation
* [ ] Automate log collection
* [ ] Add deployment health checks

---

## Long Term

Potential future features:

* [ ] Web-based administration interface
* [ ] Remote device management
* [ ] Multi-device deployment
* [ ] Centralized deployment server
* [ ] Automatic device discovery
* [ ] Deployment profiles
* [ ] Versioned releases
* [ ] Automated testing
* [ ] CI/CD integration

---

## MXQ Optimization

Investigation leads for the headless Leelbox MXQ (24/7 operation):

* [ ] Time reliability: box clock resets on power loss (1970 timestamps in `history/`) - evaluate busybox ntpd against a LAN server, or push the PC date during install
* [x] Time sync: `/api/TIME_SYNC?t=` pushes PC UTC time to the box (web panel button); `provision.sh --fix` resyncs via ADB
* [ ] CPU / thermal profile: read governors + thermal zones, define eco (frequency cap) vs perf profiles for 24/7 use
* [x] Thermal: `thermal` tool (STATUS/ECO/PERF), temperature + governor reported in `check_state`, ECO/PERF buttons on the web panel
* [x] Service slimming: `cut_services` tool (STATUS/CUT/RESTORE) - stops useless init services (perfprofd, bootanim, cameraserver, debuggerd, console), disables factory packages (stresstest, devicetest, OTA, katniss) with RAM gain measurement; customization via `SERVICES_CUT` / `PACKAGES_DISABLE` in device.conf
* [x] Server preset: `cut_services APPS` disables GMS/Play/katniss/DLNA/mediacenter/changeled/factory tests per headless purpose (launcher, UI, keyboard and user apps kept)
* [x] Front display control: `front_led` tool (STATUS/LED/TRIGGER/BLINK/ON/OFF, FD655_Demo clock daemon stop + init service detection for persistent stop)
* [x] Root execution verdict: `inspect_user` detects su manager flavor + SELinux mode; on rooted boxes the uid-0 role is already global - dedicated "root user" is not needed, remote access control is the real lever
* [x] Global inspection: `inspect_all` runs every check/inspect tool with per-tool rc summary
* [x] /system read-write toggle: `system_rw RW|RO|STATUS` (probe included, auto-ro on reboot)
* [x] ADB welcome banner: `motd` tool - MOTD-like message for interactive adb shells via /system/etc/mkshrc hook, text kept in /data/etc/motd
* [x] Bootstrap: `AMORCE` file at key root (2-step quick start) + permanent `amorce` command on box (key detection, version compare, auto-su passthrough)
* [x] deploy hardening: automatic su elevation, `deploy VERSION` diagnostic, web panel + AMORCE copied to key root on INSTALL/PKG
* [x] EXPOSE 404 fix: fallback index generated at key root when panel missing; URL printed at start
* [x] Box compatibility fixes: printf integer conversions broken on this firmware (%d -> %s), awk absent (POSIX sed/cut/tr rewrites), RAM kB shown as Mo
* [x] PC provisioning stage 8 (linux/windows): V3 tools presence + amorce link; dpk install prints installed version
* [ ] zRAM substitute: kernel exposes no zram block device yet - probe `modprobe zram`, then `zram_setup STATUS|ON|OFF` tool (~512-768 Mo compressed); swap on eMMC/USB rejected for a 24/7 box (wear/reliability)
* [ ] logd buffers: `logcat -G 256K` to trim ring buffers after cut_services validation
* [ ] lmkd thresholds: earlier kills once APPS/MAX baseline measured
* [ ] Memory pressure: zRAM presence/size, lowmemorykiller thresholds, top consumers report
* [x] eMMC wear: `life_time` estimates reported in `inspect_system` [5]; flash-write reduction still open (log rotation and manifest caps already in place)
* [ ] Supervision: auto-restart of httpd + USB watcher after crash/reboot (watchdog loop)
* [x] Web panel: active config exposure (`/api/CONFIG`) + full action set from the index (state, sync, logs, HDMI, field mode, TV display, reboot)
* [x] Dedicated GUI remote port 8081 (`server/gui_server.sh`): fullscreen URL/text display, key/tap injection, live TV screenshot
* [ ] Network depth: link speed/duplex, DNS latency, throughput test (`dd` over `nc`), internet connectivity check
* [ ] Security: restrict adb (5555) and HTTP (8000) to the LAN subnet via iptables
* [ ] Entropy: check `entropy_avail`, feed rngd if TLS stalls are observed

---

## Notes

This roadmap is intentionally flexible.

Features may be added, removed or reorganized as the project evolves and new requirements are identified.



