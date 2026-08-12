#!/system/bin/sh

USB_DIR="/mnt/media_rw/4E28-7C59"
LOG_DIR="$USB_DIR/log"

mkdir -p "$LOG_DIR"

case "$1" in

    SEND_LOGS)
        TS="$(date '+%Y%m%d_%H%M%S')"
        OUT="$LOG_DIR/log_$TS"

        mkdir -p "$OUT"

        echo "Collecte des logs..."
        echo "Destination: $OUT"

        logcat -d > "$OUT/logcat.txt" 2>&1
        dmesg > "$OUT/dmesg.txt" 2>&1
        getprop > "$OUT/getprop.txt" 2>&1
        ip link > "$OUT/ip_link.txt" 2>&1
        mount > "$OUT/mount.txt" 2>&1
        ps > "$OUT/processes.txt" 2>&1

        echo "Logs envoyés dans:"
        echo "$OUT"
        ;;

    *)
        echo ""
        echo "RK322X DEPLOY"
        echo ""
        echo "Commandes:"
        echo "  SEND_LOGS    Collecter les logs"
        echo ""
        ;;
esac

exit 0
