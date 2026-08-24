# TOOLS - Catalogue des outils du toolkit

> Reference alignee sur la convention [Theme+numero] de STARTUP.md.
> Chaque outil est installe dans /data/scripts + lien /data/bin
> (sauf mention contraire). `help` donne le detail complet sur la box.

## Organisation du depot (themes)

Depot thematise : `scripts/boot` (demarrage), `scripts/optim`
(memoire/thermie/allegement), `scripts/inspect` (diagnostics),
`scripts/frontal` (afficheur 4 digits/LED/IR), `scripts/outils`
(administration transversale), `scripts/core` (librairies + registre).
Le PAQUET reste a plat : la box ne voit aucun dossier (contract
/data/scripts). Point d'entree PC : `./rk322x.sh <outil|ID|LIST>`.

## Themes d'actions (xrun)

| Lettre | Theme |
|---|---|
| P | Preparation (PC/TV) |
| I | Installation |
| C | Configuration |
| O | Optimisation |
| R | Re-check (non-regression) |
| N | iNspection |
| S | Serveur |
| M | Metriques (reserve) |
| W | Web IHM |
| B | Boot/reboot |

Registre executable : `scripts/core/actions.tsv` - lancer par ID :
`xrun LIST` / `xrun <ID>` (ex : xrun C1).

## Deploiement & demarrage

| Outil | Role |
|---|---|
| deploy | INSTALL/PKG/RESTORE/EXPOSE/STOP/SEND_LOGS/STATUS/CLEAN/TOKEN/MAXCONN |
| INSTALLER.sh | installation complete interactive en une commande (racine cle) |
| boot | hook init persistant (INSTALL/REMOVE/STATUS/TEST) |
| amorce | bilan demarrage + raccourcis |
| sd_boot | carte SD examinee en dernier au boot |
| preflight | verif commandes critiques box + verdicts features (autonome) |

## Configuration

| Outil | Role |
|---|---|
| config | editeur interactif numerote (GET/SET/CHECK scriptables) |
| profile | profils nommes LIST/SHOW/DIFF/SWITCH/OFF/SAVE |
| set_network | IP/route/DNS sans coupure depuis device.conf |
| set_time | horloge AUTO (SET_HEURE/mtime cle/nom dpk/RTC) |
| conf_check | validation 6 sections + application optimisations |

## Memoire & performance

| Outil | Role |
|---|---|
| mem_tune | zram/swap chaine cle->repli /data/swappiness/LMK/logd (OPTIMIZE/STATUS/RESTORE/PROBE) ; PROBE = sonde acceptation swapon + fabrication directe d un mini-binaire syscall si agent absent ; STATUS affiche chaque maillon |
| swap_watch | gardien memoire RESIDENT (pattern net_watch) : STATUS/START [sec]/STOP/RUN ; reagit en runtime : TRIM caches sous seuil MemAvailable, RESCUE chaine swap morte, THRASH journalise sur cle ; BOOT_SWAP_WATCH=1 |
| cut_services | allegement services+paquets (CUT/APPS/RESTORE/STATUS) |
| thermal | profils ECO/PERF + temperatures |
| stress_ram | pression RAM controlee + rapport |
| vitals | releves instantanes/WATCH/CSV (+ colonnes swap : % utilise, delta pswp) |

## Environnement isole (chroot)

| Outil | Role |
|---|---|
| chroot_env | mini-conteneurs chroot (rootfs armhf sous /data/chroots) : PROBE capacites kernel, CREATE depuis cle/chemin (tar.gz/xz/bz2/tar), LIST/STATUS, ENTER shell interactif, EXEC commande ponctuelle, MOUNT/UMOUNT liens proc/sys/dev+DNS (auto au boot via BOOT_CHROOT=1), REMOVE [FORCE] |

## Reseau

| Outil | Role |
|---|---|
| net_diag | PING/PORTS/THROUGHPUT + verdicts |
| net_watch | daemon suivi connexions + BAN/UNBAN iptables |
| disable_wireless | coupe Wi-Fi/BT (OFF) / restaure (ON) / STATUS |

## Affichage & peripheriques

| Outil | Role |
|---|---|
| hdmi | OFF/ON/STATUS |
| field_mode | OFF/ON/STATUS services affichage |
| front_digit | horloge frontale (PROBE/CLOCK/ROTATE/SHOW) |
| front_led | LED frontale STATUS/ON/OFF |
| remote_map | remap telecommande IR (.kl) STATUS/APPLY/RESTORE |
| motd | banniere adb ON/SET/DEFAULT/OFF/STATUS |

