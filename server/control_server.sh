#!/system/bin/sh

USB="/mnt/media_rw/4E28-7C59"
PORT=8080
PIDFILE="$USB/server/control_server.pid"
LOG="$USB/log/control_server.log"
INCOMING="$USB/incoming"

mkdir -p "$USB/server" "$USB/log" "$INCOMING"

log()
{
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
}

case "$1" in
    start)
        ;;
    *)
        echo "Usage: sh $0 start"
        exit 1
        ;;
esac

if [ -f "$PIDFILE" ]; then
    PID="$(cat "$PIDFILE" 2>/dev/null)"
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        echo "CONTROL SERVER ALREADY RUNNING"
        echo "PID: $PID"
        exit 0
    fi
    rm -f "$PIDFILE"
fi

echo "CONTROL SERVER STARTED" >> "$LOG"

log "========================================"
log "CONTROL SERVER START (PORT $PORT)"
log "========================================"

(
    while true
    do
        busybox nc -l -p "$PORT" > /data/local/tmp/control_request 2>/dev/null

        REQUEST="$(head -n 1 /data/local/tmp/control_request 2>/dev/null)"

        COMMAND="$(echo "$REQUEST" | sed -n 's#GET /api/\([^ ?]*\).*#\1#p')"

        log "REQUEST: ${COMMAND:-<inconnu>}"

        case "$COMMAND" in
            HELP|SEND_LOGS|PURGE_LOG|SYNC)
                touch "$INCOMING/$COMMAND"
                log "COMMANDE ACCEPTED: $COMMAND"

                BODY="{\"status\":\"ok\",\"command\":\"$COMMAND\"}"

                printf 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s' \
                    "${#BODY}" "$BODY"
                ;;

            *)
                log "COMMANDE REJECTED: inconnue"

                BODY='{"status":"error","message":"unknown command"}'

                printf 'HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s' \
                    "${#BODY}" "$BODY"
                ;;
        esac

        rm -f /data/local/tmp/control_request
    done
) &

PID="$!"
echo "$PID" > "$PIDFILE"

sleep 1

if kill -0 "$PID" 2>/dev/null; then
    echo "CONTROL SERVER STARTED"
    echo "PID: $PID"
    echo "PORT: $PORT"
else
    echo "CONTROL SERVER FAILED"
    rm -f "$PIDFILE"
    exit 1
fi
