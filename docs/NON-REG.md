# NON-REG - Base de non-regression

> Points valides **OK sur le device** (Leelbox RK322X, dpk v17, cle F43F-A8F6).
> Toute evolution ne doit pas casser ces acquis. Source : logs recette/selftest/exec
> du 2026-08-23 (horloge box 1970, session 00h04 -> 01h40).

**Verification executable : outil `nreg`** (scripts/outils/nreg.sh) - les 10 themes
ci-dessous sont relancables a tout moment :

```bash
nreg              # tous les themes + bilan PASS/FAIL
nreg 4            # un seul theme : numero, nom ou prefixe (nreg mem, nreg wifi)
nreg HELP         # liste des themes
```

Legende : [OK] valide sur device - source log indiquee.

NB : les traces brutes ayant alimente cette base ont ete purgees apres
extraction (session 2026-08-23) ; les constats essentiels sont integres
ci-dessus. La derniere passe device (dpk >= 26.08.2317.3340) repartira
d'un repertoire log/ vide et regenerera des traces fraiches.

---

## 1. Installation / Deploiement

| Point | Etat | Source |
|---|---|---|
| P1 INSTALL (VERSION + STATUS) | [OK] | recette_19700101-013414 |
| deploy HELP | [OK] | selftest_19700101-013416 |
| Cle USB detectee automatiquement (/mnt/media_rw/F43F-A8F6) | [OK] | selftest_19700101-013416 |
| Modules core (runlog, config) | [OK] | selftest_19700101-013416 |

## 2. Selftest outils (44/44 PASS)

| Outil | Verif | Source |
|---|---|---|
| help, menu | [OK] | selftest_19700101-013416 |
| check_state | [OK] | selftest_19700101-013416 |
| inspect_system / inspect_services | [OK] | selftest_19700101-013416 |
| device_info | [OK] | selftest_19700101-013416 |
| conf_check | [OK] | selftest_19700101-013416 |
| run_state | [OK] | selftest_19700101-013416 |
| inspect_gui STATUS | [OK] | selftest_19700101-013416 |
| thermal STATUS | [OK] | selftest_19700101-013416 |
| vitals STATUS | [OK] | selftest_19700101-013416 |
| mem_tune STATUS | [OK] | selftest_19700101-013416 |
| cut_services STATUS | [OK] | selftest_19700101-013416 |
| system_rw STATUS | [OK] | selftest_19700101-013416 |
| motd STATUS | [OK] | selftest_19700101-013416 |
| net_diag / sys_diag | [OK] | selftest_19700101-013416 |
| sd_inspect / sd_boot STATUS | [OK] | selftest_19700101-013416 |
| set_time STATUS / sync_usb STATUS | [OK] | selftest_19700101-013416 |
| disable_wireless ST | [OK] | selftest_19700101-013416 |
| front_led STATUS | [OK] | selftest_19700101-013416 |
| ssh_server STATUS | [OK] | selftest_19700101-013416 |
| amorce | [OK] | selftest_19700101-013416 |
| boot HELP + STATUS | [OK] | selftest_19700101-013416 |
| reboot HELP + STATUS | [OK] | selftest_19700101-013416 |
| remote_map HELP / front_digit HELP+STATUS | [OK] | selftest_19700101-013416 |
| investigate HELP / stress_ram HELP+STATUS | [OK] | selftest_19700101-013416 |
| crowdsec HELP *(retire depuis) / capture HELP / net_watch HELP | [OK] | selftest_19700101-013416 |
| rotate_logs / media / hdmi STATUS | [OK] | selftest_19700101-013416 |

## 3. Configuration

| Point | Etat | Source |
|---|---|---|
| conf_check sections 1-5 conformes (cles, formats, valeurs, profil, cles inconnues) | [OK] | conf_check_19700101-013704 |
| Section [6] optimisations appliquees 3/3 (vm tunable, lmk early, logd 256K) | [OK] | conf_check_19700101-013704 |
| zram N/A coherent avec MEM_ZRAM_MB=0 (kernel sans backend lz4) | [OK] | conf_check_19700101-013704 |

## 4. Memoire (mem_tune)

