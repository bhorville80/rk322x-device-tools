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
* [ ] Service slimming: identify stoppable init services (bootanim, media scanner, OTA...) and fill `SERVICES_STOP`, measure RAM/CPU gains
* [ ] Memory pressure: zRAM presence/size, lowmemorykiller thresholds, top consumers report
* [ ] eMMC wear: read `life_time` estimates, reduce flash writes (log rotation, fewer manifest writes)
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



