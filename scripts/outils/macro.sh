#!/system/bin/sh
# macro - sequences nommees d'actions [Theme+numero] du registre xrun.
#
# Une macro = un fichier /data/etc/macros/<nom> contenant un ID par ligne
# (+ commentaires #). Chaque action est executee via xrun (trace exec
# individuelle conservee) et le bilan global porte le rc de la macro.
#
# Exemple : check-matin = sante systeme + reseau + config + vitals
#   macro NEW check-matin N8 N7 C1 O4
#   macro RUN  check-matin
#
# Usage:
#   macro                       ou LIST : macros connues + contenu resume
#   macro SHOW <nom>            contenu detaille (IDs resolves en libelles)
#   macro NEW <nom> <ID...>     cree une macro (REPLACE pour ecraser)
#   macro ADD <nom> <ID...>     ajoute des actions en fin de sequence
#   macro DEL <nom> <ID...>     retire des actions
#   macro RM <nom>              supprime la macro
#   macro RUN <nom>             execute toute la sequence + bilan
#   macro HELP                  cette aide

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" "$(dirname "$0")/.." /data/scripts; do
    [ -f "$B/core/runlog.sh" ] && { . "$B/core/runlog.sh"; RUNLOG_LOADED=1; break; }
done

MACROS_DIR="/data/etc/macros"

BASE="$(cd "$(dirname "$0")" && pwd)"
TABLE="$BASE/core/actions.tsv"
[ -f "$TABLE" ] || TABLE="$BASE/../core/actions.tsv"
[ -f "$TABLE" ] || TABLE="/data/scripts/core/actions.tsv"

XRUN=""
for C in "$BASE/xrun.sh" "$BASE/../outils/xrun.sh" /data/scripts/xrun.sh; do
    [ -f "$C" ] && { XRUN="$C" ; break ; }
done

ok_ko() { printf '  [%s] %s\n' "$1" "$2" ; }

valid_name()
{
    N="$1"
    case "$N" in ""|.|..|-*|*[!a-zA-Z0-9_.-]*) return 1 ;; esac
    return 0
}

id_exists()
{
    [ -r "$TABLE" ] || return 0   # registre absent -> ne pas bloquer ici
    awk -F'\t' -v id="$(printf '%s' "$1" | tr 'a-z' 'A-Z')" \
        '!/^#/ && $1==id { found=1 ; exit } END { exit !found }' "$TABLE"
}

macro_file()
{
    printf '%s/%s\n' "$MACROS_DIR" "$1"
}