## Inspection & diagnostics

| Outil | Role |
|---|---|
| check_state | verdict boitier/reseau/wireless/hdmi |
| inspect_all | coeur + classes exploration (FORCE = tout avec confirmation) |
| inspect_system/services/user/display/gui/remote | inspections unitaires |
| inspect_system | RAM/CPU/processus/kernel instantane |
| inspect_services | services init running vs allegement |
| inspect_display | afficheur frontal 4 digits (exploration) |
| inspect_gui | capacites UI/HDMI + SHOT/URL (exploration) |
| inspect_remote | recepteur IR/input/.kl (exploration) |
| inspect_user | methodes utilisateurs Android (exploration) |
| device_info | inventaire materiel par fonctionnalite |
| sys_diag | sante rapide charge/memoire/stockage |
| sd_inspect | carte SD montage/erreurs/espace |
| inspect_usb | cle USB x adb : montage/droits uid2000/adbd 5555 |
| inspect_proc | processus par PSS : critiques/kit/deja coupees/candidats detournables + traitement suggere (reduction RAM) |
| inspect_dev | capacites d'execution embarquee : runtimes/ABI/montages exec/primitives de service/cout mesure d'un mini-daemon |
| busi | busybox devoile : INFO inventaire+indice puissance, LIST/WHERE applets, CHECK besoins du kit + puissances endormies, POWERS demos vivantes (httpd/gzip/awk), RUN applet directe, WHO fournisseurs de /system/bin |
| launcher_toggle | lanceur TV : STATUS / ON (apps visibles, voie A/B inspect_dev) / OFF (retour headless via cut_services) |
| hw_report | rapport materiel COMPLET recherche web (SAVE = fichier cle) |
| investigate | collecte contextuelle ALL/scenario |
| capture | captures ecran/logcat |

## Non-regression & pilotage

| Outil | Role |
|---|---|
| nreg | non-regression executable : 10 themes, un seul lancable |
| xrun | executeur par identifiant [Theme+numero] (registre core/actions.tsv) ; mode serie xrun N8 N7 O4 + bilan, recherche FIND <motif> |
| macro | sequences nommees d'actions [ID] : NEW/ADD/DEL/RM/SHOW/RUN (/data/etc/macros), chaque action tracee + bilan global |
| selftest | tous les outils repondent (~50 checks) |
| recette | bout-en-bout P1..P7 + sections CONFIG/DIAG + manifest |
| ramstep | deploiement instrumente (mesure RAM par etape) |
| rampre | empreinte RAM box vierge (avant installation) |
| manage | dispatcher etat/gestion services-web-ports |
| menu | dispatcher par sujet (install/recette/pilotage/...) |
| run_state | lancements outils + echecs depuis log/exec |

## Maintenance

| Outil | Role |
|---|---|
| aliases | raccourcis uid-2000 dans /system/bin (INSTALL/REMOVE/STATUS/LIST) |
| rotate_logs | rotation tailles + purge par age (appele aussi au boot) |
| sync_usb | /data/scripts -> cle avec verification octet/octet |
| show_key | paquets dpk de la cle vs installe |
| reboot | redemarrage trace |
| tips | golden one-liners embarques sur la box (categories reseau/ram/stockage/web/secours/divers, ALL, FIND) - version executable de docs/BEST-COMMANDES.md |
| system_rw | bascule /system RW/RO (+DEBUG formes remount) |

## Serveurs (server/)

| Script | Port | Role |
|---|---|---|
| start_server.sh | 8000 | busybox httpd (panneau + cle) + auth PANEL_USER/PASS + lance les suivants |
| control_server.sh | 8080 | API commandes ; tcpsvd multi-listeners ou FIFO mono-slot ; UPLOAD/APPLY_DPK/RUN/MAXCONN |
| gui_server.sh | 8081 | telecommande TV KEY/TAP/TEXT/URL/SHOT |
| watch_usb.sh | - | consomme incoming/ (commandes filees par l'API) |
| ssh_server.sh | 2222 | dropbear optionnel (START/STOP/STATUS) |

## Cote PC (admin/)

linux : provision.sh, logpull.sh, set_box_time.sh, vitals_history.sh,
write_set_heure.sh - equivalents PowerShell/BAT sous windows/.

identification : identify_box.ps1 (windows) - etat de la box vue du PC :
adb absent / box absente (VID attendus 18D1/2207/1F3A + procedure P2-P3) /
visible hors adb (pilote ou debogage USB) / joignable (carte d'identite
modele-board-android-build-serial-eth0 + coherence device.conf ; -Full =
device_info [N3] sur la box).
