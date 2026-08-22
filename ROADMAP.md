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
* [x] Layout cleanup: every tool lives in `scripts/` - repo root keeps only `deploy.sh` (+ index.html / AMORCE); duplicate `disable_wireless` removed; `set_network` / `set_time` / `setHEURE_*` now deployed to `/data/scripts` with `/data/bin` links
* [x] Add deployment status reporting (`deploy STATUS`: tools present/missing, bin links, backups, manifest, key version comparison, live servers)
* [x] Add deployment validation (end of INSTALL/PKG: `sh -n` on every deployed script + `/data/bin` links check; result traced in `VERSION`, rc=1 on failure)
* [x] Add automatic error detection (validation fails loudly and propagates through dpk install)
* [x] Add deployment cleanup (`deploy CLEAN [DRY]`: keeps 3 backups + 10 manifests + 11 gui_shots, purges dpk staging/tmp residuals/tombstones, rotates exec logs)
* [ ] Improve rollback capabilities

### Configuration

* [x] Centralize device configuration (`config/device.conf` single source, consumed everywhere via `core/config.sh`; network target completed: GATEWAY/DNS/PREFIX/ADB_PORT + hardware reference facts block)
* [x] Improve device profiles (enriched key set with documented sections; `PROFILE=` key)
* [x] Support multiple device profiles (`config/profiles/<name>.conf` overlay - values there take priority over the base profile; secrets in a third layer `config/secrets.conf`)
* [x] Add configuration validation (`conf_check`: required keys, IP/netmask/prefix/port formats, enum values NETWORK/SSH_MODE/WIRELESS_AIRPLANE, overlay presence, unknown-key warnings; rc=1 on error, wired into selftest)
* [x] Secrets hygiene: passwords live only in `config/secrets.conf` (gitignored, excluded from `.dpk` packaging and USB sync); web panel exposes config summary + live `conf_check` (`CONF_CHECK` API)

### Logging

* [x] Improve log formatting
* [ ] Add deployment summaries
* [ ] Add error levels
* [ ] Improve log collection
* [x] Add log rotation (`rotate_logs`, auto-run after SEND_LOGS, ROTATE_LOGS trigger)
* [x] Tool execution state report (`run_state`: launched vs never-launched per installed script, derived from `log/exec` traces - count, last timestamp, last rc, failures)

---

## Network

* [x] Improve network configuration scripts (`set_network` driven by device.conf GATEWAY/DNS; `check_state` suggests remediation on WARN)
* [x] Add network diagnostics (`net_diag`: link speed/duplex from sysfs, MAC, routes, DNS servers)
* [x] Add connectivity checks (ping gateway / DNS / 8.8.8.8 / domain resolution, per-check verdicts + summary)
* [x] Add automatic IP detection (`net_diag` scans all interfaces, flags subnet mismatches vs profile)
* [x] Improve HTTP server management (`net_diag PORTS` labels listeners 8000/8080/8081/5555/2222; EXPOSE prints URL; STOP unified via pidfiles)

---

## USB

* [x] Improve USB detection
* [x] Improve USB synchronization (`sync_usb` post-copy validation pass, size report, explicit key path argument)
* [x] Add synchronization status (`sync_usb STATUS`: identical/different/missing file diff without copying)
* [x] Add synchronization validation (byte-to-byte `cmp` verification after copy, ecarts reported)
* [x] Improve handling of missing USB storage (explicit error + hint, multi-key safe pick deploy.sh+LOST.DIR first)

---

## Wireless

* [x] Improve Wi-Fi shutdown handling (`disable_wireless OFF`: svc + persistent `wifi_on=0`, residual init services scan, interface down with retry, rfkill best-effort, optional airplane mode via `WIRELESS_AIRPLANE`)
* [x] Improve Bluetooth shutdown handling (persistent `bluetooth_on=0`, running bt/wpa/hci service detection and stop, hci0 verification)
* [x] Add wireless state detection
* [x] Add verification after disabling interfaces (per-interface verify with 2 attempts, rc reflects residual radios)
* [x] Root helper scripts now installed to /data/scripts (disable_wireless/set_* were key-only before - field_mode ON/OFF failed when run installed)

