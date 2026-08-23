# IHM - Guide d'utilisation du panneau web

> Tout se pilote depuis un navigateur : `http://<ip-box>:8000/`
> 6 pages, une barre de navigation commune, des badges d'etat de ports
> en tete de chaque page.

## Badges de ports (toutes les pages)

| Badge | Signification |
|---|---|
| vert `OK` | le port repond |
| orange `UP - token requis` | serveur actif mais protege par token |
| rouge `INJOIGNABLE` | service arrete ou reseau bloque |

---

## Page ACCUEIL

- **Bilan versions** : installee (/data/scripts) vs cle ; verdict "a jour"
  ou "divergent -> deploy INSTALL".
- **Verdict conf_check** : 3 dernieres lignes de la validation de config.
- **Dernier CHECK STATE** : entete du dernier etat boitier/reseau.
- **Heure box** : horloge de la machine comparee au PC -
  rouge = 1970 (HORLOGE FAUSSE), orange = ecart > 180 s (SYNC HORLOGE a faire).

## Page CLE

- **Premier demarrage** : rappel de la commande d'installation initiale.
- **Catalogue des outils** par fonction.
- **Televerser sur la cle** : choisir un fichier (.dpk/.sha256/.txt/.log,
  max 20 Mo) -> TELEVERSER. Le sha256 est calcule par le navigateur puis
  verifie par la box. Un .dpk propose automatiquement l'application.
- **Appliquer un dpk depose** : extrait l'archive tar.gz SUR LA CLE
  (mise a jour sans la debrancher). Ensuite : page Commandes > REBOX,
  ou `deploy INSTALL`.
- **Telechargements directs** : rapport materiel, bilans recette/state/
  vitals, manifest certifie, config, navigation du repertoire log/.

## Page COMMANDES

| Section | Boutons | Effet |
|---|---|---|
| Base | SYNC HORLOGE | met l'horloge box a l'heure UTC du PC |
| | CHECK STATE | etat complet boitier/reseau, resultat dans log/state_last.txt |
| | SYNC CLE | synchronise /data/scripts vers la cle |
| Logs | SEND LOGS / ROTATE / PURGE | collecte, rotation, purge des traces |
| Affichage TV | PANEL | ouvre le panneau web SUR LA TV |
| | HDMI OFF/ON, FIELD OFF/ON | coupe/restaure sortie et services affichage |
| Systeme | MODE ECO / MODE PERF | profil CPU thermique (24/7 : ECO) |
| | REBOOT | redemarrage (confirmation) |
| Materiel | RAPPORT MATERIEL | genere hw_report complet + lien telechargement |
| Recette | P1..P7, RETOUR | phases unitaires ; COMPLETE = P1->RETOUR |
| | GENERER MANIFEST | certification apres 7/7 OK |

Resultats affiches dans le bloc noir sous les boutons.

## Page METRIQUES

- **VITALS** : releve memoire/CPU/charge instantane (+ WATCH pour suivi).
- **CHECK STATE**, **CONF CHECK** : relances manuelles avec sortie brute.

## Page TELECOMMANDE

- **Ecran TV (miroir)** : capture d'ecran rafraichie (pause / 2 s / 4 s /
  8 s). **Un clic sur l'image = un TAP aux memes coordonnees sur la TV.**
- **Touches** : dpad + OK, RETOUR/HOME/MENU, VOL +/- , POWER.
- **Envoyer** : TEXT = message plein ecran sur la TV ;
  OUVRIR URL = page dans le navigateur de la TV.
- **Console distante** (equivalent adb shell) : une ligne -> sortie brute.
  Conditions : `WEB_RUN=1` dans device.conf ET token actif
  (`deploy TOKEN ON`) - sinon refuse volontairement. Bornee a 15 s / 8 Ko,
  chaque ligne est loggee.

## Page INFOS (donnees statiques)

- **Identite & versions** : Android, build, kernel, uptime, RAM, CPU, /data.
- **Materiel** : dernier rapport puces consultable + regeneration.
- **Configuration active** : device.conf servi en lecture.
- **Manifest recette certifie** : phases OK + empreintes sha256.

---

## Securite

- Sans token : API 8080 et GUI 8081 ouvertes au LAN (panneau 8000 statique).
- `deploy TOKEN ON` protege l'API/GUI ; le panneau demande la valeur une
  seule fois (localStorage).
- La console distante exige EN PLUS `WEB_RUN=1`.

## En cas de souci

- Badge 8080 rouge -> `deploy EXPOSE` sur la box (ou adb).
- "Failed to fetch" persistant -> voir TROUBLESHOOTING section WEB PANEL.
- Apres toute mise a jour des scripts : `deploy STOP && deploy EXPOSE`.