cmd_list()
{
    echo ""
    echo "=== MACROS ($MACROS_DIR) ==="
    if [ ! -d "$MACROS_DIR" ]; then
        echo "  (aucune - macro NEW <nom> <ID...>)"
        echo ""
        return 0
    fi
    FOUND=0
    for F in "$MACROS_DIR"/*; do
        [ -f "$F" ] || continue
        FOUND=1
        N="$(basename "$F")"
        NB_="$(grep -cv '^[[:space:]]*#' "$F" 2>/dev/null)"
        printf '  %-16s %s action(s)\n' "$N" "${NB_:-?}"
    done
    [ "$FOUND" -eq 1 ] || echo "  (aucune - macro NEW <nom> <ID...>)"
    echo ""
    return 0
}

cmd_show()
{
    valid_name "$1" || { echo "[ERREUR] nom invalide : '$1'" ; return 1 ; }
    F="$(macro_file "$1")"
    [ -f "$F" ] || { echo "[ERREUR] macro inconnue : $1 (macro LIST)" ; return 1 ; }
    echo ""
    echo "=== MACRO $1 ==="
    NL=0
    while IFS= read -r L_; do
        case "$L_" in ''|\#*) echo "  $L_" ; continue ;; esac
        NL=$((NL+1))
        LBL="$(awk -F'\t' -v id="$L_" '!/^#/ && $1==id {print $2 ; exit}' "$TABLE" 2>/dev/null)"
        printf '  %2d) %-8s %s\n' "$NL" "$L_" "${LBL:-[inconnu]}"
    done < "$F"
    echo ""
    return 0
}

check_ids()
{
    for ID_ in "$@"; do
        if ! id_exists "$ID_"; then
            ok_ko KO "action inconnue au registre : $ID_ (voir xrun LIST)"
            return 1
        fi
    done
    return 0
}

cmd_new()
{
    NAME="$1" ; shift
    valid_name "$NAME" || { echo "[ERREUR] nom invalide : '$NAME' (a-z A-Z 0-9 _ . -)" ; return 1 ; }
    REPLACE=""
    while [ "$1" = "REPLACE" ] || [ "$1" = "replace" ]; do
        REPLACE=1 ; shift
    done
    [ -n "$1" ] || { echo "[ERREUR] au moins un ID requis : macro NEW $NAME <ID...>" ; return 1 ; }
    check_ids "$@" || return 1
    mkdir -p "$MACROS_DIR" 2>/dev/null || { echo "[ERREUR] mkdir $MACROS_DIR impossible" ; return 1 ; }
    F="$(macro_file "$NAME")"
    if [ -f "$F" ] && [ -z "$REPLACE" ]; then
        echo "[ERREUR] existe deja : $F (macro NEW $NAME ... REPLACE pour ecraser)"
        return 1
    fi
    {
        echo "# macro '$NAME' - creee $(date '+%Y-%m-%d %H:%M:%S')"
        for A in "$@"; do printf '%s\n' "$(printf '%s' "$A" | tr 'a-z' 'A-Z')" ; done
    } > "$F" || { echo "[ERREUR] ecriture $F impossible" ; return 1 ; }
    ok_ko OK "macro creee : $NAME ($(grep -cv '^#' "$F") actions)"
    cmd_show "$NAME"
    return 0
}

cmd_add_del()
{
    OP="$1" ; NAME="$2" ; shift 2
    valid_name "$NAME" || { echo "[ERREUR] nom invalide : '$NAME'" ; return 1 ; }
    F="$(macro_file "$NAME")"
    [ -f "$F" ] || { echo "[ERREUR] macro inconnue : $NAME (macro LIST)" ; return 1 ; }
    [ -n "$1" ] || { echo "[ERREUR] au moins un ID requis : macro $OP $NAME <ID...>" ; return 1 ; }
    check_ids "$@" || return 1
    TMP="${F}.tmp.$$"
    case "$OP" in
        ADD)
            cp "$F" "$TMP" || return 1
            for A in "$@"; do
                printf '%s\n' "$(printf '%s' "$A" | tr 'a-z' 'A-Z')" >> "$TMP"
            done
            ;;
        DEL)
            for A in "$@"; do
                AI="$(printf '%s' "$A" | tr 'a-z' 'A-Z')"
                grep -v "^${AI}[[:space:]]*\$" "$F" > "$TMP" || true
                mv -f "$TMP" "$F"
            done
            rm -f "$TMP"
            ok_ko OK "retire$( [ $# -gt 1 ] && echo s ) : $*"
            cmd_show "$NAME"
            return 0
            ;;
    esac
    mv -f "$TMP" "$F" || { rm -f "$TMP" ; echo "[ERREUR] maj $F impossible" ; return 1 ; }
    ok_ko OK "macro mise a jour : $NAME"
    cmd_show "$NAME"
    return 0
}

cmd_rm()
{
    valid_name "$1" || { echo "[ERREUR] nom invalide : '$1'" ; return 1 ; }
    F="$(macro_file "$1")"
    [ -f "$F" ] || { echo "[ERREUR] macro inconnue : $1" ; return 1 ; }
    rm -f "$F" && ok_ko OK "macro supprimee : $1"
}

cmd_run()
{
    valid_name "$1" || { echo "[ERREUR] nom invalide : '$1'" ; return 1 ; }
    F="$(macro_file "$1")"
    [ -f "$F" ] || { echo "[ERREUR] macro inconnue : $1 (macro LIST)" ; return 1 ; }
    [ -n "$XRUN" ] || { echo "[ERREUR] xrun.sh introuvable (deploy INSTALL)" ; return 127 ; }
    RC_ALL=0 ; OKN=0 ; KON=0
    while IFS= read -r L_; do
        case "$L_" in ''|\#*) continue ;; esac
        if sh "$XRUN" "$L_"; then
            OKN=$((OKN+1))
        else
            KON=$((KON+1)) ; RC_ALL=1
        fi
    done < "$F"
    echo ""
    if [ "$KON" -eq 0 ]; then
        echo "=== MACRO '$1' : $OKN/$OKN OK ==="
    else
        echo "=== MACRO '$1' : $OKN OK, $KON KO ==="
    fi
    return $RC_ALL
}

usage()
{
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

main()
{
    case "$1" in
        ""|LIST|list)    cmd_list ;;
        SHOW|show)       shift ; cmd_show "$@" ;;
        NEW|new)         shift ; cmd_new "$@" ;;
        ADD|add)         shift ; cmd_add_del ADD "$@" ;;
        DEL|del)         shift ; cmd_add_del DEL "$@" ;;
        RM|rm|REMOVE)    shift ; cmd_rm "$@" ;;
        RUN|run)         shift ; cmd_run "$@" ;;
        HELP|-h|--help)  usage ;;
        *)               echo "option inconnue : $1 (voir macro HELP)" ; return 1 ;;
    esac
}

if [ "$RUNLOG_LOADED" -eq 1 ] && runlog_start "$SCRIPT_ID"; then
    main "$@" >> "$RUNLOG_FILE" 2>&1 ; RC=$?
    runlog_end "$RC" ; cat "$RUNLOG_FILE"
else
    main "$@" ; RC=$?
fi
exit "$RC"