---

## Diagnostics

* [x] Automated device diagnostics suite: `inspect_all` (global) + `net_diag` (network) + `sys_diag` (clock-loss detection, memory/lmkd pressure, entropy, eMMC write speed, security posture: adb/token/ssh/wireless)
* [ ] Add network-specific deep diagnostics (packet capture, route tracking) if field issues appear
* [x] Add hardware information collection
* [x] Add Android system information
* [x] Add storage diagnostics
* [x] Add memory diagnostics
* [x] Add process diagnostics
* [x] Digital display (front LED/VFD) inspection + modification paths
* [x] Graphical interface inspection (HDMI/fb stack, headless screencap, display-capable apps, input injection, boot visual paths, fullscreen URL action)
* [x] IR remote inspection + key remap procedure
* [x] Network diagnostics (`net_diag`: link speed/duplex, addresses auto-detect, routes, DNS, connectivity, ports, throughput; deep packet capture if field issues appear)
* [x] System health diagnostics (`sys_diag`: clock-loss 1970 detection, memory pressure + lmkd, entropy, eMMC write speed, security posture)
* [x] Chip-level hardware inventory (`device_info`: dynamic sysfs/procfs/getprop/dmesg detection sorted by function - SOC/CPU, RAM/DDR, GPU, eMMC, eth/wireless chips, USB, audio, HDMI, inputs/IR, regulators/RTC, thermal - with init services grouped per function)

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

* [x] Time reliability: `sys_diag` detects the 1970 clock-reset condition; sync paths exist (`/api/TIME_SYNC`, `provision --fix`, `setHEURE`) - busybox ntpd against a LAN server stays open for unattended sites
* [x] Time sync: `/api/TIME_SYNC?t=` pushes PC UTC time to the box (web panel button); `provision.sh --fix` resyncs via ADB
* [x] CPU / thermal profile: `thermal` tool (STATUS/ECO/PERF) + governors reported in `check_state` and `inspect_all`
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
* [x] zRAM substitute: `mem_tune OPTIMIZE` probes `modprobe zram` then activates swap compresse (MEM_ZRAM_MB, prio 10) + swappiness adapte; swap on eMMC/USB rejected for a 24/7 box (wear/reliability); settings volatile - re-run after reboot
* [x] logd buffers: `mem_tune` trims ring buffers (`logcat -G` + persist.logd.size, LOGD_SIZE_KB in device.conf) to limit eMMC wear after cut_services validation
* [ ] lmkd thresholds: earlier kills via MEM_LMK_EARLY=1 implemented in `mem_tune`; tune the factor once APPS/MAX baseline measured
* [x] Memory pressure report: `sys_diag` (MemAvailable %, zRAM presence, lmkd minfree/props) + top consumers in `inspect_system` / `inspect_services`
* [x] eMMC wear: `life_time` estimates reported in `inspect_system` [5]; flash-write reduction still open (log rotation and manifest caps already in place)
* [ ] Supervision: auto-restart of httpd + USB watcher after crash/reboot (watchdog loop)
* [x] Web panel: active config exposure (`/api/CONFIG`) + full action set from the index (state, sync, logs, HDMI, field mode, TV display, reboot)
* [x] Dedicated GUI remote port 8081 (`server/gui_server.sh`): fullscreen URL/text display, key/tap injection, live TV screenshot
* [x] Network depth: `net_diag` - link speed/duplex, DNS latency (ping), internet connectivity checks, throughput test sender-side (`dd` over `nc`, receiver command printed)
* [ ] Security: restrict adb (5555) and HTTP (8000) to the LAN subnet via iptables
* [x] Entropy: `entropy_avail` reported in `sys_diag` + `inspect_system` (rngd feed only if TLS stalls observed in the field)

---

## Notes

This roadmap is intentionally flexible.

Features may be added, removed or reorganized as the project evolves and new requirements are identified.



