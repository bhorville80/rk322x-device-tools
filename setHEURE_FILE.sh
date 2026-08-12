#!/system/bin/sh

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

su -c "date $TIME"

echo "Heure après réglage :"
date
