#!/system/bin/sh

USB="/mnt/media_rw/4E28-7C59"

if [ ! -d "$USB" ]; then
    echo "ERREUR: clé USB non trouvée: $USB"
    exit 1
fi

if [ -z "$1" ]; then
    echo "Usage: $0 /chemin/du/script"
    exit 1
fi

SCRIPT="$1"

if [ ! -f "$SCRIPT" ]; then
    echo "ERREUR: script introuvable: $SCRIPT"
    exit 1
fi

NAME="$(basename "$SCRIPT")"

cp "$SCRIPT" "$USB/$NAME"

if [ $? -ne 0 ]; then
    echo "ERREUR: copie impossible"
    exit 1
fi

chmod 755 "$USB/$NAME"

echo "OK: $NAME copié sur la clé USB"
echo "Destination: $USB/$NAME"

exit 0
