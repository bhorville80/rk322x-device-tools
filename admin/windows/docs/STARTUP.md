# STARTUP - From-scratch installation and bring-up procedure

> Full deployment of a stock RK322X box up to full autonomy.
> Reference dpk: latest build in dist/. Each phase lists exact commands
> and EXPECTED results. Do not chain phases past a failure.
>
> ## Convention d'identification des actions
> Chaque action est identifiee par [Xnn] :
>   X = theme (P Prepa, I Install, C Config, O Optim, R Re-check,
>              N iNspection, S Serveur, W Web IHM, B Boot/reboot)
>  nn = numero de l'action/script dans ce theme.
> Les PREREQUIS citent les [Xnn] requis avant de demarrer une phase.

---

## Phase 0 - Preparation

**Prerequis : aucun (point de depart)**

### Sur le PC
- [P1] Copier sur la cle USB (FAT32) : `rk322x-tools_v17_<BUILD>.dpk` (+ `.sha256`) et `deploy.sh`

### Sur la TV (telecommande)
- [P2] Parametres → A propos → taper 7x "numero de build" → options developpeur
- [P3] Activer **Debogage USB**
- [P4] Reseau → Ethernet → Statique : IP `192.168.50.20` `/24`, GW `192.168.50.1`, DNS `8.8.8.8`

### Connexion PC <-> box
- [P5] `adb kill-server && adb devices`            -> la box apparait
- [P6] `adb shell ; su`
- [P7] `ls /mnt/media_rw/*/INSTALLER.sh`           -> la cle est visible

---

## Phase A - Empreinte memoire AVANT installation

**Prerequis : [P6]**

- [A1] (PC) `adb push scripts\optim\rampre.sh /data/local/tmp/`
- [A2] (box) `sh /data/local/tmp/rampre.sh 120`

Attendu : `rampre_<TS>.txt` sur cle/sdcard (MemAvailable moy/min/max,
top PSS, pressions lmk). C'est la LIGNE DE BASE des benefices.

---

## Phase 1 - Installation + hook + application

**Prerequis : [P7]**

- [I1] `sh /mnt/media_rw/*/INSTALLER.sh`
       valide [I1a] paquet, [I1b] deploy PKG, [I1c] revue config,
       [I1d] boot INSTALL (hook persistant), [I1e] boot TEST (application),
       [I1f] aliases

Attendu : bloc `[5] Demarrage automatique... [ OK ]` puis `TERMINE`.

---

## Phase 2 - Configuration & verification

**Prerequis : [I1]**

- [C1] `config CHECK`          -> "[ OK ] configuration conforme"
- [C2] `config`                -> revue visuelle (IP/GATEWAY, BOOT_*, WEB_RUN)
- [C3] (PC) `ping 192.168.50.20`

---

## Phase 2bis - Optimisation & performance

**Prerequis : [C1]**

- [O1] `thermal STATUS` puis `thermal ECO`         (profil 24/7)
- [O2] `mem_tune STATUS` puis `mem_tune OPTIMIZE`  (swappiness/LMK/logd)
- [O3] `stress_ram`                                (tenue sous pression)
- [O4] `vitals`                                    (releve post-coupure)
- [O4b] swap sur la cle : actif par defaut (MEM_SWAP_FILE=auto,
  512 Mo, swappiness 40) - mem_tune OPTIMIZE le cree/reactive
- [O5] `cut_services STATUS` puis `cut_services CUT` (allegement ~120-150 Mo)
- [O6] headless : `field_mode OFF` puis `hdmi OFF` (optionnel)
- [O7] contre-verif : `check_state` ; `conf_check | tail -5` ; `nreg memoire`

Note : [O2][O5] sont reappliques automatiquement a chaque boot
(BOOT_MEM_TUNE / BOOT_CUT_SERVICES).

---

## Phase 2ter - Deploiement instrumente (ramstep)

**Prerequis : [O7]**

- [O8] `ramstep 30`
       rejoue la sequence avec MESURE RAM avant/apres chaque etape et
       pause 30 s ; effet serveur isole. Chronologie :
       `log/ram_steps_<TS>.txt` (delta_prev par etape)

---

## Phase 3 - Re-check (non-regression)

**Prerequis : [I1]**

- [R1] `nreg`                  -> 10 themes PASS sans FAIL
- [R2] `selftest | tail -3`    -> ~50 PASS / 0 FAIL

---

## Phase 4 - Inspection

**Prerequis : [I1]**

- [N1] `inspect_all LIST`      -> classification coeur/exploration
- [N2] `inspect_all`           -> analyses coeur (~1 min)
- [N3] `device_info`           -> inventaire puces par fonction
- [N4] `hw_report SAVE`        -> rapport complet -> log/hardware_latest.txt

---

## Phase 5 - Serveur

**Prerequis : [I1] pile web demarree**

- [S1] `manage`                -> vue globale services/web/ports
- [S2] `manage web`            -> 3 ports LISTENING, panneau servi, api OK
- [S3] `deploy STATUS`         -> manquants : 0
- [S4] `show_key`              -> paquet cle vs installe

---

## Phase 6 - Tests IHM (navigateur PC)

**Prerequis : [S2]**
Identifiants panneau par defaut : `user` / `user`
(PANEL_USER/PANEL_PASS device.conf).

- [W1] Accueil      : badges verts, heure box reelle, versions a jour
- [W2] Commandes    : CHECK STATE / SYNC HORLOGE instantanes
- [W3] Cle          : HARDWARE REPORT genere + telechargement direct
- [W4] Cle          : televerser le .dpk -> sha verifie + APPLY propose
- [W5] Metriques    : VITALS affiche des valeurs fraiches
- [W6] Telecommande : miroir TV ~2 s, touches, clic = TAP
- [W7] Infos        : identite/materiel/config/manifest remplis
Console distante : necessite WEB_RUN=1 ET token actif.

---

## Phase 7 - LE critere final : reboot autonome

**Prerequis : [W1..W7]**

- [B1] `reboot` puis attendre 4 a 6 minutes SANS toucher
- [B2] `http://192.168.50.20:8000/` -> IHM presente seule, badges verts
- [B3] `date` -> horloge reelle
- [B4] dernier `log/exec/boot_*.log` -> sequence complete finissant par
       `[boot] panneau OK (8000)` + footer `fin/rc`

[B2]+[B3]+[B4] verts = objectif "zero action manuelle" ATTEINT.

---

## Recuperation

| Symptome | Remediation |
|---|---|
| Box injoignable en reseau | adb USB (cable PC->box) puis `set_network` |
| IP perdue apres une ancienne version | reboot simple ; ou statique via TV |
| Hook non pose (rc/init.d refuses) | repli install-recovery.sh automatique |
| Serveurs morts apres manip | `su -c 'deploy STOP ; deploy EXPOSE'` |
| Tout est casse | reset usine MXQ puis reprise a [P1] |

La cle USB est la SOURCE DE VERITE : elle seule suffit a tout redeployer.
