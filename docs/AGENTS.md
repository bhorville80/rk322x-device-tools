# AGENTS - Contexte projet pour agents IA

> Ce document est une **synthèse légère** : il donne le cadre pour comprendre
> le projet rapidement, mais **rien ne tient lieu de vérité ici**. Chaque
> responsabilité pointe vers la doc qui fait foi. Lis les sections liées
> avant d'agir sur un sujet.
>
> Objectif : permettre à tout agent (IA ou humain) de ne **rien supposer**.

---

## 1. Le projet en 5 lignes

Kit d'administration pour box Android TV **MXQ / RK322X** (Android 7.1.2,
headless 24/7). La **clé USB** est la source de vérité : elle porte le code,
les configs (profiles), les commandes `incoming`, les logs et les manifests.
Un paquet **`.dpk`** (tar.gz + sha256) s'installe sur la box via
`INSTALLER.sh`, puis la box fonctionne en autonomie au boot : réseau IP
statique, panneau web **:8000**, API de contrôle **:8180**, GUI TV **:8081**.

Commandes : `adb shell ; su ; sh /mnt/media_rw/*/INSTALLER.sh`
Panneau : `http://<ip-box>:8000/`

## 2. Les docs de vérité (à consulter AVANT toute intervention)

| Sujet | Document |
|---|---|
| 60 s pour tout comprendre, installation | [README.md](../README.md) |
| Installation / déploiement au complet | [docs/STARTUP.md](STARTUP.md) |
| **Règles de code obligatoires** (avant d'écrire la moindre ligne) | [docs/CODING.md](CODING.md) |
| Catalogue des outils par thème | [docs/TOOLS.md](TOOLS.md) |
| Panneau web : pages, boutons, console | [docs/IHM.md](IHM.md) |
| Boîte à commandes internes / binaires | [docs/BEST-COMMANDES.md](BEST-COMMANDES.md) |
| Feuille de recette fonctionnelle/énergie | [docs/RECETTE.md](RECETTE.md) |
| Non-régression : baseline + points ouverts | [docs/NON-REG.md](NON-REG.md) |
| Plan de vérification V1-beta | [docs/RUN-BETA.md](RUN-BETA.md) |
| Ce qui est livré / à venir | [ROADMAP.md](../ROADMAP.md) |
| Démarrage pas à pas pour un novice | [docs/GUIDE-NOVICE.md](GUIDE-NOVICE.md) |

## 3. Architecture réelle (pas une vision)

```
<cle USB>/                       <box> /data/scripts + /data/bin
├── deploy.sh         point d'entrée PC/box (install, INSTALLER, HELP)
├── INSTALLER.sh      dans le .dpk : install interactive + hook de boot
├── *.dpk + *.sha256  paquets versionnés
├── config/device.conf + profiles/   profil courant = matériel réel
├── incoming/         commandes POSÉES EN FICHIER (typing livres)
├── log/              journal système (runlog standardisé)
├── manifests/current + history/     déploiement + évolution
├── history/          anciennes versions (scripts/config)
├── server/           start_server.sh, control_server.sh, watch_usb.sh,
│                     gui_server.sh, ssh_server.sh, token
└── scripts/          thèmes: boot optim inspect frontal outils core
```

Points à NE PAS oublier :
- **2 sens de sync** : `SYNC` = box→clé (`sync_usb.sh` copie
  `/data/scripts` vers la clé) et le sens inverse (clé→box) passe par
  `deploy INSTALL`/`INSTALLER` (la clé reste la source de vérité). Il
  n'y a **pas** de "SYNC2" : ne pas l'inventer.
- **watcher incoming = POLLING** (boucle `sleep 1`, pas d'inotifyd).
- **2 serveurs HTTP distincts** : httpd BusyBox **:8000** (fichiers)
  et serveur de contrôle tcpsvd/nc **:8180** (API). La GUI TV est **:8081**.

## 4. Cible matérielle & contraintes (non négociables)

- Shell = **POSIX strict, exécuté par mksh** (Android) ; BusyBox limité.
  Interdits : `[[ ]]`, `<<<`, tableaux, `echo -e`, `grep -P`... → **CODING §1**.
- Interdits : python, wget, curl, systemd, apt, GNU coreutils complets.
- Clé montée possible en `noexec` → toujours `sh /chemin/x.sh`.
- Ne **jamais** coder en dur l'ID de clé : détection dynamique
  (`/mnt/media_rw/*`, `scripts/core/usb.sh`) → **CODING §7**.
- IP statique par défaut `192.168.50.20` (config `device.conf`).

## 5. Règles de travail (valables pour tout agent)

1. **Observer avant de modifier.** Inspecter → identifier → expliquer →
   sauvegarder → modifier → tester → regarder les logs.
2. Tout outil ajouté respecte la **checklist de livraison en 10 points**
   (CODING §9) : squelette runlog, deploy INSTALL_LIST, aliases, selftest,
   help, TOOLS.md, actions.tsv, menu, build vert...
3. **Idempotence** : relancer ne doit jamais casser. Backup avant
   remplacement, jamais de suppression irréversible.
4. **Traçabilité** : toute action importante passe par le logging commun
   (runlog : `DATE HEURE [SCRIPT] ACTION RESULTAT`) et produit un manifest
   quand il s'agit d'un déploiement.
5. **Sécurité** : whitelist stricte des verbes (pas de shell distant
   arbitraire), pas d'eval inutile, token requis pour les endpoints
   sensibles, double garde (flag conf + token) pour RUN.
6. POSIX + LF uniquement (paquet rejette CRLF). `sh -n` avant commit.

## 6. Interfaces & canaux (vue d'ensemble)

| Canal | Mécanisme | Détail |
|---|---|---|
| Fichiers `incoming/` | polling `watch_usb.sh` (sleep 1) | verbes typés : HELP, SEND_LOGS, SYNC, STATE, VITALS, RECETTE*, FIELD_ON/OFF, HDMI_ON/OFF, PANEL, REBOX, ROTATE_LOGS, ECO/PERF_MODE, MEDIA... inconnu = log UNKNOWN + fichier supprimé |
| API **:8180** | tcpsvd + handlers détachés (fifo_loop) | `/api/HELP`, `/api/CONFIG`, `/api/TIME_SYNC`, `/api/UPLOAD`, `/api/APPLY_DPK`, `/api/PROC|DEV|PROBE`... ; `RUN` = gated (WEB_RUN=1 + token) |
| HTTP **:8000** | BusyBox httpd | panneau 6 pages, upload + sha256 navigateur, téléchargements |
| GUI TV **:8081** | gui_server.sh | KEY/TAP/TEXT/URL/SHOT + `?token=` |
| CLI | `deploy.sh` + outils | `INSTALL_LIST` (déploiement), `xrun <ID>` (registre `actions.tsv`) |
| SSH (opt.) | dropbear | optionnel, sinon adb |

Registre des actions exécutables : `scripts/core/actions.tsv` (convention
d'identification `[Xnn]`, CODING §10).

## 7. La question centrale du projet

À tout moment, le système doit répondre : *quel matériel ? quelle clé ?
quelle config ? quelle version ? quels composants ? quand installés ? quels
changements ? quels logs ? quel état réseau ? quelles commandes ?*

C'est la **traçabilité** qui prime, avant toute vélocité de fonctionnalité.