| Point | Etat | Source |
|---|---|---|
| P4 mem_tune OPTIMIZE rc=0 | [OK] | recette_19700101-013414 |
| Profil applique + origine sauvegardee (/data/etc/mem_tune.orig) | [OK] | mem_tune_19700101-013518 |
| swappiness=100, minfree x1.4 (lmk early), logd 256K effectifs | [OK] | mem_tune_19700101-013518 |

## 5. Boot

| Point | Etat | Source |
|---|---|---|
| Sequence boot : mem_tune -> cut_services -> STOP -> EXPOSE -> front_digit CLOCK | [OK] | boot_19700101-012936 |
| BOOT_MEM_TUNE / BOOT_CUT_SERVICES / BOOT_EXPOSE executes au demarrage | [OK] | boot_19700101-012936 |

## 6. Reseau

| Point | Etat | Source |
|---|---|---|
| eth0 UP, IP statique 192.168.50.20 | [OK] | check_state_19700101-013716 |
| DNS 8.8.8.8 (8.8.4.4) | [OK] | check_state_19700101-013716 |

## 7. Wireless / Bluetooth

| Point | Etat | Source |
|---|---|---|
| Wi-Fi desactive (wlan0/p2p0 absentes) | [OK] | check_state_19700101-013716 |
| Bluetooth desactive (hci0 absent) | [OK] | check_state_19700101-013716 |

## 8. Diagnostics

| Point | Etat | Source |
|---|---|---|
| P5 inspect_all complet rc=0 | [OK] | recette_19700101-013414 |
| device_info / inspect_system / inspect_services / inspect_display / inspect_remote / inspect_user | [OK] | exec 013721-013804 |
| investigate / media / hdmi STATUS / rotate_logs | [OK] | exec 013700-013702 |
| RAM totale reportee 2011 Mo, CPU interactive 1464 MHz | [OK] | check_state_19700101-013716 |

## 9. Carte SD (sd_boot)

| Point | Etat | Source |
|---|---|---|
| BOOT_SD_LAST=1 : sd_boot execute en fin de boot, carte absente geree proprement (rc=0) | [OK] | sd_boot_19700101-013649 |

## 10. Traces / Logs

| Point | Etat | Source |
|---|---|---|
| P6 run_state : 21 outils traces, rotation 5 traces/outil | [OK] | run_state_19700101-013938 |
| Entete standard des traces exec (script/debut/device/uid/log) | [OK] | toutes traces exec |

---

## Points OUVERTS (hors non-reg, en cours de traitement)

| # | Sujet | Etat |
|---|---|---|
| O1 | Recette P7 EXPOSE : trace incomplete (interrompue pendant P7, vieux build sans fix serveurs) | CORRIGE (serveurs pipes + sondes bornees) - A REVALIDER sur device |
| O2 | Trace boot sans footer rc (vieux build) | SANS CODE (couvert : front_digit borne 90 s, sd_boot dernier) - A REVALIDER sur device |
| O3 | check_state : WARN Passerelle absente sur eth0 | CORRIGE (BOOT_SET_NETWORK=1) - A REVALIDER sur device |
| O4 | Horloge box en 1970 toute la session | CORRIGE (BOOT_TIME_SYNC=1 + passerelle O3) - A REVALIDER sur device |
| O5 | Residus 'box'/'test' + JAMAIS obsoletes sur le device | CORRIGE (link_bin purge les liens morts au INSTALL) - A REVALIDER sur device |
| O6 | Chaine swap cle -> repli /data + sonde PROBE acceptation swapon (+ build direct syscall si agent absent) | CODE LIVRE (mem_tune OPTIMIZE/STATUS/PROBE [O9], core/swap.sh) - A VALIDER sur device |
| O7 | Leviers RAM additionnels : BACKGROUND_PROC_LIMIT/ALWAYS_FINISH_ACTIVITIES, BOOT_TRIM_CACHES, KSM+scheduler (inspect_dev 4b), launcher_toggle [C4] | CODE LIVRE - A VALIDER sur device |

Tous les points sont traites cote depot ; la derniere passe device
(dpk >= 26.08.2317.4931) valide leur fermeture avec traces fraiches.
