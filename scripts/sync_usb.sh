#!/system/bin/sh

DATA_DIR="/data/scripts"
USB_BASE="/mnt/media_rw"

USB=""

for d in "$USB_BASE"/*; do
    if [ -d "$d" ] && [ -d "$d/LOST.DIR" ]; then
        USB="$d"
        break
    fi
done

if [ -z "$USB" ]; then
    echo "ERREUR: aucune clé USB trouvée"
    exit 1
fi

USB_DIR="$USB/scripts"

mkdir -p "$USB_DIR"

echo "USB : $USB"
echo "DATA: $DATA_DIR"
echo "SYNC: $USB_DIR"

cp -rf "$DATA_DIR"/* "$USB_DIR/" 2>/dev/null

echo "Synchronisation DATA -> USB terminée."

exit 0
