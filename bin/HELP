#!/system/bin/sh

INCOMING=""
for d in /mnt/media_rw/*; do
    if [ -f "$d/deploy.sh" ]; then
        INCOMING="$d/incoming"
        break
    fi
done

if [ -z "$INCOMING" ]; then
    echo "[ERREUR] cle USB introuvable"
    exit 1
fi

mkdir -p "$INCOMING"
touch "$INCOMING/HELP"
exit 0
