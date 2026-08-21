#!/system/bin/sh

USB="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)"
if [ -z "$USB" ] || [ ! -f "$USB/deploy.sh" ]; then
    USB=""
    for d in /mnt/media_rw/*; do
        if [ -f "$d/deploy.sh" ]; then
            USB="$d"
            break
        fi
    done
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
                rm -f "$FILE"
                ;;

            SYNC)
                log "SYNC"
                sh "$USB/scripts/sync_usb.sh" >> "$LOG" 2>&1
                rm -f "$FILE"
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
                sh "$USB/bin/MEDIA" >> "$LOG" 2>&1
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
