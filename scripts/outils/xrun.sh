#!/system/bin/sh
# xrun - lance des actions par leur identifiant [Theme+numero].
#
# Source de verite : scripts/core/actions.tsv (ID | libelle | commande).
# %BASE% dans la commande est remplace par le repertoire des scripts.
#
# Usage:
#   xrun                ou LIST : toutes les actions (ID, libelle, cible)
#   xrun <ID>           execute l'action (ex : xrun C1, xrun S2)
#   xrun <ID> <ID>...   mode serie : les actions dans l'ordre + bilan
#                       (ex : xrun N8 N7 O4)
#   xrun FIND <motif>   recherche insensible a la casse dans libelles+cibles
#   xrun HELP           cette aide
#
# Themes : P Prepa | I Install | C Config | O Optim | R Re-check
#          N iNspection | S Serveur | M Metriques | W Web IHM | B Boot

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" "$(dirname "$0")/.." /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

BASE="$(cd "$(dirname "$0")" && pwd)"
TABLE="$BASE/core/actions.tsv"
[ -f "$TABLE" ] || TABLE="$BASE/../core/actions.tsv"
[ -f "$TABLE" ] || TABLE="/data/scripts/core/actions.tsv"

resolve()
{
    # $1 = ID (insensible a la casse) -> globals X_LABEL / X_CMD
    ID_="$(printf '%s' "$1" | tr 'a-z' 'A-Z')"
    LINE_="$(awk -F'\t' -v id="$ID_" '!/^#/ && $1==id{print;exit}' "$TABLE" 2>/dev/null)"
    if [ -z "$LINE_" ]; then
        X_LABEL="" ; X_CMD=""
        return 1
    fi
    X_LABEL="$(printf '%s' "$LINE_" | cut -f2)"
    X_CMD="$(printf '%s' "$LINE_" | cut -f3-)"
    return 0
}

do_list()
{
    echo ""
    echo "=== ACTIONS [Theme+numero] ==="
    awk -F'\t' '!/^#/ && NF>=3 {printf "  %-5s %-45s %s\n", $1, $2, $3}' "$TABLE"
    echo ""
}

do_find()
{
    M="$1"
    if [ -z "$M" ]; then
        echo "[ERREUR] usage : xrun FIND <motif>"
        return 1
    fi
    echo ""
    echo "=== ACTIONS contenant '$M' ==="
    awk -F'\t' -v m="$M" \
        '!/^#/ && NF>=3 && index(tolower($0), tolower(m)) {printf "  %-5s %-45s %s\n", $1, $2, $3 ; n++ }
         END { if (!n) print "  (aucun resultat)" }' "$TABLE"
    echo ""
    return 0
}

usage()
{
    echo ""
    echo "Usage: xrun [<ID>|LIST|FIND <motif>|<ID> <ID>...]"
    echo "  ex : xrun C1   xrun N8 N7 O4 (serie + bilan)   xrun FIND reseau"
    echo "  registre : $TABLE"
    echo ""
    return 0
}

run_one()
{
    resolve "$1" || {
        echo "[KO] action inconnue : $1 (voir : xrun LIST)"
        return 1
    }

    case "$X_CMD" in
        -)
            echo "[i] '$X_LABEL' est une action cote PC / navigateur (non executable ici)"
            return 0 ;;
    esac

    CMD="$(printf '%s' "$X_CMD" | sed "s|%BASE%|$BASE|g")"

    # repli de chemin mot a mot : un chemin sous BASE inexistant est
    # reecrit vers le niveau superieur (layout depot a plat), puis vers
    # les dossiers de theme (layout depot thematise) ; inversement
    # /data/scripts/... -> BASE (box)
    NEW=""
    for W_ in $CMD; do
        case "$W_" in
            "$BASE"/*)
                if [ ! -f "$W_" ]; then
                    REST_="${W_#"$BASE"/}"
                    A_="$(dirname "$BASE")/$REST_"
                    if [ ! -f "$A_" ]; then
                        for C_ in "$(dirname "$BASE")"/*/"$REST_"; do
                            [ -f "$C_" ] && { A_="$C_"; break; }
                        done
                    fi
                    [ -f "$A_" ] && W_="$A_"
                fi ;;
            /data/scripts/*)
                if [ ! -f "$W_" ]; then
                    REST_="${W_#"/data/scripts/"}"
                    A_="$BASE/$REST_"
                    if [ ! -f "$A_" ]; then
                        for C_ in "$BASE"/../*/"$REST_"; do
                            [ -f "$C_" ] && { A_="$C_"; break; }
                        done
                    fi
                    [ -f "$A_" ] && W_="$A_"
                fi ;;
        esac
        NEW="$NEW${NEW:+ }$W_"
    done
    CMD="$NEW"

    echo "[xrun] [$1] $X_LABEL"
    echo "       \$ $CMD"
    sh -c "$CMD"
    return $?
}

main()
{
    [ -r "$TABLE" ] || { echo "[ERREUR] registre introuvable : $TABLE" ; return 1 ; }

    case "$1" in
        ""|LIST|list)  do_list ; return 0 ;;
        HELP|-h|--help) usage ; return 0 ;;
        FIND|find)     shift ; do_find "$@" ; return $? ;;
    esac

    # un ou plusieurs IDs -> mode serie avec bilan
    RC_ALL=0 ; OKN=0 ; KON=0 ; KOLIST=""
    for A_ in "$@"; do
        echo ""
        echo "----------------------------------------"
        if run_one "$A_"; then
            OKN=$((OKN+1))
        else
            RC_ALL=1 ; KON=$((KON+1)) ; KOLIST="$KOLIST $A_"
        fi
    done
    echo ""
    if [ "$KON" -eq 0 ]; then
        echo "=== BILAN SERIE : $OKN/$OKN OK ==="
    else
        echo "=== BILAN SERIE : $OKN OK, $KON KO ($KOLIST ) ==="
    fi
    return $RC_ALL
}

if [ "$RUNLOG_LOADED" -eq 1 ] && runlog_start "$SCRIPT_ID"; then
    main "$@" >> "$RUNLOG_FILE" 2>&1
    RC=$?
    runlog_end "$RC"
    cat "$RUNLOG_FILE"
else
    main "$@"
    RC=$?
fi
exit "$RC"
