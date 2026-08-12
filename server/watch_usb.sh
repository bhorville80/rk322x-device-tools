#!/system/bin/sh

USB="/mnt/media_rw/4E28-7C59"
INCOMING="$USB/incoming"
LOG_DIR="$USB/log"
LOG="$LOG_DIR/watch.log"

mkdir -p "$INCOMING" "$LOG_DIR"

log()
{
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
}

log "========================================"
log "USB WATCHER POLLING START"
log "INCOMING: $INCOMING"
log "========================================"

while true
do
    for FILE in "$INCOMING"/*
    do
        [ -f "$FILE" ] || continue

        NAME="$(basename "$FILE")"

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
