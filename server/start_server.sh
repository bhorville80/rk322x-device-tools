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

# --- authentification du panneau (HTTP Basic busybox) ---
# PANEL_USER/PANEL_PASS dans device.conf ; vides = acces libre.
conf_val()
{
    for C in /data/scripts/config/device.conf "$USB/scripts/config/device.conf"; do
        [ -f "$C" ] || continue
        V="$(sed -n "s/^$1=//p" "$C" 2>/dev/null | head -n 1 | tr -d '\r')"
        [ -n "$V" ] && { printf '%s' "$V" ; return 0 ; }
    done
    printf '%s' "$2"
}

PANEL_USER="$(conf_val PANEL_USER "")"
PANEL_PASS="$(conf_val PANEL_PASS "")"
AUTH_CONF="$USB/server/httpd.conf"

if [ -n "$PANEL_USER" ] && [ -n "$PANEL_PASS" ]; then
    mkdir -p "$USB/server" 2>/dev/null
    printf '/:%s:%s\n' "$PANEL_USER" "$PANEL_PASS" > "$AUTH_CONF" 2>/dev/null
    AUTH_OPTS="-c $AUTH_CONF -r RK322X_PANEL"
    echo "$(date '+%Y-%m-%d %H:%M:%S') PANEL AUTH active (user: $PANEL_USER)" >> "$LOG"
else
    rm -f "$AUTH_CONF" 2>/dev/null
    AUTH_OPTS=""
fi

# serveurs annexes : installation locale d'abord (/data/scripts/server),
# puis repertoire du script (cle layout depot), puis cle/scripts/server
# (cle construite par sync_usb), cle/server en dernier recours
SRV=""
[ -f "/data/scripts/server/gui_server.sh" ] && SRV="/data/scripts/server"
[ -z "$SRV" ] && [ -f "$(dirname "$0")/gui_server.sh" ] && SRV="$(dirname "$0")"
[ -z "$SRV" ] && [ -f "$USB/scripts/server/gui_server.sh" ] && SRV="$USB/scripts/server"
[ -z "$SRV" ] && SRV="$USB/server"

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

# port en ecoute ? netstat, sinon /proc/net/tcp (port hexa, etat 0A=LISTEN)
port_up()
{
    P_="$1"
    if netstat -tln 2>/dev/null | grep -q ":$P_ "; then
        return 0
    fi
    H_="$(printf '%04X' "$P_" 2>/dev/null)"
    [ -n "$H_" ] && grep -qi ":$H_ .* 0A " /proc/net/tcp 2>/dev/null && return 0
    return 1
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

        for D in scripts server config; do
            [ -d "$USB/$D" ] || continue
            echo "<h2>$D/</h2><ul>"
            ls -1 "$USB/$D" 2>/dev/null | while read -r N; do
                case "$N" in *.log|*.pid) continue ;; esac
                echo "<li><a href=\"$D/$N\">$N</a></li>"
            done
            echo '</ul>'
        done

        echo '<h2>API locales</h2><ul>'
        echo '<li>control : http://&lt;ip-box&gt;:8180/api/HELP (token eventuel)</li>'
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

# --- copie de la configuration active vers la racine cle --------------------
# Le panneau web (infos.html, index.html, cle.html) charge /config/device.conf
# depuis le serveur HTTP. Le depot installe device.conf dans /data/scripts/config/
# (ou scripts/config/ sur la cle) mais pas a la racine de la cle.
# On copie/ synchronise ici pour que httpd puisse la servir.
CONF_DEST="$USB/config/device.conf"
CONF_SRC=""
for C in /data/scripts/config/device.conf "$USB/scripts/config/device.conf"; do
    [ -f "$C" ] || continue
    # prendre la source la plus recente
    if [ -z "$CONF_SRC" ] || [ "$C" -nt "$CONF_SRC" ]; then
        CONF_SRC="$C"
    fi
done
if [ -n "$CONF_SRC" ]; then
    if [ ! -f "$CONF_DEST" ] || [ "$CONF_SRC" -nt "$CONF_DEST" ]; then
        mkdir -p "$USB/config" 2>/dev/null
        if cp -f "$CONF_SRC" "$CONF_DEST" 2>/dev/null; then
            echo "CONFIG SYNC: $CONF_SRC -> $CONF_DEST"
            echo "$(date '+%Y-%m-%d %H:%M:%S') CONFIG SYNC: $CONF_SRC -> $CONF_DEST" >> "$LOG"
        else
            echo "CONFIG SYNC: WARN copie impossible vers $CONF_DEST"
        fi
    else
        echo "CONFIG SYNC: deja a jour"
    fi
else
    echo "CONFIG SYNC: WARN aucun device.conf source (/data/scripts et cle)"
