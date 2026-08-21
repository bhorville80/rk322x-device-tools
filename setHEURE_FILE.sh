#!/system/bin/sh

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

USB_DIR="/mnt/media_rw/4E28-7C59"
TIME_FILE="$USB_DIR/SET_HEURE"

if [ ! -f "$TIME_FILE" ]; then
    echo "ERREUR: fichier $TIME_FILE absent"
    exit 1
fi

TIME="$(cat "$TIME_FILE" | tr -d '[:space:]')"

if [ -z "$TIME" ]; then
    echo "ERREUR: fichier SET_HEURE vide"
    exit 1
fi

echo "Heure actuelle :"
date

echo "Heure demandée : $TIME"

date "$TIME"

echo "Heure après réglage :"
date
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

