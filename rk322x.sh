#!/bin/sh
# rk322x.sh - point d'entree unique des outils du depot (niveau deploy.sh)
#
# Le depot est organise par themes (scripts/<theme>/*.sh) ; ce parent
# resout l'emplacement pour vous :
#
#   ./rk322x.sh <outil> [args...]    trouve le theme et execute
#       ex : ./rk322x.sh mem_tune STATUS
#            ./rk322x.sh device_info
#   ./rk322x.sh <ID>                 action [Theme+numero] via xrun
#       ex : ./rk322x.sh N8          (registre : scripts/core/actions.tsv)
#   ./rk322x.sh LIST                 inventaire des themes et outils
#   ./rk322x.sh HELP                 cette aide
#
# Themes : boot demarrage | optim memoire/thermie | inspect diagnostics |
#          frontal afficheur/IR | outils administration transversale.
# Note PC : beaucoup d'outils visent la box (mksh/Android) ; hors box ils
# degradent proprement (pattern repli explicite). Cote box, utiliser
# directement /data/scripts/<outil>.sh ou les aliases /data/bin.

set -- "${1:-HELP}"

THEMES="boot optim inspect frontal outils"

say()  { echo "[rk322x] $*"; }
die()  { echo "[ERREUR rk322x] $*" >&2; exit 1; }

REPO="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$REPO/scripts"

do_list()
{
    echo ""
    echo "=== OUTILS PAR THEME ==="
    for T in $THEMES; do
        D="$SCRIPTS/$T"
        [ -d "$D" ] || continue
        echo ""
        printf -- "--- %s ---\n" "$T"
        for F in "$D"/*.sh; do
            [ -f "$F" ] || continue
            B="$(basename "$F" .sh)"
            DESC="$(sed -n '2{s/^# \{0,1\}//;p;q;}' "$F" 2>/dev/null)"
            printf '  %-16s %s\n' "$B" "${DESC:-}"
        done
    done
    echo ""
    echo "Actions balisees [Theme+numero] : ./rk322x.sh LIST-ID"
    echo "(ou ./rk322x.sh xrun LIST)"
}

find_tool()
{
    # $1 = nom sans .sh -> chemin complet ou rien
    T_="$1"
    for T_DIR in $THEMES core; do
        [ -f "$SCRIPTS/$T_DIR/$T_.sh" ] && { echo "$SCRIPTS/$T_DIR/$T_.sh"; return 0; }
    done
    return 1
}

case "$1" in
    HELP|-h|--help|help|"")
        sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
        exit 0 ;;
    LIST|list)
        do_list ; exit 0 ;;
    LIST-ID|ids)
        exec sh "$SCRIPTS/outils/xrun.sh" LIST ;;
esac

case "$1" in
    *[!0-9]*[0-9]|[A-Z])
        # motif ID [Lettre+chiffres] (ex N8, O4b, C1) -> delegue a xrun
        case "$1" in
            *[!A-Za-z0-9b]*) ;;   # caractere etranger : ce n'est pas un ID
            *)
                ID_UP="$(printf '%s' "$1" | tr 'a-z' 'A-Z')"
                case "$ID_UP" in
                    [A-Z][0-9]*|[A-Z])
                        say "action [$ID_UP] via xrun"
                        exec sh "$SCRIPTS/outils/xrun.sh" "$ID_UP" ;;
                esac ;;
        esac ;;
esac

TOOL_PATH="$(find_tool "$1")" \
    || die "outil '$1' introuvable dans les themes ($THEMES). Voir : ./rk322x.sh LIST"

shift
exec sh "$TOOL_PATH" "$@"
