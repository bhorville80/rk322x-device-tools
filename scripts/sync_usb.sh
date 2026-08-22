#!/system/bin/sh
# sync_usb - synchronisation /data/scripts -> cle USB.
#
#   sync_usb            copie + validation post-copie (cmp) + resume
#   sync_usb STATUS     comparaison sans copie : identiques / divergents
#   sync_usb <chemin>   cible explicite (ex: /mnt/media_rw/F43F-A8F6)
#   sync_usb help

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

DATA_DIR="/data/scripts"

find_key()
{
    PREFER="$1"

    if [ -n "$PREFER" ]; then
        [ -d "$PREFER" ] && { KEY="$PREFER"; return 0; }
        return 1
    fi

    for d in /mnt/media_rw/*; do
        [ -d "$d" ] || continue
        if [ -f "$d/deploy.sh" ] && [ -d "$d/LOST.DIR" ]; then
            KEY="$d"
            return 0
        fi
    done

    for d in /mnt/media_rw/*; do
        [ -d "$d" ] || continue
        [ -f "$d/deploy.sh" ] && { KEY="$d"; return 0; }
    done

    return 1
}

same_file()
{
    # $1 source, $2 destination : identiques ?
    [ -f "$2" ] || return 1
    S1="$(wc -c < "$1" 2>/dev/null | tr -dc '0-9')"
    S2="$(wc -c < "$2" 2>/dev/null | tr -dc '0-9')"
    [ -n "$S1" ] && [ "$S1" = "$S2" ] || return 1
    cmp -s "$1" "$2"
}

list_files()
{
    # fichiers reguliers de $1, chemins relatifs
    for E in "$1"/*; do
        [ -e "$E" ] || continue
        case "$(basename "$E")" in *.log|VERSION|secrets.conf) continue ;; esac
        if [ -f "$E" ]; then
            printf '%s\n' "$(basename "$E")"
        elif [ -d "$E" ]; then
            find "$E" -type f 2>/dev/null | grep -v '/secrets\.conf$' | sed "s|^$1/||"
        fi
    done | sort -u
}

do_status()
{
    find_key "$KEY_ARG" || {
        echo "[ERREUR] aucune cle USB trouvee dans /mnt/media_rw/*"
        echo "         brancher la cle (ou : sync_usb STATUS /mnt/media_rw/<ID>)"
        return 1
    }

    DST="$KEY/scripts"
    echo ""
    echo "=== SYNC STATUS ==="
    echo "  source : $DATA_DIR"
    echo "  cle    : $DST"

    SAME=0; DIFF=0; MISS=0
    for F in $(list_files "$DATA_DIR"); do
        SRC="$DATA_DIR/$F"
        DSTF="$DST/$F"
        if same_file "$SRC" "$DSTF"; then
            SAME=$((SAME+1))
        elif [ -f "$DSTF" ]; then
            DIFF=$((DIFF+1))
            echo "  [DIFF] $F"
        else
            MISS=$((MISS+1))
            echo "  [ABSENT] $F"
        fi
    done

    echo ""
    printf '  identiques : %s   divergents : %s   absents : %s\n' \
        "$SAME" "$DIFF" "$MISS"
    case "$((DIFF + MISS))" in
        0) echo "[ OK ] cle a jour" ;;
        *) echo "[WARN] relancer : sync_usb" ;;
    esac
    echo ""
    return 0
}

do_sync()
{
    find_key "$KEY_ARG" || {
        echo "[ERREUR] aucune cle USB trouvee dans /mnt/media_rw/*"
        echo "         brancher la cle (ou : sync_usb /mnt/media_rw/<ID>)"
        return 1
    }
    DST="$KEY/scripts"
    mkdir -p "$DST"

    echo ""
    echo "=== SYNC DATA -> USB ==="
    echo "USB  : $KEY"
    echo "DATA : $DATA_DIR"
    echo "DEST : $DST"
    echo ""

    N=0; OKC=0; FAIL=0
    for f in "$DATA_DIR"/*; do
        [ -e "$f" ] || continue
        NAME="$(basename "$f")"
        case "$NAME" in VERSION|secrets.conf) continue ;; esac
        N=$((N+1))

        if cp -rf "$f" "$DST/" 2>/dev/null; then
            echo "[ OK ] $NAME"
            OKC=$((OKC+1))
        else
            echo "[ERREUR] $NAME"
            FAIL=1
        fi
    done

    [ "$N" -eq 0 ] && echo "[WARN] aucun fichier dans $DATA_DIR"

    echo ""
    echo "--- Validation post-copie ---"
    BAD=0
    for F in $(list_files "$DATA_DIR"); do
        if ! same_file "$DATA_DIR/$F" "$DST/$F"; then
            echo "  [KO] $F"
            BAD=$((BAD+1))
            FAIL=1
        fi
    done
    VERIFIED=$(($(list_files "$DATA_DIR" | grep -c .) - BAD))
    echo "  verifies identiques : $VERIFIED   ecarts : $BAD"

    SZ="$(du -sk "$DST" 2>/dev/null | tr -dc '0-9')"
    [ -n "$SZ" ] && echo "  taille cible        : $((SZ / 1024)) Mo"

    echo ""
    if [ "$FAIL" -eq 0 ]; then
        echo "[ OK ] Synchronisation terminee et validee ($N elements)"
        return 0
    fi
    echo "[ERREUR] Synchronisation terminee avec des ecarts"
    return 1
}

case "$1" in
    ""|sync)      KEY_ARG=""; do_sync ;;
    STATUS|status) KEY_ARG="$2"; do_status ;;
    HELP|help|-h|--help)
        sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
        ;;
    /mnt/media_rw/*)
        KEY_ARG="$1"; do_sync
        ;;
    *)
        echo "Usage: sync_usb [STATUS|/mnt/media_rw/<ID>|help]"
        exit 1
        ;;
esac
