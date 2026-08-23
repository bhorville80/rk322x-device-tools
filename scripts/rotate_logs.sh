#!/system/bin/sh
# rotate_logs - rotation / purge des logs de la cle USB
#
#   - fichiers *.log actifs (racine cle + log/)      : rotation si > 512 Ko
#     (copy-truncate : les daemons gardent leur fd sur le fichier tronque)
#   - log/exec/<script>_<TS>.log                     : garde les KEEP derniers
#   - log/log_<TS>/ (collections SEND_LOGS)          : garde les 3 derniers
#   - manifests/history/*.manifest                   : garde les 10 derniers
#
# Usage: rotate_logs.sh [KEEP]

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

find_usb()
{
    for d in /mnt/media_rw/*; do
        [ -d "$d" ] || continue
        [ -f "$d/deploy.sh" ] || continue
        USB="$d"
        return 0
    done
    return 1
}

KEEP="${1:-5}"
MAX_BYTES=$((512 * 1024))

rotate_one()
{
    F="$1"
    [ -f "$F" ] || return 0
    S="$(wc -c < "$F" 2>/dev/null)"
    case "$S" in ''|*[!0-9]*) return 0 ;; esac
    [ "$S" -lt "$MAX_BYTES" ] && return 0

    I=$KEEP
    while [ "$I" -gt 1 ]; do
        [ -f "$F.$((I-1))" ] && cp -f "$F.$((I-1))" "$F.$I" 2>/dev/null
        I=$((I-1))
    done
    cp -f "$F" "$F.1" 2>/dev/null
    : > "$F" 2>/dev/null
    echo "  rotation : $(basename "$F") (${S} octets)"
    return 0
}

prune_keep()
{
    # prune_keep <motif> <keep>
    LIST="$(ls -1d "$1" 2>/dev/null | sort)"
    [ -z "$LIST" ] && return 0
    TOTAL="$(printf '%s\n' "$LIST" | wc -l)"
    [ "$TOTAL" -le "$2" ] && return 0
    DEL=$((TOTAL - $2))
    printf '%s\n' "$LIST" | head -n "$DEL" | while IFS= read -r P; do
        rm -rf "$P" 2>/dev/null
        echo "  purge    : $(basename "$P")"
    done
    return 0
}

main()
{
    echo ""
    echo "=== ROTATION DES LOGS ==="

    if ! find_usb; then
        echo "[ERREUR] aucune cle USB trouvee"
        return 1
    fi
    echo "cle : $USB"

    for L in "$USB"/*.log "$USB/log"/*.log; do
        rotate_one "$L"
    done

    echo "--- exec (keep $KEEP) ---"
    prune_keep "$USB/log/exec/*.log" "$KEEP"

    echo "--- collections SEND_LOGS (keep 3) ---"
    prune_keep "$USB/log/log_*" 3

    echo "--- manifests history (keep 10) ---"
    prune_keep "$USB/manifests/history/*.manifest" 10

    # purge par AGE : rapports et captures au-dela de AGE_DAYS jours
    # (rampre, hardware, stress_ram, ram_steps, gui_shots...)
    AGE_DAYS="${AGE_DAYS:-14}"
    if [ "$AGE_DAYS" -gt 0 ] 2>/dev/null && command -v find > /dev/null 2>&1; then
        echo "--- purge par age (>${AGE_DAYS}j) ---"
        find "$USB/log" -type f \( -name 'rampre_*' -o -name 'hardware_*' \
            -o -name 'stress_ram_*' -o -name 'ram_steps_*' \) -mtime +"$AGE_DAYS" \
            -exec rm -f {} \; 2>/dev/null
        find "$USB/log/gui_shots" -type f -mtime +"$AGE_DAYS" -exec rm -f {} \; 2>/dev/null
        echo "  [ OK ] purge d'age appliquee"
    fi

    echo ""
    echo "=== TERMINE ==="
    return 0
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
