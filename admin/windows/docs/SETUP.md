# SETUP - PC preparation and first install from a factory-reset MXQ

> Bench procedure: prepare the PC once, prepare the key, wake the box,
> then follow docs/STARTUP.md phase by phase. Do not chain phases past
> a failure. Hardware reference: Leelbox MXQ, RK322X, Android 7.1.2.

---

## 1 - PC side (one-time)

### 1.1 adb available in PATH

adb ships with Android platform-tools. If `adb` is not in PATH but the
SDK copy exists, add it permanently:

```bat
setx PATH "%PATH%;%LOCALAPPDATA%\Android\Sdk\platform-tools"
```

Open a NEW terminal, then verify:

```bash
adb version        # expected: Android Debug Bridge version 1.0.4x
```

The admin scripts (`provision.ps1`, `logpull.ps1`, ...) require this.

### 1.2 Identify the box at any time

```powershell
powershell -File admin\windows\identify_box.ps1          # USB or verdict
powershell -File admin\windows\identify_box.ps1 -Full    # + [N3] inventory
powershell -File admin\windows\identify_box.ps1 -Target 192.168.50.20:5555
```

States reported: adb absent / box absent (expected USB VIDs listed) /
visible outside adb (driver or debug issue) / reachable (identity card,
device.conf consistency).

Expected USB IDs on RK322X:

| VID:PID    | Meaning                        |
|------------|--------------------------------|
| 18D1:4EE7  | Google ADB composite (usual)   |
| 2207:0006  | Rockchip adb only              |
| 2207:0011  | Rockchip MTP+adb               |
| 1F3A:....  | loader/maskrom (NOT adb)       |

---

## 2 - Key side ([P1])

Build fresh if needed, then copy to a FAT32 key ROOT:

```bash
tools/build.sh                       # dist/<name>.dpk + .sha256 (+ dist/latest)
# copy to key: rk322x-tools_v17_<BUILD>.dpk, .dpk.sha256, deploy.sh
```

Optional: `tools/usb_zip.sh` builds a self-service key zip (docs included).
The key is the SOURCE OF TRUTH: it alone is enough to redeploy everything.

---

## 3 - TV side after factory reset ([P2][P3][P4])

With the remote only:

- [P2] Settings -> About -> tap "Build number" 7x -> developer options
- [P3] Enable **USB debugging**
- [P4] Network -> Ethernet -> Static: IP `192.168.50.20` /24,
  GW `192.168.50.1`, DNS `8.8.8.8`

---

## 4 - Connect and gate-check

```bash
identify_box.ps1 -Full     # identity card + hardware inventory
adb kill-server && adb devices    # [P5] box must be listed
adb shell ; su ; id               # [P6] uid=0 required
ls /mnt/media_rw/*/INSTALLER.sh   # [P7] key visible
```

[P5]+[P6]+[P7] green = cleared for install.

---

## 5 - Run the bring-up (docs/STARTUP.md)

Follow phases in order; each lists exact commands and EXPECTED results:

| Phase | Content | Gate |
|---|---|---|
| A | rampre baseline [A1][A2] | baseline file on key |
| 1 | INSTALLER.sh [I1] | `TERMINE`, boot hook OK |
| 2 | config CHECK / review / ping [C1-C3] | "[ OK ] configuration conforme" |
| 2bis | thermal ECO, mem_tune OPTIMIZE, CUT [O1-O7] | check_state clean |
| 2ter | ramstep instrumented run [O8] | log/ram_steps_<TS>.txt |
| 3 | nreg + selftest [R1][R2] | 10 themes PASS, ~50 PASS / 0 FAIL |
| 4 | inspections [N1-N4] | hardware_latest.txt saved |
| 5 | servers [S1-S5] | 3 ports LISTENING, missing: 0 |
| 6 | web panel [W1-W7] | badges green (user/user) |
| 7 | autonomous reboot [B1-B4] | panel alone at :8000, real clock |

V1-beta gate: TWO consecutive autonomous reboots + closed non-reg list.

---

## 6 - Quick recovery

| Symptom | Fix |
|---|---|
| Box plugged but absent | data cable / re-do [P2][P3] / Google USB driver |
| Visible outside adb (18D1/2207) | debug USB off -> [P3]; driver error -> install driver |
| Box unreachable on network | adb USB then `set_network` on the box |
| Everything broken | MXQ factory reset, resume at section 2 |
