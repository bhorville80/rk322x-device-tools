# CODING - Regles et patterns obligatoires

> A CONSULTER avant toute creation/modification de fichier de code.
> Chaque regle ici vient d'un bug reellement rencontre dans ce depot.

## 1. Dialecte shell : POSIX strict, execute par mksh (Android)

INTERDIT (mksh/box casse ou portable non garanti) :

| Interdit | Remplacement |
|---|---|
| `[[ ... ]]` | `[ ... ]` avec case pour motifs |
| `<<<` herestring | `printf '%s' x \| commande` |
| `function f()` | `f() { ... }` |
| tableaux, `${a//x/y}` global | boucle / sed |
| `$'...'`, `local` hors mksh-sur | variables normales |
| `echo -e`, `grep -P` | printf formats, awk |

Balayage de vigilance avant commit :
```bash
grep -rnE '\[\[|<<<|function [a-z_]+\(|\$\{[a-zA-Z_]+\[' scripts server
```

## 2. Fins de ligne : LF uniquement

`.gitattributes` impose LF ; le paquet REJETE tout CRLF
(`pack` gate). Ecrire les fichiers avec newline='\n'.

## 3. Squelette standard d'un outil (scripts/X.sh)

```sh
#!/system/bin/sh
SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" /data/scripts; do
    [ -f "$B/core/runlog.sh" ] && { . "$B/core/runlog.sh"; RUNLOG_LOADED=1; break; }
done

# librairie config : UNIQUEMENT core/config.sh
# (NE JAMAIS sourcer "$(dirname)/config.sh" : c'est l'outil interactif !)
for B in "$(dirname "$0")/core" /data/scripts/core; do
    [ -f "$B/config.sh" ] && { . "$B/config.sh"; break; }
done

BASE="$(cd "$(dirname "$0")" && pwd)"
# ... fonctions ...
case "$1" in HELP|-h) aide ; exit 0 ;; esac

if [ "$RUNLOG_LOADED" -eq 1 ] && runlog_start "$SCRIPT_ID"; then
    main "$@" >> "$RUNLOG_FILE" 2>&1 ; RC=$?
    runlog_end "$RC" ; cat "$RUNLOG_FILE"
else
    main "$@" ; RC=$?
fi
exit "$RC"
```

## 4. Repli explicite (pattern "fallback chaine")

Tout mecanisme optionnel suit : essai -> si echec, message LOG clair ->
repli eprouve. Jamais d'echec silencieux.
Exemple type : control_server = tcpsvd factory -> log REPLI -> fifo_loop.

## 5. Garde-fou serveur (equivalent try/catch)

Tout handler requete passe par un dispatch garde :
```sh
req_dispatch || { log "DISPATCH ERROR rc=$?" ;
                 reply 500 "Internal Server Error" '{...erreur interne...}' ; }
```

## 6. HTTP reponses

- Content-Length TOUJOURS en octets : `LEN=$(printf '%s' "$BODY" | wc -c)`
- CORS `Access-Control-Allow-Origin: *` sur TOUTES les reponses
- Corps binaires : JAMAIS via variable shell (NUL perdus) ->
  dd deux-phases (bs=4096 puis bs=1 du reste), tail -c +offset
- Endpoints sensibles : double garde (flag conf + token)

## 7. Chemins portables

- Ne jamais coder en dur l'ID de cle : boucler /mnt/media_rw/*
- Registre d'actions : `%BASE%` resolu par xrun, qui reecrit mot a mot
  les chemins manquants (BASE <-> parent, /data/scripts <-> BASE)
- Fichiers temporaires : /data/local/tmp (+$$ si concurrence possible)

## 8. Ajouter une cle de configuration (checklist)

1. device.conf : cle + commentaire explicite + valeur par defaut sure
2. conf_check : whitelist valeur autorisee + liste "cles connues"
3. Si flag BOOT_* : ajouter au NONE-check et STATUS de boot.sh
4. Si lu par un serveur : prevoir le chemin /data/scripts ET la cle

## 9. Nouvel outil : checklist de livraison (10 points)

1. scripts/X.sh (squelette §3, HELP accessible sans root)
2. deploy.sh : INSTALL_LIST += X
3. scripts/aliases.sh : tool_list += X
4. selftest : check_rc "X HELP" (+ LIST/STATUS si pertinent)
5. scripts/help.sh : entree une ligne lisible
6. docs/TOOLS.md : ligne catalogue dans le bon theme
7. docs/actions.tsv (scripts/core/) : si action lancable -> ID [Xnn]
8. docs/IHM.md : si visible depuis le panneau
9. menu.sh : sujet/action si interactif
10. tools/build.sh vert (gate CRLF + verify dpk)

## 10. Convention d'identification

[Xnn] : X = theme (P I C O R N S W B), nn = numero (99 slots/theme).
Registre : scripts/core/actions.tsv (source unique). Toute nouvelle
action executables y est ajoutee ; les actions PC/navigateur ont "-".

## 11. Tests minimum avant commit

```bash
tools/check.sh          # sh -n tous les scripts
node check JS des pages # syntaxe des <script> html
tools/build.sh          # gate CRLF + verify dpk + rotation dist
smoke xrun              # xrun LIST + une action sure (ex : xrun N8)
```

## 12. Style commits/messages

Francais, descriptif, semicolons entre sujets : "Sujet : detail ; detail".
Un commit = un axe coherent (fix, feature, docs...).
