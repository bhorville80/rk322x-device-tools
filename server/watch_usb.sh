#!/system/bin/sh

# racine = CLE en priorite (cf gui_server.sh) : sinon, lance depuis
# /data/scripts/server, le watcher surveille /data/scripts/incoming au lieu
# de <cle>/incoming (la ou httpd 8000 et le depot deposent) -> commandes
# incoming jamais declenchees.
USB=""
for d in /mnt/media_rw/*; do
    if [ -f "$d/deploy.sh" ]; then
        USB="$d"
        break
    fi
done
if [ -z "$USB" ]; then
    USB="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)"
    [ -f "$USB/deploy.sh" ] || USB=""
fi

if [ -z "$USB" ]; then
    echo "[ERREUR] cle USB introuvable"
    exit 1
fi

INCOMING="$USB/incoming"
LOG_DIR="$USB/log"
LOG="$LOG_DIR/watch.log"
LOCK="$USB/server/watch.lock"

mkdir -p "$INCOMING" "$LOG_DIR" "$USB/server"

if [ -f "$LOCK" ]; then
    LPID="$(cat "$LOCK" 2>/dev/null)"
    if [ -n "$LPID" ] && kill -0 "$LPID" 2>/dev/null; then
        echo "[ERREUR] watcher deja actif (PID $LPID)"
        exit 1
    fi
    rm -f "$LOCK"
fi

echo $$ > "$LOCK"

log()
{
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
}

cleanup()
{
    rm -f "$LOCK"
    exit 0
}

# HUP ignore : la fermeture de la session adb ne doit pas tuer le watcher
# (le lock stale est de toute facon detecte au prochain demarrage)
trap '' HUP
trap cleanup INT TERM

log "========================================"
log "USB WATCHER POLLING START (PID $$)"
log "INCOMING: $INCOMING"
log "========================================"

while true
do
    for FILE in "$INCOMING"/*
    do
        [ -f "$FILE" ] || continue

        NAME="$(basename "$FILE")"

        case "$NAME" in
            .*|_*)
                rm -f "$FILE"
                continue
                ;;
        esac

        case "$NAME" in
            HELP)
                log "HELP"
                sh "$USB/deploy.sh" HELP >> "$LOG" 2>&1
                rm -f "$FILE"
                ;;

            SEND_LOGS)
                log "SEND_LOGS"
                sh "$USB/deploy.sh" SEND_LOGS >> "$LOG" 2>&1
                sh "$USB/scripts/rotate_logs.sh" > /dev/null 2>&1
                rm -f "$FILE"
                ;;

            SYNC)
                log "SYNC"
                sh "$USB/scripts/sync_usb.sh" >> "$LOG" 2>&1
                rm -f "$FILE"
                ;;

            FIELD_OFF)
                log "FIELD_OFF"
                sh "$USB/scripts/field_mode.sh" OFF >> "$LOG" 2>&1
                rm -f "$FILE"
                ;;

            FIELD_ON)
                log "FIELD_ON"
                sh "$USB/scripts/field_mode.sh" ON >> "$LOG" 2>&1
                rm -f "$FILE"
                ;;

            HDMI_OFF)
                log "HDMI_OFF"
                sh "$USB/scripts/hdmi.sh" OFF >> "$LOG" 2>&1
                rm -f "$FILE"
                ;;

            HDMI_ON)
                log "HDMI_ON"
                sh "$USB/scripts/hdmi.sh" ON >> "$LOG" 2>&1
                rm -f "$FILE"
                ;;

            PANEL)
                log "PANEL"
                IP="$(sed -n 's/^IP=//p' "$USB/scripts/config/device.conf" 2>/dev/null | head -n 1 | tr -d '\r')"
                [ -n "$IP" ] || IP="192.168.50.20"
                sh "$USB/scripts/inspect_gui.sh" URL "http://$IP:8000" >> "$LOG" 2>&1
                rm -f "$FILE"
                ;;

            STATE)
                log "STATE"
                mkdir -p "$LOG_DIR"
                sh "$USB/scripts/check_state.sh" > "$LOG_DIR/state_last.txt" 2>&1
                rm -f "$FILE"
                ;;

            VITALS)
                log "VITALS"
                mkdir -p "$LOG_DIR"
                sh "$USB/scripts/vitals.sh" STATUS > "$LOG_DIR/vitals_last.txt" 2>&1
                rm -f "$FILE"
                ;;

            RECETTE)
                log "RECETTE"
                mkdir -p "$LOG_DIR"
                sh "$USB/scripts/recette.sh" > "$LOG_DIR/recette_last.txt" 2>&1
                rm -f "$FILE"
                ;;

            RECETTE_P[1-7]|RECETTE_RETOUR|RECETTE_MANIFEST)
                log "RECETTE $NAME"
                mkdir -p "$LOG_DIR"
                PH="${NAME#RECETTE_}"
                sh "$USB/scripts/recette.sh" "$PH" >> "$LOG_DIR/recette_last.txt" 2>&1
                rm -f "$FILE"
                ;;

            ROTATE_LOGS)
                log "ROTATE_LOGS"
                sh "$USB/scripts/rotate_logs.sh" >> "$LOG" 2>&1
                rm -f "$FILE"
                ;;

            ECO_MODE)
                log "ECO_MODE"
                sh "$USB/scripts/thermal.sh" ECO >> "$LOG" 2>&1
                rm -f "$FILE"
                ;;

            PERF_MODE)
                log "PERF_MODE"
                sh "$USB/scripts/thermal.sh" PERF >> "$LOG" 2>&1
                rm -f "$FILE"
                ;;

            REBOX)
                log "REBOOT demande"
                rm -f "$FILE"
                sync
                reboot || setprop sys.powerctl reboot
                ;;

            PURGE_LOG)
                log "PURGE_LOG"
                rm -rf "$LOG_DIR"
                mkdir -p "$LOG_DIR"
                log "LOG PURGED"
                rm -f "$FILE"
                ;;

            MEDIA)
                log "MEDIA"
                if [ -f "/data/scripts/core/media.sh" ]; then
                    sh /data/scripts/core/media.sh >> "$LOG" 2>&1
                elif [ -f "$USB/scripts/core/media.sh" ]; then
                    sh "$USB/scripts/core/media.sh" >> "$LOG" 2>&1
                else
                    log "MEDIA: media.sh introuvable"
                fi
                rm -f "$FILE"
                ;;

            POLL_TEST|POLL8TEST|TEST_INOTIFY|INOTIFY_TEST2|INOTIFY_TEST3|INOTIFY_TEST4)
                log "TEST IGNORE: $NAME"
                rm -f "$FILE"
                ;;

            *)
                log "UNKNOWN=$NAME"
                rm -f "$FILE"
                ;;
        esac
    done

    sleep 1
done
