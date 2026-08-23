# RUN-BETA - Plan d'execution V1-beta par checkpoints

> Sequence choisie : [9] -> [5] -> COMMIT -> [2] -> [4] -> COMMIT ->
> [6][7][8] -> COMMIT -> retour rapport / re-priorisation.
> Chaque checkpoint liste les commandes exactes et les PREUVES a renvoyer.
> Les IDs [Xnn] referencent docs/STARTUP.md.

## Table de priorisation initiale

| Prio | # | Tache | Risque | Preuve |
|---|---|---|---|---|
| 1 | 9 | swap/mem_tune sur box vierge | ELEVE | /proc/swaps |
| 1 | 5 | INSTALLER interactif complet | moyen | deroule + hook |
| 2 | 2 | TV dev/debug/IP statique | faible | adb devices |
| 2 | 4 | rampre baseline archive | nul | rampre_*.txt |
| 3 | 6 | mecanisme hook identifie | faible | boot STATUS |
| 3 | 7 | badges verts sans action | moyen | navigateur |
| 3 | 8 | config conforme + ping | faible | conf_check/ping |
| 4 | R/N/S/W | nreg, selftest, inspections, matrice IHM | faible | bilans |
| gate | B | reboot autonome x2 + tag v1.0-beta | - | traces |

## CHECKPOINT A - tache 9 : mem_tune + swap sur box VIERGE

Kit autonome (toolkit non installe) :

```bash
# PC
adb push scripts\mem_tune.sh /data/local/tmp/
adb push scripts\core\config.sh /data/local/tmp/core_config.sh
adb shell ; su
mkdir -p /data/local/tmp/core
cp /data/local/tmp/core_config.sh /data/local/tmp/core/config.sh
sh /data/local/tmp/mem_tune.sh OPTIMIZE
cat /proc/swaps          <- LIGNE DECISIVE : swap.bin actif ou warn ?
free
```

Preuves a renvoyer : sortie OPTIMIZE complete + /proc/swaps + free.
Plan si echec swapon sur vfat : verdict documente puis plan B (partition
SD type 82) sans bloquer la suite.

COMMIT A : resultats + fix eventuel code.

## CHECKPOINT B - tache 5 : INSTALLER interactif

```bash
sh /mnt/media_rw/*/INSTALLER.sh
```

Renvoyer le DERROULE INTEGRAL jusqu'a TERMINE + PROCHAINES ETAPES.
COMMIT B : install + mecanisme de hook observe + fixes immediats.

## CHECKPOINT C - taches 2 + 4

- TV : options developpeur, debogage USB, IP statique ([P2]-[P4])
- ping OK depuis le PC ([C3])
- baseline : `rampre 120` depuis scripts/ installe ([A2])

COMMIT C : confirmation reseau + baseline RAM archivee (reference des gains).

## CHECKPOINT D - taches 6 + 7 + 8

- [6] `boot STATUS` : mecanisme actif (rc / init.d / recovery)
- [7] navigateur direct : badges verts SANS action manuelle
- [8] `config CHECK` vert + ping

COMMIT D : NON-REG coche partiellement, ROADMAP mise a jour.

## Cloture

Retour au rapport global puis re-priorisation :
R/N/S/W (nreg, selftest, inspections N*, serveur S*) puis matrice IHM
W0..W7 (auth user/user, upload+APPLY reel, telecommande, MAXCONN/tcpsvd,
console RUN), enfin GATE : reboot autonome x2 consecutifs, fermeture
NON-REG O1-O5, tag v1.0-beta.
