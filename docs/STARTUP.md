# STARTUP - From-scratch installation and bring-up procedure

> Full deployment of a stock RK322X box up to full autonomy.
> Reference dpk: latest build in dist/. Each phase lists exact commands
> and EXPECTED results. Do not chain phases past a failure.

---

## Phase 0 - Preparation

### On the PC
Copy to USB key root (FAT32):
```
rk322x-tools_v17_<BUILD>.dpk          (+ .sha256)
deploy.sh
```

### On the TV (remote control)
1. Settings -> About -> tap "Build number" 7x -> developer options
2. Enable **USB debugging**
3. Settings -> Network -> Ethernet -> **Static**:
   IP `192.168.50.20` / `/24` / gateway `192.168.50.1` / DNS `8.8.8.8`

### PC <-> box connection
```bash
adb kill-server && adb devices        # box must be listed
adb shell ; su
ls /mnt/media_rw/*/INSTALLER.sh       # key is visible
```

---

## Phase A - RAM baseline BEFORE installing (virgin box)

```bash
adb push scripts\rampre.sh /data/local/tmp/
adb shell ; su
sh /data/local/tmp/rampre.sh 120      # 120 s sampling
```

Expected: `rampre_<TS>.txt` on key/sdcard with MemAvailable avg/min/max,
top PSS start/end, lmk pressure count. This is the baseline used to
quantify every optimization benefit later.

---

## Phase 1 - Install + hook + apply

```bash
sh /mnt/media_rw/*/INSTALLER.sh
```

Interactive with validation gates:
- [0] detected package presentation (BUILD-INFO)
- 1/3 deploy PKG   -> tools + web panel + /data/bin links
- config highlights review -> optional interactive editor (`config`)
- 2/3 boot INSTALL -> persistent launcher (tried in order: init .rc,
  init.d if firmware supports it, install-recovery.sh block)
- 3/3 boot TEST    -> immediate application (memory/network/clock/web)
- bonus aliases    -> uid-2000 shortcuts (help, manage, nreg...)

Expected: `[5] Startup... [ OK ]`, web stack running, TERMINE banner.

---

## Phase 2 - Configuration & verification

```bash
config            # numbered interactive review
config CHECK      # = conf_check -> "[ OK ] configuration compliant"
exit ; exit
ping 192.168.50.20
```

Keys to eyeball: `IP/GATEWAY`, `BOOT_SET_NETWORK=1`, `BOOT_TIME_SYNC=1`,
`BOOT_EXPOSE=1`, `WEB_RUN=0` (panel console off by default).

---

## Phase 2bis - Optimization & performance

A) CPU thermal profile (24/7 -> ECO)
```bash
thermal STATUS
thermal ECO
```

B) Memory: optimize then hold test
```bash
mem_tune STATUS
mem_tune OPTIMIZE     # swappiness + LMK early + logd
stress_ram            # controlled ~30 s RAM pressure, kills monitored
vitals                # post-pressure reading
```
Expected: clean LMK kills during stress, recovery without reboot.

C) Services/packages slimming
```bash
cut_services STATUS
cut_services CUT      # frees ~120-150 MB PSS on this box
```

D) Headless (if TV only used for panel): `field_mode OFF` then `hdmi OFF`.

E) Immediate counter-check
```bash
check_state ; conf_check | tail -5 ; nreg memoire ; manage service
```

Note: BOOT_MEM_TUNE/BOOT_CUT_SERVICES reapply B/C at every boot.

---

## Phase 2ter - Instrumented deployment (ramstep)

Isolates each optimization benefit with before/after RAM measures and a
30 s observation window:

```bash
ramstep 30
```

Steps: mem_tune OPTIMIZE -> thermal ECO -> cut_services CUT ->
network+clock -> STOP+EXPOSE (server startup cost isolated).
Timeline with per-step gains: `log/ram_steps_<TS>.txt`.
Single-command wrap: `ramstep ONE "<label>" <cmd...>`.

---

## Phase 3 - Re-check (non-regression)

```bash
nreg                  # 10 themes, PASS without FAIL
selftest | tail -3    # ~50 PASS / 0 FAIL
```

---

## Phase 4 - Inspection

```bash
inspect_all LIST      # heart/exploration classes with reason+expectations
inspect_all           # heart analyses (~1 min)
device_info           # chip inventory by function
hw_report SAVE        # FULL report -> log/hardware_latest.txt (chip research)
```

---

## Phase 5 - Server

```bash
manage                # services + web + ports overview
manage web            # 3 ports LISTENING, panel served, api answering
deploy STATUS         # missing: 0
show_key              # key package vs installed
```

---

## Phase 6 - IHM tests (PC browser) - see docs/IHM.md

| Page | Test | Expected |
|---|---|---|
| Accueil | badges, box clock, versions | 3 green, real clock |
| Commandes | CHECK STATE, SYNC HORLOGE | instant answer |
| Cle | hardware report + download + dpk upload | ~10 s gen, direct download |
| Metriques | VITALS | fresh values |
| Telecommande | TV mirror + keys + click=TAP | ~2 s refresh |
| Infos | identity/material/config/manifest | everything filled |

Remote console needs `WEB_RUN=1` AND active token.

---

## Phase 7 - THE final gate: autonomous reboot

```bash
reboot
```

Wait **4 to 6 minutes** without touching anything. Then, no manual action:
1. `http://192.168.50.20:8000/` -> panel up, green badges
2. `date` -> real clock
3. latest `log/exec/boot_*.log` -> complete sequence ending with
   `[boot] panel OK (8000)` and `fin/rc` footer

Phase 7 passing = "zero manual action" goal ACHIEVED.

---

## Recovery

| Symptom | Remedy |
|---|---|
| Box unreachable over network | USB adb (PC->box cable) then `set_network` |
| IP lost after an old version | simple reboot; or static via TV settings |
| Hook not installed (rc/init.d refused) | install-recovery.sh fallback is automatic |
| Servers dead after a manipulation | `su -c 'deploy STOP ; deploy EXPOSE'` |
| Everything broken | MXQ factory reset then this procedure from Phase 0 |

The USB key is the SOURCE OF TRUTH: it alone can redeploy everything.
