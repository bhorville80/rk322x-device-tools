#!/system/bin/sh

PORT="8000"

USB=""
for d in /mnt/media_rw/*; do
    [ -d "$d" ] || continue
    [ -f "$d/deploy.sh" ] || continue
    USB="$d"
    break
done

if [ -z "$USB" ]; then
    echo "[ERREUR] aucune cle USB contenant deploy.sh trouvee"
    exit 1
fi

PIDFILE="$USB/server/server.pid"
LOG="$USB/log/http_server.log"

mkdir -p "$USB/server" "$USB/log"

if [ -f "$PIDFILE" ]; then
    PID="$(cat "$PIDFILE" 2>/dev/null)"

    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        echo "SERVER déjà actif"
        echo "PID: $PID"
        exit 0
    fi

    rm -f "$PIDFILE"
fi

busybox httpd -f -p 0.0.0.0:$PORT -h "$USB" >> "$LOG" 2>&1 &

PID="$!"

echo "$PID" > "$PIDFILE"

sleep 1

if kill -0 "$PID" 2>/dev/null; then
    echo "SERVER STARTED"
    echo "PID: $PID"
    echo "PORT: $PORT"
    echo "ROOT: $USB"
    echo "$(date '+%Y-%m-%d %H:%M:%S') HTTP SERVER STARTED (PID $PID, PORT $PORT, ROOT $USB)" >> "$LOG"
else
    echo "ERREUR: serveur non démarré"
    echo "$(date '+%Y-%m-%d %H:%M:%S') HTTP SERVER FAILED (PORT $PORT)" >> "$LOG"
    rm -f "$PIDFILE"
    exit 1
fi
