# STARTUP - Procedure d'installation et de mise en service from scratch

> Deploiement complet d'une box RK322X remise a zero jusqu'a l'autonomie totale.
> Dernier dpk de reference : voir dist/ (build le plus recent).
> Chaque phase indique les commandes EXACTES et le RESULTAT ATTENDU.
> En cas d'echec : ne pas enchanter la phase suivante avant resolution.

---

## Phase 0 - Preparation

### Sur PC
Copier a la racine de la cle USB (FAT32) :
```
rk322x-tools_v17_<BUILD>.dpk          (+ .sha256)
deploy.sh
```
(`INSTALLER.sh`, panneau web et tous les outils sont dans le dpk.)

### Sur la TV (telecommande)
1. Parametres → A propos → taper 7x sur "numero de build" → options developpeur
2. Activer **Debogage USB**
3. Parametres → Reseau → Ethernet → **Statique** :
   - IP `192.168.50.20` / masque `/24`
   - passerelle `192.168.50.1` / DNS `8.8.8.8`
   (persistant natif Android ; nos outils s'alignent dessus)

### Connexion PC <-> box
```bash
adb kill-server && adb devices        # la box doit apparaitre
adb shell ; su
ls /mnt/media_rw/*/INSTALLER.sh       # la cle est vue
```

---

## Phase 1 - Installation + hook + application

```bash
sh /mnt/media_rw/*/INSTALLER.sh
```

Interactive, avec validation a chaque etape :
- [0] presentation du paquet detecte (BUILD-INFO)
- 1/3 deploy PKG      -> scripts + panneau web + liens /data/bin
- revue des cles importantes -> option ajustement interactif (`config`)
- 2/3 boot INSTALL    -> point de lancement persistant
                        (mecanismes essayes dans l'ordre : init .rc,
                         init.d si supporte, bloc install-recovery.sh)
- 3/3 boot TEST       -> application immediate (memoire/reseau/horloge/web)
- bonus aliases       -> raccourcis adb shell (help, manage, nreg...)

**Attendu** : `[5] Demarrage automatique... [ OK ]`, pile web demarree,
message final TERMINE.

---

## Phase 2 - Configuration & verification

```bash
config            # revue visuelle complete numerotee
config CHECK      # = conf_check -> "[ OK ] configuration conforme"
exit ; exit
ping 192.168.50.20                    # reseau operationnel
```

Points a verifier sur la page `config` :
- `IP=192.168.50.20` / `GATEWAY=192.168.50.1`
- `BOOT_SET_NETWORK=1`, `BOOT_TIME_SYNC=1`, `BOOT_EXPOSE=1`
- `WEB_RUN=0` (console IHM desactivee par defaut)

---

## Phase 2bis - Optimisation & Performance

### A) Profil CPU thermique (24/7 -> ECO)
```bash
thermal STATUS        # gouverneur + temperatures actuelles
thermal ECO           # profil eco conseille pour un fonctionnement 24/7
```
Attendu : gouverneur eco actif, temperature < 60 C au repos.

### B) Memoire : optimisation puis test de tenue
```bash
mem_tune STATUS       # avant
mem_tune OPTIMIZE     # swappiness + LMK early + logd
stress_ram            # pression RAM controlee ~30 s, kills surveilles
vitals                # relevé apres coupure
```
Attendu : kills LMK propres pendant stress_ram, recuperation sans reboot.
C'est LA validation que la configuration memoire tient sous charge.

### C) Allegement services / paquets
```bash
cut_services STATUS   # ce qui tourne encore d'inutile
cut_services CUT      # coupe liste SAFE + PACKAGES_DISABLE
```
Attendu : ~120-150 Mo de PSS liberés (gms, mediacenter, launcher, vending...).

### D) Headless (si TV utilisee uniquement pour le panneau)
```bash
field_mode OFF        # arret des services d'affichage superflus
hdmi OFF              # sortie HDMI coupee (economie/chaleur)
```

### E) Contre-verification immediate
```bash
check_state           # synthese OK/KO/WARN
conf_check | tail -5  # optimisations 3/3 APPLIQUE
nreg memoire          # theme memoire seul -> PASS
manage service        # vue rapide services restants
```

Note : BOOT_MEM_TUNE=1 et BOOT_CUT_SERVICES=1 reappliquent tout ceci
automatiquement a chaque demarrage.

---

## Phase 3 - Re-check (non-regression)

```bash
nreg                  # 10 themes -> PASS sans FAIL
selftest | tail -3    # ~50 PASS / 0 FAIL
```

---

## Phase 4 - Inspection

```bash
inspect_all LIST      # classification coeur/exploration avec raison+attentes
inspect_all           # analyses coeur (~1 min)
device_info           # inventaire puces par fonctionnalite
hw_report SAVE        # rapport COMPLET -> log/hardware_latest.txt
                      # (recherche web des puces : datasheets/possibilites)
```

---

## Phase 5 - Serveur

```bash
manage                # vue globale : services + web + ports
manage web            # 3 ports ECOUTE, panneau servi, api repond
deploy STATUS         # manquants : 0
show_key              # paquet cle vs installe
```

---

## Phase 6 - Tests IHM (navigateur PC)

| Page | A tester | Attendu |
|---|---|---|
| Accueil | badges ports, heure box, versions | 3 verts, horloge reelle |
| Commandes | CHECK STATE, SYNC HORLOGE | reponse instantanee |
| Cle | RAPPORT MATERIEL + telechargement + televerser dpk | generation ~10 s, download direct |
| Metriques | VITALS | valeurs fraiches |
| Telecommande | image TV + touches + clic=TAP | mirroring ~2 s |
| Infos | identite/materiel/config/manifest | tout rempli |

Console distante (page Telecommande) : necessite `WEB_RUN=1`
(config SET WEB_RUN 1) ET token actif (deploy TOKEN ON).

---

## Phase 7 - LE critere final : reboot autonome

```bash
reboot
```

Attendre **4 a 6 minutes** sans rien toucher (30 s du bloc install-recovery +
fin de boot Android + attente de la cle jusqu'a 150 s + sequence complete).

Verification sans aucune action manuelle :
1. `http://192.168.50.20:8000/` -> IHM presente, badges verts
2. `date` -> horloge reelle
3. dernier `log/exec/boot_*.log` -> sequence complete avec
   `[boot] panneau OK (8000)` et footer `fin/rc`

Si la phase 7 passe : objectif "zero action manuelle" ATTEINT.

---

## Recuperation (en cas de probleme)

| Symptome | Remediation |
|---|---|
| Box injoignable en reseau | adb USB (cable PC->box) puis `set_network` |
| IP perdue apres une ancienne version | reboot simple ; ou parametrage statique via TV |
| Hook non pose (rc/init.d refuses) | mecanisme install-recovery.sh pris en repli auto |
| Serveurs morts apres manip | `su -c 'deploy STOP ; deploy EXPOSE'` |
| Tout est casse | reset usine MXQ puis cette procedure depuis Phase 0 |

La cle USB est la SOURCE DE VERITE : elle suffit a redeployer integralement.
