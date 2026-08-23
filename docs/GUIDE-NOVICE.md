# GUIDE NOVICE - Installer la box MXQ de A a Z (aucun prerequis)

> Version guidee, pour debutant, du parcours SETUP.md + STARTUP.md.
> Chaque etape donne : l'ACTION exacte -> ce que VOUS DEVEZ VOIR ->
> quoi faire si ce n'est pas le cas. Une seule commande a la fois.
> Duree totale : environ 1 h 30, sans se presser.

---

## 0 - Ce qu'il vous faut (5 min de verification)

| Materiel | Detail |
|---|---|
| La box TV | Leelbox MXQ (RK322X), remise a zero de preference |
| Son alimentation | branchee a la TV ou au mur |
| Un cable Ethernet | box <-> box internet de la maison |
| Un cable USB | bout A (PC) vers micro/bout selon la box ; doit etre un cable DE DONNEES (si la box ne chauffe pas en charge avec, c'est bon signe) |
| Une cle USB | format FAT32, au moins 1 Go libre |
| Le PC Windows | celui sur lequel vous etes |

Lexique express :
- **adb** = le pont de commande entre le PC et Android (la box).
- **dpk** = le paquet contenant tous les outils (comme un .zip signe).
- **panneau** = page web de pilotage de la box (ouverte dans le navigateur).

---

## 1 - Preparer le PC (une seule fois)

### Etape 1.1 - Ouvrir le bon terminal

ACTION : touche Windows, tapez `powershell`, Entree.

VOUS DEVEZ VOIR : une fenetre bleue foncee avec `PS C:\Users\...>`.

### Etape 1.2 - Verifier si adb est deja la

ACTION : tapez `adb version` puis Entree.

- SI vous voyez `Android Debug Bridge version ...` : parfait, passez a l'Etape 2.
- SINON (`adb introuvable` / `not recognized`) : tapez :

```bat
setx PATH "%PATH%;%LOCALAPPDATA%\Android\Sdk\platform-tools"
```

Puis FERMEZ la fenetre, rouvrez-la (Etape 1.1) et recommencez `adb version`.

SI ca ne marche toujours pas : installez « Android SDK platform-tools »
(zip officiel Google), decompressez dans `C:\platform-tools`, puis :

```bat
setx PATH "%PATH%;C:\platform-tools"
```

### Etape 1.3 - Savoir ou est le depot

Toute la suite suppose que vous etes DANS le dossier du projet :

```powershell
cd C:\Users\user\Desktop\REPOS\PUBLIC\rk322x-device-tools
```

---

## 2 - Preparer la cle USB (10 min)

### Etape 2.1 - Construire le paquet tout neuf

```powershell
sh tools/build.sh
```

VOUS DEVEZ VOIR : `[build] OK` a la fin.

### Etape 2.2 - Copier 3 fichiers sur la cle

Branchez la cle, copiez a sa RACINE (pas dans un dossier) :

1. `dist\rk322x-tools_v17_XXXXXXXX.XXXX.dpk` (le plus recent)
2. `dist\rk322x-tools_v17_XXXXXXXX.XXXX.dpk.sha256`
3. `deploy.sh`

Ejectez proprement la cle. NE LA BRANCHEZ PAS encore a la box.

---

## 3 - Preparer la box apres un reset usine (10 min, telecommande)

La box doit etre ALLUMEE et affichee sur la TV.

### Etape 3.1 - Activer les options developpeur [P2]

ACTION : Parametres → A propos de → surlignez « numero de build » et
appuyez OK **7 fois de suite**.

VOUS DEVEZ VOIR : « Vous etes maintenant developpeur ! »

### Etape 3.2 - Activer le debogage USB [P3]

ACTION : Parametres → Options developpeur → activez **Debogage USB**.
Confirmez l'avertissement.

### Etape 3.3 - Donner une adresse fixe a la box [P4]

ACTION : Parametres → Reseau → Ethernet → Statique :

| Champ | Valeur |
|---|---|
| Adresse IP | 192.168.50.20 |
| Longueur prefixe / Masque | 24 / 255.255.255.0 |
| Passerelle | 192.168.50.1 |
| DNS | 8.8.8.8 |

NOTE : votre box internet doit etre sur le reseau 192.168.50.x. Si votre
box internet utilise autre chose (ex : 192.168.1.x), gardez le meme
principe mais adaptez : IP finissant par .20 dans VOTRE plage, passerelle
= adresse de VOTRE box internet (visible sur son etiquette).

---

## 4 - Brancher et verifier (5 min)

### Etape 4.1 - Cabler

1. Cle USB → port USB de la box
2. Cable USB donnees → PC <-> box
3. Ethernet deja branche

### Etape 4.2 - La box est-elle visible ? ([P5])

Dans PowerShell (dans le dossier du projet) :

```powershell
adb kill-server ; adb devices
```

VOUS DEVEZ VOIR : une ligne avec des caracteres + le mot `device`.

SI liste vide :
- debranchez/rebranchez le cable,
- sur la TV, une demande d'autorisation peut attendre votre OK (cochez
  « toujours autoriser »),
