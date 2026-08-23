#!/system/bin/sh
# xrun - lance une action par son identifiant [Theme+numero].
#
# Source de verite : scripts/core/actions.tsv (ID | libelle | commande).
# %BASE% dans la commande est remplace par le repertoire des scripts.
#
# Usage:
#   xrun                ou LIST : toutes les actions (ID, libelle, cible)
#   xrun <ID>           execute l'action (ex : xrun C1, xrun S2)
#   xrun HELP           cette aide
#
# Themes : P Prepa | I Install | C Config | O Optim | R Re-check
#          N iNspection | S Serveur | M Metriques | W Web IHM | B Boot

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

BASE="$(cd "$(dirname "$0")" && pwd)"
TABLE="$BASE/core/actions.tsv"
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

main()
{
    [ -r "$TABLE" ] || { echo "[ERREUR] registre introuvable : $TABLE" ; return 1 ; }

    case "$1" in
        ""|LIST|list) do_list ; return 0 ;;
        HELP|-h|--help)
            echo ""
            echo "Usage: xrun [<ID>|LIST]"
            echo "  ex : xrun C1   xrun S2   xrun LIST"
            echo "  registre : $TABLE"
            echo ""
            return 0 ;;
    esac

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
    # reecrit vers le niveau superieur (layout depot cote PC), et
    # inversement /data/scripts/... -> BASE (box)
    NEW=""
    for W_ in $CMD; do
        case "$W_" in
            "$BASE"/*)
                [ -f "$W_" ] || { A_="$(dirname "$BASE")/${W_#"$BASE"/}"
                                 [ -f "$A_" ] && W_="$A_" ; } ;;
            /data/scripts/*)
                [ -f "$W_" ] || { A_="$BASE/${W_#"/data/scripts/"}"
                                 [ -f "$A_" ] && W_="$A_" ; } ;;
        esac
        NEW="$NEW${NEW:+ }$W_"
    done
    CMD="$NEW"

    echo "[xrun] [$1] $X_LABEL"
    echo "       \$ $CMD"
    sh -c "$CMD"
    return $?
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
