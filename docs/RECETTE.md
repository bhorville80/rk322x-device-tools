# RECETTE SHEET - RK322X DEVICE TOOLS

Functional + energy acceptance run for the Leelbox MXQ box (rk322x,
Android 7.1.2, 2 GB RAM, headless 24/7). Hand-filled during the run -
not automated. Three tested sides: BOX (local), PC LINUX, PC WINDOWS,
plus the WEB PANEL.

## 1. Environment

| Item            | Value                         |
|-----------------|-------------------------------|
| Package         | rk322x-tools_v17_<BUILD_ID>   |
| Date/tester     | _____________________________ |
| Box/key IP      | 192.168.50.20 / _____________ |
| Initial state   | ( ) factory   ( ) provisioned |

Deliverable installation:

    tools/dpk.sh install -t 192.168.50.20:5555        (PC side)
    or: su -c 'sh /mnt/media_rw/*/deploy.sh INSTALL' (from the key)

## 2. Test cases - BOX SIDE (local, adb or console)

| #  | Action                      | Expected                                        | OK/KO |
|----|-----------------------------|-------------------------------------------------|-------|
| B01| deploy STATUS               | tools present = total, bin links ok             |       |
| B02| selftest                    | all modules answer, 0 KO                        |       |
| B03| conf_check                  | config compliant + sections [1..6]              |       |
| B04| mem_tune OPTIMIZE           | zram/swappiness/logd applied (or kernel noted)  |       |
| B05| mem_tune then conf_check    | section [6] = APPLIED on targeted lines         |       |
| B06| mem_tune RESTORE            | back to original values                         |       |
| B07| run_state                   | runs/count/rc + installed-never-run             |       |
| B08| device_info                 | chips by function + grouped services            |       |
| B09| inspect_all                 | all sections, rc synthesis at end               |       |
| B10| STOP then EXPOSE            | servers restarted: 8000/8180/8081 + watcher     |       |
| B11| boot INSTALL then STATUS    | init hook active, last pass traced              |       |
| B12| front_digit PROBE           | frame format memorized, SHOW "12.34" visible    |       |
| B13| remote_map STATUS           | target device + layout, 0 modification         |       |
| B14| net_watch STATUS            | connection states + top remote IPs              |       |
| B15| motd DEFAULT                | ASCII frame banner: panel URL + ports state     |       |

## 3. Test cases - WEB PANEL (http://192.168.50.20:8000)

Full page-by-page matrix: docs/IHM.md. Minimum grid:

| #  | Page       | Action              | Expected                                   | OK/KO |
|----|------------|---------------------|--------------------------------------------|-------|
| W01| accueil    | open                | config summary + versions + verdict        |       |
| W02| commandes  | SYNC HORLOGE        | box clock reset (PC UTC)                   |       |
| W03| commandes  | CHECK STATE         | instant answer, state_last displayed       |       |
| W04| cle        | HARDWARE REPORT     | report generated + downloadable link       |       |
| W05| cle        | upload .dpk         | sha verified, APPLY offered                |       |
| W06| metriques  | VITALS              | vitals_last.txt displayed                  |       |
| W07| telecommande| mirror + click TAP | screen refreshes ~2 s, tap lands on TV     |       |
| W08| infos      | static data         | identity/hardware/config/manifest filled   |       |
| W09| navigation | 6-page bar          | smooth navigation, current page highlighted|       |

## 4. Test cases - PC LINUX side

| #  | Tool                     | Expected                                        | OK/KO |
|----|--------------------------|-------------------------------------------------|-------|
| L01| admin/linux/provision.sh | check: steps [0..8], OK/KO summary              |       |
| L02| set_box_time.sh          | box clock aligned with PC                       |       |
| L03| logpull.sh               | collects key logs to the PC                     |       |
| L04| vitals_history.sh        | CSV history readable/plotted                    |       |

## 5. Test cases - PC WINDOWS side

Same grid as section 4 with provision.ps1 / set_box_time.ps1 /
logpull.ps1 / vitals_history.ps1.

## 6. Energy measurements

Protocol and sheet: docs/PJ-releve-energie.csv.
Reference scenarios:

| Ref | Scenario                          | Expected metric |
|-----|-----------------------------------|-----------------|
| N01| boot -> idle after EXPOSE         | peak W then stabilization |
| N02| idle 10 min headless (hdmi off)   | avg W |
| N03| idle ECO (thermal ECO)            | avg W vs N01 |
| N04| idle PERF (thermal PERF)          | avg W delta |
| N05| stress_ram 256 MB during measure  | max W |

## 7. Verdict

| Phase                     | GO/KO |
|---------------------------|-------|
| BOX (section 2)           |       |
| WEB PANEL (section 3)     |       |
| PC LINUX (section 4)      |       |
| PC WINDOWS (section 5)    |       |
| ENERGY (section 6)        |       |

Global: ______ GO ______ NO-GO - Comments: ______________________
