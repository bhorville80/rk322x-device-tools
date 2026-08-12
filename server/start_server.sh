#!/system/bin/sh

USB="/mnt/media_rw/4E28-7C59"
PORT="8000"
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

su -c "busybox httpd -f -p 0.0.0.0:$PORT -h '$USB'" \
    >> "$LOG" 2>&1 &

PID="$!"

echo "$PID" > "$PIDFILE"

sleep 1

if kill -0 "$PID" 2>/dev/null; then
    echo "SERVER STARTED"
    echo "PID: $PID"
    echo "PORT: $PORT"
    echo "ROOT: $USB"
else
    echo "ERREUR: serveur non démarré"
    rm -f "$PIDFILE"
    exit 1
fi
