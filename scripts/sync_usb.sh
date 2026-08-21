#!/system/bin/sh

DATA_DIR="/data/scripts"
USB_BASE="/mnt/media_rw"

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

main()
{
    USB=""

    for d in "$USB_BASE"/*; do
        if [ -d "$d" ] && [ -d "$d/LOST.DIR" ]; then
            USB="$d"
            break
        fi
    done

    if [ -z "$USB" ]; then
        echo "[ERREUR] aucune clé USB trouvée"
        return 1
    fi

    USB_DIR="$USB/scripts"

    mkdir -p "$USB_DIR"

    echo ""
    echo "=== SYNC DATA -> USB ==="
    echo "USB  : $USB"
    echo "DATA : $DATA_DIR"
    echo "DEST : $USB_DIR"
    echo ""

    FAIL=0
    N=0

    for f in "$DATA_DIR"/*; do
        [ -e "$f" ] || continue

        NAME="$(basename "$f")"
        N=$((N+1))

        if cp -rf "$f" "$USB_DIR/" 2>/dev/null; then
            echo "[ OK ] $NAME"
        else
            echo "[ERREUR] $NAME"
            FAIL=1
        fi
    done

    if [ "$N" -eq 0 ]; then
        echo "[WARN] aucun fichier dans $DATA_DIR"
    fi

    echo ""
    if [ "$FAIL" -eq 0 ]; then
        echo "[ OK ] Synchronisation terminée ($N éléments)"
        return 0
    fi
    echo "[ERREUR] Synchronisation terminée avec erreurs"
    return 1
}

if [ "$RUNLOG_LOADED" -eq 1 ] && runlog_start "$SCRIPT_ID"; then
    main >> "$RUNLOG_FILE" 2>&1
    RC=$?
    runlog_end "$RC"
    cat "$RUNLOG_FILE"
else
    main
    RC=$?
fi

exit "$RC"
