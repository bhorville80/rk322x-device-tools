#!/system/bin/sh
# start_server.sh - HTTP 8000 servant la cle USB (+ gui_server 8081)
# Genere un index de secours a la racine si le panneau web est absent.

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

box_ip()
{
    IP=""
    for IF in eth0 wlan0; do
        IP="$(ip -4 addr show "$IF" 2>/dev/null | sed -n 's/.*inet \([0-9.]*\).*/\1/p' | head -n 1)"
        [ -n "$IP" ] && break
    done
    if [ -z "$IP" ]; then
        IP="$(ifconfig eth0 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1p')"
    fi
    echo "$IP"
}

ensure_index()
{
    [ -f "$USB/index.html" ] && return 0

    NOW="$(date '+%Y-%m-%d %H:%M:%S')"

    {
        echo '<!DOCTYPE html>'
        echo '<html><head><meta charset="utf-8">'
        echo '<meta name="viewport" content="width=device-width,initial-scale=1">'
        echo '<title>RK322X DEVICE TOOLS</title>'
        echo '<style>body{font-family:monospace;background:#111;color:#ddd;padding:1em 2em}h1{color:#9fd590;font-size:1.2em}h2{color:#e8c06f;font-size:1.05em;margin-bottom:4px}a{color:#7ec8e3;text-decoration:none}li{margin:2px 0}.mut{color:#888}</style>'
        echo '</head><body>'
        echo '<h1>RK322X DEVICE TOOLS</h1>'
        echo "<p class=\"mut\">cle : $USB &mdash; index de secours genere le $NOW</p>"
        echo '<p>Pour le panneau web complet : deploy INSTALL (copie automatiquement'
        echo 'le fichier <code>index.html</code> du depot ici), puis recharger la page.</p>'

        echo '<h2>Racine de la cle</h2><ul>'
        for F in "$USB"/*; do
            N="$(basename "$F")"
            case "$N" in LOST.DIR|.Trashes|*.pid|index.html) continue ;; esac
            [ -f "$F" ] || continue
            SZ="$(wc -c < "$F" 2>/dev/null | tr -dc '0-9')"
            echo "<li><a href=\"$N\">$N</a> <span class=\"mut\">${SZ:-?} o</span></li>"
        done
        echo '</ul>'

        for D in scripts server bin config; do
            [ -d "$USB/$D" ] || continue
            echo "<h2>$D/</h2><ul>"
            ls -1 "$USB/$D" 2>/dev/null | while read -r N; do
                case "$N" in *.log|*.pid) continue ;; esac
                echo "<li><a href=\"$D/$N\">$N</a></li>"
            done
            echo '</ul>'
        done

        echo '<h2>API locales</h2><ul>'
        echo '<li>control : http://&lt;ip-box&gt;:8080/api/HELP (token eventuel)</li>'
        echo '<li>gui     : http://&lt;ip-box&gt;:8081/gui/HELP</li>'
        echo '</ul>'
        echo '</body></html>'
    } > "$USB/index.html" 2>/dev/null

    [ -f "$USB/index.html" ]
}

if [ -f "$PIDFILE" ]; then
    PID="$(cat "$PIDFILE" 2>/dev/null)"

    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        echo "SERVER deja actif"
        echo "PID: $PID"
        exit 0
    fi

    rm -f "$PIDFILE"
fi

if netstat -tln 2>/dev/null | grep -q ":$PORT "; then
    echo "[WARN] port $PORT semble occupe par un processus etranger"
    echo "       (pas de server.pid valide). Voir : deploy STOP ou reboot."
fi

ensure_index

busybox httpd -f -p 0.0.0.0:$PORT -h "$USB" >> "$LOG" 2>&1 &

PID="$!"

echo "$PID" > "$PIDFILE"

sleep 1

if kill -0 "$PID" 2>/dev/null; then
    echo "SERVER STARTED"
    echo "PID: $PID"
    echo "PORT: $PORT"
    echo "ROOT: $USB"

    IP="$(box_ip)"
    if [ -n "$IP" ]; then
        echo "URL : http://$IP:$PORT/"
    else
        echo "URL : http://<ip-box>:$PORT/"
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') HTTP SERVER STARTED (PID $PID, PORT $PORT, ROOT $USB)" >> "$LOG"

    if [ -f "$USB/server/gui_server.sh" ]; then
        if sh "$USB/server/gui_server.sh" start > /dev/null 2>&1; then
            echo "GUI SERVER: 8081"
            echo "$(date '+%Y-%m-%d %H:%M:%S') GUI SERVER STARTED (PORT 8081)" >> "$LOG"
        else
            echo "GUI SERVER: echec (voir log/gui_server.log)"
        fi
    fi
else
    echo "ERREUR: serveur non demarre"
    echo "$(date '+%Y-%m-%d %H:%M:%S') HTTP SERVER FAILED (PORT $PORT)" >> "$LOG"
    rm -f "$PIDFILE"
    exit 1
fi
