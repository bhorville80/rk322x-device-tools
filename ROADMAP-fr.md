# Roadmap

> Évolutions prévues et développements futurs pour `rk322x-device-tools`.

Ce document présente les fonctionnalités prévues, les améliorations techniques et les évolutions envisagées pour le projet.

---

## 🚧 Version actuelle

### Administration système

* [x] Accès ADB
* [x] Accès Root
* [x] Gestion de la date et de l'heure
* [x] Inspection du réseau
* [x] Synchronisation USB
* [x] Déploiement de scripts
* [x] Gestion du Wi-Fi / Bluetooth
* [x] Gestion des logs
* [x] Serveur HTTP de fichiers via BusyBox

---

## 📅 Court terme

* [x] Couper le HDMI (hdmi ON/OFF/STATUS + field_mode)

### Déploiement

* [x] Améliorer la gestion des commandes de `deploy.sh` (INSTALL/PKG/EXPOSE/CLEAN...)
* [x] Suivi de l'état du déploiement (deploy STATUS + manifest)
* [x] Validation du déploiement (verify_install + sh -n)
* [x] Détection des erreurs (recette : bilan GO/NO-GO par phases)
* [x] Rollback (backup auto + deploy RESTORE)
* [x] Vérification post-déploiement (selftest)

### Configuration

* [x] Profils de périphériques (config/profiles/*.conf)
* [x] Configuration centralisée (device.conf + secrets.conf)
* [x] Validation de configuration (conf_check, 6 sections)
* [x] Multi-profils (PROFILE= overlay)
* [x] Paramètres par modèle (clés HW_* + BOOT_*/FD_*)


## 🌐 Réseau

* [x] Améliorer les scripts de configuration réseau
* [x] Diagnostic réseau (net_diag + net_watch)
* [x] Tests de connectivité (net_diag PING/PORTS/THROUGHPUT)
* [x] Détection IP automatique (motd/amorce/start_server)
* [x] Serveur HTTP complet (EXPOSE : httpd+control+GUI+watcher)
* [x] État des interfaces (check_state)
* [x] Détection de problèmes (check_state WARN passerelle/DNS)

---

## 🔌 USB

* [x] Améliorer la détection des périphériques USB
* [x] Synchronisation USB améliorée (sync_usb STATUS/START)
* [x] Suivi de synchro (sync_usb STATUS)
* [ ] Ajouter la validation de la synchronisation
* [x] Clé absente gérée proprement (require_usb partout)
* [ ] Ajouter la détection des erreurs USB
* [x] Infos supports (media)

---

## 📡 Wi-Fi & Bluetooth

* [x] Arrêt Wi-Fi (disable_wireless + option avion)
* [x] Arrêt Bluetooth (disable_wireless)
* [x] État radios (disable_wireless STATUS)
* [x] Vérification effective (check_state section wireless)
* [x] Diagnostics Wi-Fi/BT (disable_wireless STATUS)
* [x] Erreurs sans fil (ON restaure, WIRELESS_AIRPLANE)

---

## 🔍 Diagnostics

* [x] Diagnostics automatiques (inspect_all + recette)
* [x] Informations matérielles (device_info, inspect_system)
* [x] Informations Android (inspect_services, getprop)
* [x] Stockage (df + sd_inspect + usure eMMC vitals)
* [x] Mémoire (mem_tune, stress_ram, vitals)
* [x] Processus (top RAM inspect_system/services)
* [x] Réseau (net_diag/net_watch/investigate REMOTE)
* [x] Telecommande IR : detection du recepteur reel (pwm/remote/rc privilegies avant le keypad face avant)
* [x] Santé générale (sys_diag + vitals WATCH)
* [x] Rapports (investigate ALL + SEND_LOGS + manifests)

---

## 📋 Manifests de déploiement

* [x] Manifests définis (install_*.manifest)
* [x] Validation manifests (recette MANIFEST 7/7 phases)
* [x] Versioning (manifests/current + history)
* [x] Historique conservé (rotation CLEAN)
* [x] Reproductibilité (sha256 scripts dans le manifest)
* [x] Compatibilité device (snapshot allconf device+conf)
* [x] Par modèle (profiles + snapshot identite device)

---

## ⚙️ Automatisation