- sinon lancez `powershell -File admin\windows\identify_box.ps1` : il dit
  exactement ce qui manque (pilote, cable, debogage).

### Etape 4.3 - Carte d'identite complete (facultatif mais conseille)

```powershell
powershell -File admin\windows\identify_box.ps1 -Full
```

VOUS DEVEZ VOIR : modele, Android 7.1.2, IP 192.168.50.20, et si le kit
est deja installe l'inventaire complet des puces.

---

## 5 - Installer (20 min)

### Etape 5.1 - Entrer dans la box en tant qu'administrateur ([P6])

```powershell
adb shell
```

VOUS DEVEZ VOIR : l'invite change (ex : `shell@rk30board:/ $`).

Passez root :

```
su
```

VOUS DEVEZ VOIR : le `$` final devient `#`. Tapez `exit` plus tard pour sortir.

### Etape 5.2 - Verifier que la cle est vue ([P7])

toujours dans le shell de la box :

```
ls /mnt/media_rw/*/INSTALLER.sh
```

VOUS DEVEZ VOIR : le chemin affiche (pas de message « No such file »).

SI absent : attendez 30 s (la cle est lente sur ce socle), reessayez,
verifiez qu'elle tient bien 3 fichiers a sa racine (Etape 2.2).

### Etape 5.3 - Lancer l'installation ([I1])

toujours en root (`#`) sur la box :

```
sh /mnt/media_rw/*/INSTALLER.sh
```

Laissez-vous guider a l'ecran (revue de config, confirmations).

VOUS DEVEZ VOIR a la fin : bloc `[5] Demarrage automatique... [ OK ]`
puis `TERMINE`.

L'installation fait elle-meme un reboot de controle. Attendez 4 a 6 min
SANS toucher la telecommande.

### Etape 5.4 - Premier controle apres reboot

Sur le PC, navigateur : ouvrez `http://192.168.50.20:8000/`

VOUS DEVEZ VOIR : le panneau de la box (identifiants par defaut
`user` / `user`) avec des pastilles/badges verts.

C'est deja un systeme autonome : a chaque demarrage la box applique
seule ses optimisations.

---

## 6 - Finir la mise en route (30 min, conseille)

Le reste du parcours optimise et verifie tout, TOUJOURS depuis le shell
root de la box (`adb shell` puis `su`, Etape 5.1). Suivez alors
docs/STARTUP.md phase par phase ; dans l'ordre :

1. `thermal ECO` + `mem_tune OPTIMIZE` + `cut_services CUT` (phase 2bis)
2. `nreg` puis `selftest | tail -3` (phase 3 : tout doit etre PASS)
3. `inspect_all` puis `hw_report SAVE` (phase 4)
4. `manage web` (phase 5 : 3 ports LISTENING)
5. Tour complet du panneau web (phase 6)
6. `reboot` puis cafe (phase 7 : la box revient TOUTE SEULE, c'est LE test)

En cas de doute pendant une commande : ne chainez rien d'autre, notez le
message exact affiche, cherchez-le dans TROUBLESHOOTING.md.

---

## 7 - Problemes courants (version novice)

| Symptome | Cause probable | Action |
|---|---|---|
| `adb devices` vide | cable charge-only | changer de cable USB |
| boite de dialogue sur la TV | autorisation USB en attente | cocher « toujours » + OK |
| peripherique inconnu dans Windows | pilote manquant | installer « Google USB Driver » |
| cle non vue par la box | enumeration lente | patienter 30-60 s, retester |
| panneau inaccessible apres reboot | pile web pas montee | attendre 6 min ; puis `su -c 'sh /data/scripts/deploy.sh EXPOSE'` |
| IP 192.168.50.20 ne ping pas | reseau domestique different | revoir Etape 3.3 NOTE |
| tout semble casse | dernier recours | reset usine MXQ puis reprendre a l'Etape 2 |

---

*Document compagnon de docs/SETUP.md (version bench) et
docs/STARTUP.md (procedure de reference).*