fi

    # nohup si dispo : la fermeture de la session adb ne doit pas tuer le serveur
    if command -v nohup > /dev/null 2>&1; then
        nohup busybox httpd -f -p 0.0.0.0:$PORT $AUTH_OPTS -h "$USB" >> "$LOG" 2>&1 &
    else
        busybox httpd -f -p 0.0.0.0:$PORT $AUTH_OPTS -h "$USB" >> "$LOG" 2>&1 &
    fi

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

    # capture par fichier (pas de $() nu) : un descripteur herite par un
    # serveur en tache de fond ne doit pas bloquer le demarrage de la pile
    SRV_TMP="/data/local/tmp/start_server_out.$$"

    # TOUT verdict est trace dans http_server.log : un 8081 muet ne doit
    # jamais rester sans explication sur la cle (temoin v19 : seul STARTED
    # laissait une trace, deja actif/echec/absent etaient invisibles)
    if [ -f "$SRV/gui_server.sh" ]; then
        sh "$SRV/gui_server.sh" start > "$SRV_TMP" 2>&1
        GUI_OUT="$(cat "$SRV_TMP" 2>/dev/null)"
        case "$GUI_OUT" in
            *"ALREADY RUNNING"*)
                echo "GUI SERVER: deja actif"
                echo "$(date '+%Y-%m-%d %H:%M:%S') GUI SERVER deja actif (port 8081 verifie par gui_server)" >> "$LOG"
                ;;
            *"STARTED"*)
                echo "GUI SERVER: 8081"
                echo "$(date '+%Y-%m-%d %H:%M:%S') GUI SERVER STARTED (PORT 8081)" >> "$LOG"
                ;;
            *)
                echo "GUI SERVER: echec ($GUI_OUT)"
                echo "$(date '+%Y-%m-%d %H:%M:%S') GUI SERVER ECHEC (${GUI_OUT:-aucune sortie})" >> "$LOG"
                ;;
        esac
        sleep 1
        if port_up 8081; then
            echo "GUI PORT: 8081 en ecoute (verifie)"
            case "$GUI_OUT" in
                *"STARTED"*) echo "$(date '+%Y-%m-%d %H:%M:%S') GUI PORT 8081 en ecoute (verifie)" >> "$LOG" ;;
            esac
        else
            echo "GUI PORT: WARN 8081 absent (voir gui_server.log)"
            echo "$(date '+%Y-%m-%d %H:%M:%S') GUI PORT WARN 8081 NON en ecoute apres demarrage" >> "$LOG"
        fi
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') GUI SERVER ABSENT (gui_server.sh introuvable sous $SRV)" >> "$LOG"
    fi

    if [ -f "$SRV/control_server.sh" ]; then
        sh "$SRV/control_server.sh" start > "$SRV_TMP" 2>&1
        CTRL_OUT="$(cat "$SRV_TMP" 2>/dev/null)"
        case "$CTRL_OUT" in
            *"ALREADY RUNNING"*)
                echo "CONTROL SERVER: deja actif"
                echo "$(date '+%Y-%m-%d %H:%M:%S') CONTROL SERVER deja actif (port 8180 verifie par control_server)" >> "$LOG"
                ;;
            *"STARTED"*)
                echo "CONTROL SERVER: 8180"
                echo "$(date '+%Y-%m-%d %H:%M:%S') CONTROL SERVER STARTED (PORT 8180)" >> "$LOG"
                # verdict d'ecoute repris du rapport du serveur lui-meme :
                # un pid vivant ne prouve pas le bind du port
                case "$CTRL_OUT" in
                    *"ECOUTE: verifiee"*)
                        echo "CONTROL PORT: 8180 en ecoute (verifie)"
                        echo "$(date '+%Y-%m-%d %H:%M:%S') CONTROL PORT 8180 en ecoute (verifie)" >> "$LOG" ;;
                    *WARN*)
                        echo "CONTROL PORT: WARN 8180 absent (voir control_server.log)"
                        echo "$(date '+%Y-%m-%d %H:%M:%S') CONTROL PORT WARN 8180 NON ouvert" >> "$LOG" ;;
                esac
                ;;
            *)
                echo "CONTROL SERVER: echec ($CTRL_OUT)"
                echo "$(date '+%Y-%m-%d %H:%M:%S') CONTROL SERVER ECHEC (${CTRL_OUT:-aucune sortie})" >> "$LOG"
                ;;
        esac
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') CONTROL SERVER ABSENT (control_server.sh introuvable sous $SRV)" >> "$LOG"
    fi

    rm -f "$SRV_TMP" 2>/dev/null

    if [ -f "$SRV/watch_usb.sh" ]; then
        sh "$SRV/watch_usb.sh" > /dev/null 2>&1 &
        echo "USB WATCHER: actif (incoming/)"
        echo "$(date '+%Y-%m-%d %H:%M:%S') USB WATCHER STARTED" >> "$LOG"
    fi
else
    echo "ERREUR: serveur non demarre"
    echo "$(date '+%Y-%m-%d %H:%M:%S') HTTP SERVER FAILED (PORT $PORT)" >> "$LOG"
    rm -f "$PIDFILE"
    exit 1
fi
