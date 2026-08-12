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

* [ ] Couper le HDMI

### Déploiement

* [ ] Améliorer la gestion des commandes de `deploy.sh`
* [ ] Ajouter le suivi de l'état du déploiement
* [ ] Ajouter la validation du déploiement
* [ ] Ajouter la détection automatique des erreurs
* [ ] Améliorer les mécanismes de rollback
* [ ] Ajouter une vérification post-déploiement

### Configuration

* [ ] Améliorer les profils de périphériques
* [ ] Centraliser la configuration des appareils
* [ ] Ajouter la validation de configuration
* [ ] Prendre en charge plusieurs profils de périphériques
* [ ] Ajouter des paramètres spécifiques par modèle


## 🌐 Réseau

* [x] Améliorer les scripts de configuration réseau
* [ ] Ajouter des outils de diagnostic réseau
* [ ] Ajouter des tests de connectivité
* [ ] Ajouter la détection automatique de l'adresse IP
* [ ] Améliorer la gestion du serveur HTTP
* [ ] Ajouter la vérification de l'état des interfaces réseau
* [ ] Ajouter la détection des problèmes de connexion

---

## 🔌 USB

* [x] Améliorer la détection des périphériques USB
* [ ] Améliorer la synchronisation USB
* [ ] Ajouter le suivi de l'état de synchronisation
* [ ] Ajouter la validation de la synchronisation
* [ ] Améliorer la gestion des supports USB absents
* [ ] Ajouter la détection des erreurs USB
* [ ] Ajouter des informations sur les périphériques connectés

---

## 📡 Wi-Fi & Bluetooth

* [ ] Améliorer la gestion de l'arrêt du Wi-Fi
* [ ] Améliorer la gestion de l'arrêt du Bluetooth
* [ ] Ajouter la détection de l'état des interfaces sans fil
* [ ] Vérifier la désactivation effective des interfaces
* [ ] Ajouter des diagnostics Wi-Fi
* [ ] Ajouter des diagnostics Bluetooth
* [ ] Améliorer la gestion des erreurs liées aux interfaces sans fil

---

## 🔍 Diagnostics

* [ ] Ajouter des diagnostics automatiques des appareils
* [ ] Collecter les informations matérielles
* [ ] Collecter les informations système Android
* [ ] Ajouter des diagnostics du stockage
* [ ] Ajouter des diagnostics de la mémoire
* [ ] Ajouter des diagnostics des processus
* [ ] Ajouter des diagnostics réseau
* [ ] Ajouter un état général de santé du périphérique
* [ ] Générer un rapport de diagnostic

---

## 📋 Manifests de déploiement

* [ ] Définir des manifests de déploiement
* [ ] Ajouter la validation des manifests
* [ ] Ajouter le versioning des manifests
* [ ] Conserver l'historique des déploiements
* [ ] Permettre des déploiements reproductibles
* [ ] Ajouter la vérification de compatibilité avec le périphérique
* [ ] Ajouter des manifests spécifiques par modèle

---

## ⚙️ Automatisation

* [ ] Automatiser l'initialisation des périphériques
* [ ] Automatiser la configuration de la date et de l'heure
* [ ] Automatiser la configuration réseau
* [ ] Automatiser l'installation des scripts
* [ ] Automatiser la collecte des logs
* [ ] Ajouter des contrôles de santé après déploiement
* [ ] Automatiser les diagnostics
* [ ] Automatiser les vérifications de configuration

---

## 🖥️ Administration

### Interface utilisateur

* [ ] Créer une interface d'administration Web
* [ ] Afficher l'état des périphériques
* [ ] Afficher les informations système
* [ ] Afficher les logs
* [ ] Suivre les déploiements en temps réel
* [ ] Permettre le lancement d'actions depuis l'interface

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
* [ ] Gestion distante des périphériques
* [ ] Déploiement multi-périphériques
* [ ] Profils de déploiement avancés
* [ ] Gestion centralisée des configurations
* [ ] Monitoring des périphériques
* [ ] Historique centralisé des opérations
* [ ] Système de notifications
* [ ] API REST d'administration
* [ ] Versioning complet des déploiements
* [ ] Tests automatisés complets
* [ ] Intégration CI/CD

### Logs

* [ ] Améliorer le format des logs
* [ ] Ajouter des résumés de déploiement
* [ ] Ajouter différents niveaux de logs
* [ ] Améliorer la collecte des logs
* [ ] Ajouter la rotation des fichiers de logs
* [ ] Ajouter un rapport de diagnostic

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

* [ ] Renforcer la gestion des accès Root
* [ ] Sécuriser les scripts de déploiement
* [ ] Valider les fichiers avant installation
* [ ] Vérifier l'intégrité des fichiers déployés
* [ ] Ajouter une gestion des permissions
* [ ] Ajouter une traçabilité des opérations sensibles

## 🗺️ Priorités

Les priorités actuelles sont orientées autour de quatre axes :

```text
Déploiement fiable
        ↓
Diagnostics & monitoring
        ↓
Administration centralisée

```

---

## ℹ️ Notes

Cette roadmap est volontairement évolutive.

Les fonctionnalités peuvent être ajoutées, supprimées ou réorganisées en fonction des besoins du projet et des retours d'utilisation.

Les éléments cochés correspondent aux fonctionnalités considérées comme déjà disponibles dans la version actuelle. Les éléments non cochés représentent des évolutions prévues ou envisagées.