* [x] Initialisation auto (amorce + boot hook init)
* [x] Date/heure (set_time AUTO/FILE/RTC/INIT/SET)
* [x] Réseau auto (set_network static/dhcp)
* [x] Installation auto (deploy INSTALL/PKG + liens bin)
* [x] Collecte logs (SEND_LOGS + recette RETOUR + rotation)
* [x] Contrôles post-install (selftest P2 + conf_check P3)
* [x] Diagnostics auto (recette P1..P7 bout-en-bout)
* [x] Config auto (conf_check P3 + boot mem_tune)
* [x] Carte SD examinee en TOUT DERNIER au boot (BOOT_SD_LAST + sd_boot CHECK : enumeration attendue, montage tardif, trace diagnostic)

---

## 🖥️ Administration

### Interface utilisateur

* [x] Interface d'administration Web (panneau 4 pages sur http://ip:8000)
* [x] État du périphérique (index.html : versions, conf_check, reseau)
* [x] Informations système (metriques.html : vitals/check_state/conf_check)
* [ ] Afficher les logs
* [ ] Suivre les déploiements en temps réel
* [x] Actions depuis l'interface (commandes.html + endpoints RECETTE)
* [x] Commandes IHM utilisables depuis le navigateur (CORS sur API 8080/8081 + saisie token cote panneau)

### Gestion des périphériques

* [x] Gestion de plusieurs périphériques
* [ ] Détection automatique des périphériques
* [ ] Identification des modèles
* [ ] Gestion des profils
* [ ] Historique des opérations
* [ ] Gestion des états des périphériques

---

## 🔮 Long terme

Fonctionnalités envisagées :

* [ ] Interface Web complète d'administration
* [x] Gestion a distance (control API 8080 token + GUI TV 8081)
* [ ] Déploiement multi-périphériques
* [ ] Profils de déploiement avancés
* [ ] Gestion centralisée des configurations
* [ ] Monitoring des périphériques
* [ ] Historique centralisé des opérations
* [ ] Système de notifications
* [ ] API REST d'administration
* [x] Versioning (DEPLOY_VERSION + dpk horodates + manifests history)
* [x] Tests automatises (selftest 40 checks + recette P1..P7)
* [ ] Intégration CI/CD

### Logs

* [x] Format de logs standardise (core/runlog.sh : entete/rc/rotation)
* [x] Resumes (run_state + recette bilan GO/NO-GO + manifests)
* [x] Niveaux (log/exec par outil + events net_watch + phases recette)
* [x] Collecte (deploy SEND_LOGS + recette RETOUR)
* [x] Rotation (rotate_logs + runlog 5 traces/outil)
* [x] Rapport diagnostic (investigate ALL -> log/investigate_*.txt)

---

---

## 📦 Déploiement multi-périphériques

* [ ] Gestion de plusieurs appareils simultanément
* [ ] Déploiement parallèle
* [ ] Suivi individuel des déploiements
* [ ] Gestion des erreurs par périphérique
* [ ] Rapport global de déploiement
* [ ] Annulation d'un déploiement
* [ ] Rollback par périphérique

---

## 🔐 Sécurité

* [x] Acces Root durcis (is_root id -u fallback, require_root partout)
* [x] Scripts securises (sh -n au build, cle noexec, elevation su ciblee)
* [x] Validation avant installation (verify_install + dpk sha256)
* [x] Integrite deployee (manifest recette : sha256 scripts)
* [ ] Ajouter une gestion des permissions
* [ ] Ne plus servir server/token via l'HTTP 8000 (racine de cle entierement exposee)
* [x] Tracabilite (runlog systematique, y compris reboot et BAN iptables)

## 🗺️ Priorités

Les priorités actuelles sont orientées autour de quatre axes :

```text
Déploiement fiable
        ↓
Diagnostics & monitoring ->>> SCRIPT diag en prio
        ↓
Administration centralisée

```

---

## ℹ️ Notes

Cette roadmap est volontairement évolutive.

Les fonctionnalités peuvent être ajoutées, supprimées ou réorganisées en fonction des besoins du projet et des retours d'utilisation.

Les éléments cochés correspondent aux fonctionnalités considérées comme déjà disponibles dans la version actuelle. Les éléments non cochés représentent des évolutions prévues ou envisagées.
