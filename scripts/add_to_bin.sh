#!/system/bin/sh

BIN_DIR="/data/bin"

if [ -z "$1" ]; then
    echo "Usage: add_to_bin <script>"
    exit 1
fi

SCRIPT="$1"

if [ ! -f "$SCRIPT" ]; then
    echo "ERREUR: fichier introuvable: $SCRIPT"
    exit 1
fi

mkdir -p "$BIN_DIR"

NAME="$(basename "$SCRIPT")"

case "$NAME" in
    *.sh)
        NAME="${NAME%.sh}"
        ;;
esac

ln -sf "$SCRIPT" "$BIN_DIR/$NAME"

echo "OK: $NAME ajouté à /data/bin"
echo "Commande: $NAME"

exit 0
