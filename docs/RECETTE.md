# FICHE DE RECETTE - RK322X DEVICE TOOLS v12

Recette fonctionnelle + energetique de la box Leelbox MXQ (rk322x,
Android 7.1.2, 2 Go RAM, headless 24/7).
Fiche a remplir a la main pendant la recette - pas d'automatisation.
Trois cotes testes : BOX (local), PC LINUX, PC WINDOWS.

## 1. Environnement

| Item            | Valeur                        |
|-----------------|-------------------------------|
| Paquet          | rk322x-tools_v12_<BUILD_ID>   |
| Date/recetteur  | _____________________________ |
| IP box / cle    | 192.168.50.20 / _____________ |
| Etat initial    | ( ) usine   ( ) provisionnee  |

Installation du livrable :

    tools/dpk.sh install -t 192.168.50.20:5555        (cote PC)
    ou : su -c 'sh /mnt/media_rw/*/deploy.sh INSTALL' (depuis la cle)

## 2. Cas de test - COTE BOX (local, adb ou console)

| #  | Action                    | Attendu                                        | OK/KO |
|----|---------------------------|------------------------------------------------|-------|
| B01| deploy STATUS             | outils presents = total, liens bin ok          |       |
| B02| selftest                  | tous les modules repondent, 0 KO               |       |
| B03| conf_check                | configuration conforme + sections [1..6]       |       |
| B04| mem_tune OPTIMIZE         | zram/swappiness/logd appliques (ou kernel note)|       |
| B05| mem_tune puis conf_check  | section [6] = APPLIQUE sur les lignes visees   |       |
| B06| mem_tune RESTORE          | retour aux valeurs d'origine                   |       |
| B07| run_state                 | lances/nb/rc + installes jamais lances         |       |
| B08| device_info               | puces par fonctionnalite + services groupes    |       |
| B09| inspect_all               | toutes sections, synthese rc en fin            |       |
| B10| STOP puis EXPOSE          | serveurs relances : 8000/8080/8081 + watcher   |       |
| B11| boot INSTALL puis boot STATUS| hook init actif, dernier passage trace      |       |
| B12| front_digit PROBE         | format trame memorise, SHOW "12.34" visible    |       |
| B13| remote_map STATUS         | device cible + layout, 0 modification          |       |
| B14| net_watch STATUS          | etats de connexions + top IP distantes        |       |
| B15| motd DEFAULT              | banniere cadre ASCII : URL panneau + etat 8000/8080/8081 |       |

## 3. Cas de test - PANNEAU WEB (http://192.168.50.20:8000)

| #  | Page       | Action              | Attendu                                   | OK/KO |
|----|------------|---------------------|-------------------------------------------|-------|
| W01| accueil    | ouverture           | resume config + versions + verdict a jour |       |
| W02| accueil    | verdict config      | ligne conf_check visible et coherente     |       |
| W03| cle        | lecture             | contenu cle + catalogue outils affiches   |       |
| W04| commandes  | SYNC HORLOGE        | horloge box remise (UTC PC)               |       |
| W05| commandes  | CHECK STATE         | state_last.txt rapatrie dans le resultat  |       |
| W06| commandes  | HDMI OFF/ON         | ecran coupe/rendu                         |       |
| W07| metriques  | VITALS              | releve vitals_last.txt affiche            |       |
| W08| metriques  | CONF CHECK          | rapport conf_check complet                |       |
| W09| navigation | barre des 4 pages   | navigation fluide, page courante surlignee|       |

## 4. Cas de test - COTE PC LINUX

| #  | Outil                    | Attendu                                         | OK/KO |
|----|--------------------------|-------------------------------------------------|-------|
| L01| admin/linux/provision.sh | check : etapes [0..8], resume OK/KO             |       |
| L02| provision.sh fix         | avec -Fix : corrections appliquees puis valides |       |
| L03| admin/linux/set_box_time | horloge box alignee sur le PC                   |       |
| L04| admin/linux/vitals_history | collecte CSV vitals vers history/             |       |
| L05| admin/linux/logpull.sh   | SEND_LOGS box -> history/logs/ (tgz extrait)    |       |

## 5. Cas de test - COTE PC WINDOWS

| #  | Outil                       | Attendu                                      | OK/KO |
|----|-----------------------------|----------------------------------------------|-------|
| C01| admin/windows/provision.ps1 | check : etapes [0..8] equivalents a L01      |       |
| C02| provision.ps1 -Fix -Net     | corrections + ajout sous-reseau si demande   |       |
| C03| set_box_time.ps1 / .bat     | horloge box alignee                          |       |
| C04| vitals_history.ps1          | collecte CSV vitals                          |       |
| C05| logpull.ps1                 | logs remontes vers history/logs/             |       |
| C06| write_set_heure.ps1/.bat    | fichier SET_HEURE pose a la racine de la cle |       |

## 6. Recette energetique (NRG)

Objectif : mesurer l'impact consommation des profils avant/apres optimisation.
Materiel : wattmetre prise (ou prise connectée), lecture W/V/A.

Protocole par phase (10 min minimum par palier, releves toutes les minutes
dans la PJ) :

| Phase | Configuration                                    | A relever      |
|-------|--------------------------------------------------|----------------|
| N01   | boot -> idle usine                               | W moyen, pic   |
| N02   | idle apres cut_services APPS                     | W moyen        |
| N03   | idle ECO (thermal ECO) + field_mode OFF          | W moyen        |
| N04   | idle PERF (thermal PERF)                         | W moyen        |
| N05   | HDMI ON vs OFF (a profil constant)               | delta W        |
| N06   | serveurs actifs + lecture USB (EXPOSE)           | W moyen        |
| N07   | 24h continus en configuration finale             | kWh, stabilite |

Gabarit de saisie : PJ-releve-energie.csv (a dupliquer par session).
Croiser avec : vitals CSV (temp/freq/ram) via vitals_history.

## 7. Criteres de sortie

| Critere                                              | Seuil            | Verdict |
|------------------------------------------------------|------------------|---------|
| Cas B/W/L/C KO bloquants                              | 0                |         |
| selftest KO                                           | 0                |         |
| conf_check                                            | conforme         |         |
| mem_tune : optimisations APPLIQUEES (section [6])     | conformes au cfg |         |
| Gain N02 vs N01                                       | a definir        |         |
| Delta N05 (HDMI off)                                  | a definir        |         |
| Stabilite N07                                         | 0 reboot/watchdog|         |

Verdict global : ( ) GO   ( ) GO avec reserves   ( ) NO-GO
