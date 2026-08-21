#!/system/bin/sh

PORT=8080

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

PIDFILE="$USB/server/control_server.pid"
LOG="$USB/log/control_server.log"
INCOMING="$USB/incoming"
TOKEN_FILE="$USB/server/token"

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

(
    while true
    do
        busybox nc -l -p "$PORT" > /data/local/tmp/control_request 2>/dev/null

        REQUEST="$(head -n 1 /data/local/tmp/control_request 2>/dev/null)"

        COMMAND="$(echo "$REQUEST" | sed -n 's#GET /api/\([^ ?]*\).*#\1#p')"

        if [ -f "$TOKEN_FILE" ]; then
            TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE" 2>/dev/null)"
            GOT="$(echo "$REQUEST" | sed -n 's#.*token=\([0-9a-zA-Z]*\).*#\1#p')"
            if [ -z "$GOT" ] || [ "$GOT" != "$TOKEN" ]; then
                log "REQUEST REJECTED: token invalide (${COMMAND:-<inconnu>})"
                BODY='{"status":"error","message":"forbidden"}'
                printf 'HTTP/1.1 403 Forbidden\r\nContent-Type: application/json\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s' \
                    "${#BODY}" "$BODY"
                rm -f /data/local/tmp/control_request
                continue
            fi
        fi

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
    if [ -f "$TOKEN_FILE" ]; then
        echo "SECURITE: token requis (?token=...)"
    fi
else
    echo "CONTROL SERVER FAILED"
    rm -f "$PIDFILE"
    exit 1
fi
