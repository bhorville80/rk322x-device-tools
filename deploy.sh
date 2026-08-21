#!/system/bin/sh

SCRIPTS_DIR="/data/scripts"
BIN_DIR="/data/bin"

INSTALL_LIST="sync_usb disable_wireless boxhelp media inspect_user inspect_system inspect_services hdmi check_state help"

find_usb()
{
    for d in /mnt/media_rw/*; do
        [ -d "$d" ] || continue
        [ -f "$d/deploy.sh" ] || continue
        USB_DIR="$d"
        return 0
    done
    return 1
}

require_usb()
{
    if find_usb; then
        echo "Cle : $USB_DIR"
    else
        echo "[ERREUR] aucune cle USB contenant deploy.sh trouvee"
        exit 1
    fi
}

do_install()
{
    echo ""
    echo "=== RK322X INSTALL ==="
    require_usb

    mkdir -p "$SCRIPTS_DIR/core" "$BIN_DIR"

    echo ""
    echo "[1] Copie des scripts..."
    if cp -f "$USB_DIR"/scripts/*.sh "$SCRIPTS_DIR/" 2>/dev/null; then
        echo "    [ OK ] $SCRIPTS_DIR"
    else
        echo "    [ ERREUR ] $SCRIPTS_DIR"
    fi
    if cp -f "$USB_DIR"/scripts/core/*.sh "$SCRIPTS_DIR/core/" 2>/dev/null; then
        echo "    [ OK ] $SCRIPTS_DIR/core"
    else
        echo "    [ ERREUR ] $SCRIPTS_DIR/core"
    fi

    echo "[2] Copie de deploy.sh..."
    if cp -f "$USB_DIR/deploy.sh" "$SCRIPTS_DIR/deploy.sh"; then
        echo "    [ OK ] $SCRIPTS_DIR/deploy.sh"
    else
        echo "    [ ERREUR ] $SCRIPTS_DIR/deploy.sh"
    fi

    echo "[3] Commandes dans $BIN_DIR..."
    for NAME in deploy $INSTALL_LIST; do
        if [ -f "$SCRIPTS_DIR/$NAME.sh" ]; then
            TARGET="$SCRIPTS_DIR/$NAME.sh"
        elif [ -f "$SCRIPTS_DIR/core/$NAME.sh" ]; then
            TARGET="$SCRIPTS_DIR/core/$NAME.sh"
        else
            echo "    [ WARN ] $NAME introuvable"
            continue
        fi
        chmod 755 "$TARGET"
        ln -sf "$TARGET" "$BIN_DIR/$NAME"
        echo "    [ OK ] $NAME"
    done

    echo ""
    echo "=== TERMINE ==="
    echo "Commandes disponibles : deploy INSTALL | EXPOSE | STOP | SEND_LOGS | HELP"
}

do_expose()
{
    echo ""
    echo "=== RK322X EXPOSE ==="
    require_usb
    sh "$USB_DIR/server/start_server.sh"
}

do_stop()
{
    echo ""
    echo "=== RK322X STOP SERVEURS ==="

    FOUND=0
    for P in /mnt/media_rw/*/server/*.pid; do
        [ -f "$P" ] || continue
        PID="$(cat "$P" 2>/dev/null)"
        if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
            if kill "$PID" 2>/dev/null; then
                echo "[ OK ] $(basename "$P") arrete (PID $PID)"
                FOUND=1
            else
                echo "[ ERREUR ] impossible d'arreter PID $PID ($(basename "$P"))"
            fi
        else
            echo "[ WARN ] PID invalide dans $(basename "$P")"
        fi
        rm -f "$P"
    done

    if [ "$FOUND" -eq 0 ]; then
        echo "[ -- ] aucun serveur actif"
    fi
}

case "$1" in

    INSTALL)
        do_install
        ;;

    EXPOSE)
        do_expose
        ;;

    STOP)
        do_stop
        ;;

    SEND_LOGS)
        TS="$(date '+%Y%m%d_%H%M%S')"

        echo ""
        echo "=== RK322X COLLECTE DES LOGS ==="
        require_usb || exit 1

        OUT="$USB_DIR/log/log_$TS"
        mkdir -p "$OUT"
        echo "[1] Destination : $OUT"
        echo "[2] Collecte..."
        echo ""

        collect()
        {
            NAME="$1"; shift
            N=$((N+1))
            printf '  [%d/%d] %-12s ' "$N" "$TOTAL" "$NAME"
            if "$@" > "$OUT/$NAME.txt" 2>&1; then
                SIZE="$(du -h "$OUT/$NAME.txt" 2>/dev/null | cut -f1)"
                echo "[OK] ($SIZE)"
            else
                echo "[ERREUR]"
            fi
        }

        N=0
        TOTAL=6
        collect logcat   logcat -d
        collect dmesg    dmesg
        collect getprop  getprop
        collect ip_link  ip link
        collect mount    mount
        collect ps       ps

        echo ""
        echo "=== TERMINE ==="
        ls -1 "$OUT" | sed 's/^/  - /'
        echo ""
        echo "Logs disponibles dans : $OUT"
        ;;

    *)
        echo ""
        echo "RK322X DEPLOY"
        echo ""
        echo "Usage: deploy <commande>"
        echo ""
        echo "Commandes:"
        echo "  INSTALL      Rapatrier les scripts de la cle vers la box"
        echo "  EXPOSE       Exposer la cle (HTTP port 8000)"
        echo "  STOP         Arreter les serveurs"
        echo "  SEND_LOGS    Collecter les logs sur la cle"
        echo ""
        if [ -f "/data/scripts/help.sh" ]; then
            echo "Aide complete des outils : help"
        elif [ -f "$USB_DIR/scripts/help.sh" ] || find_usb; then
            echo "Aide complete des outils : sh $USB_DIR/scripts/help.sh"
        fi
        echo ""
        ;;
esac

exit 0
