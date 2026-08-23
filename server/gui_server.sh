#!/system/bin/sh
# server/gui_server.sh - telecommande de l'interface graphique TV (port 8081)
#
# Endpoints (GET):
#   INDEX              ouvre le panneau web (http://IP:8000) sur la TV
#   URL?u=<adresse>    affiche une page en plein ecran (http/https/file uniquement)
#   TEXT?t=<message>   affiche un message en plein ecran (page locale generee)
#   KEY?k=<KEYCODE_X>  injecte une touche (input keyevent)
#   TAP?x=N&y=N        simule un tap ecran
#   SHOT               capture d'ecran -> log/gui_shots/latest.png (servi en HTTP 8000)
#
# Securite: si server/token existe, chaque appel exige ?token=<valeur>.
# Arret: deploy STOP (supprime server/*.pid) ou kill du PID du pidfile.

PORT=8081

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

PIDFILE="$USB/server/gui_server.pid"
LOG="$USB/log/gui_server.log"
SHOTS_DIR="$USB/log/gui_shots"
TMP_HTML="/data/local/tmp/gui_text.html"
TOKEN_FILE="$USB/server/token"

mkdir -p "$USB/server" "$USB/log" "$SHOTS_DIR"

log()
{
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
}

case "$1" in
    start) ;;
    *)     echo "Usage: sh $0 start" ; exit 1 ;;
esac

if [ -f "$PIDFILE" ]; then
    PID="$(cat "$PIDFILE" 2>/dev/null)"
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        echo "GUI SERVER ALREADY RUNNING"
        echo "PID: $PID"
        exit 0
    fi
    rm -f "$PIDFILE"
fi

reply()
{
    # reply <code> <status> <body> ; CORS : panneau sur :8000, API ici :8081
    printf 'HTTP/1.1 %s %s\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s' \
        "$1" "$2" "${#3}" "$3"
}

ok()
{
    reply 200 OK "{\"status\":\"ok\",\"action\":\"$1\"}"
}

ko()
{
    reply 400 Bad Request "{\"status\":\"error\",\"message\":\"$1\"}"
}

decode()
{
    # decodage URL : busybox httpd -d, sinon brut
    D="$(busybox httpd -d "$1" 2>/dev/null)"
    [ -n "$D" ] && { printf '%s' "$D"; return 0; }
    printf '%s' "$1"
}

param()
{
    printf '%s' "$QS" | tr '&' '\n' | sed -n "s#^$1=\(.*\)\$\$#\1#p" | head -n 1
}

get_ip()
{
    IP="$(sed -n 's/^IP=//p' /data/scripts/config/device.conf 2>/dev/null | head -n 1 | tr -d '\r')"
    [ -n "$IP" ] || IP="$(sed -n 's/^IP=//p' "$USB/scripts/config/device.conf" 2>/dev/null | head -n 1 | tr -d '\r')"
    [ -n "$IP" ] || IP="192.168.50.20"
    printf '%s' "$IP"
}

(
    # immunise contre SIGHUP : la fermeture de la session adb ne doit pas
    # tuer le service lance en arriere-plan
    trap '' HUP

    # timeout dispo ? une connexion sans donnees (preconnexe navigateur,
    # scan de port) monopoliserait sinon l'unique slot nc pour toujours
    HAS_TIMEOUT=0
    command -v timeout > /dev/null 2>&1 && HAS_TIMEOUT=1

    while true
    do
        if [ "$HAS_TIMEOUT" = "1" ]; then
            timeout 30 busybox nc -l -p "$PORT" > /data/local/tmp/gui_request 2>/dev/null
        else
            busybox nc -l -p "$PORT" > /data/local/tmp/gui_request 2>/dev/null
        fi

        REQUEST="$(head -n 1 /data/local/tmp/gui_request 2>/dev/null)"

        # connexion silencieuse expiree (timeout) : rien a traiter
        if [ -z "$REQUEST" ]; then
            rm -f /data/local/tmp/gui_request
            continue
        fi

        ACTION="$(printf '%s' "$REQUEST" | sed -n 's#GET /gui/\([^ ?]*\).*#\1#p')"
        QS="$(printf '%s' "$REQUEST" | sed -n 's#GET /gui/[^ ?]*?\([^ ]*\).*#\1#p')"

        if [ -f "$TOKEN_FILE" ]; then
            TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE" 2>/dev/null)"
            GOT="$(param token)"
            GOT="$(printf '%s' "$GOT" | tr -cd '0-9a-zA-Z')"
            if [ -z "$GOT" ] || [ "$GOT" != "$TOKEN" ]; then
                log "REJET token invalide (${ACTION:-<inconnu>})"
                reply 403 Forbidden '{"status":"error","message":"forbidden"}'
                rm -f /data/local/tmp/gui_request
                continue
            fi
        fi

        log "ACTION: ${ACTION:-<inconnu>} QS: ${QS:+oui}"

        RC=""
        case "$ACTION" in

            INDEX)
                IP="$(get_ip)"
                am start -a android.intent.action.VIEW -d "http://$IP:8000" > /dev/null 2>&1 \
                    && ok INDEX || ko "aucune activite resolve (navigateur absent ?)"
                ;;

            URL)
                U="$(decode "$(param u)")"
                case "$U" in
                    http:*|https:*|file:*)
                        if am start -a android.intent.action.VIEW -d "$U" > /dev/null 2>&1; then
                            log "URL affichee : $U"
                            ok URL
                        else
                            ko "navigateur indisponible"
                        fi ;;
                    *) ko "url non autorisee (http/https/file)" ;;
                esac
                ;;

            TEXT)
                T="$(decode "$(param t)" | tr -d '"`$' | cut -c1-300)"
                if [ -z "$T" ]; then
                    ko "message vide"
                else
                    {
                        echo '<html><body style="background:#000;color:#4f4;font-family:sans-serif;'
                        echo 'display:flex;align-items:center;justify-content:center;height:100%;margin:0">'
                        echo '<div style="font-size:10vw;text-align:center;white-space:pre-wrap">'"$T"'</div>'
                        echo '</body></html>'
                    } > "$TMP_HTML" 2>/dev/null
                    chmod 644 "$TMP_HTML" 2>/dev/null
                    if am start -a android.intent.action.VIEW -d "file://$TMP_HTML" > /dev/null 2>&1; then
                        log "TEXTE affiche"
                        ok TEXT
                    else
                        ko "navigateur indisponible"
                    fi
                fi
                ;;

            KEY)
                K="$(param k | tr -cd 'A-Za-z0-9_' | cut -c1-40)"
                if [ -n "$K" ]; then
                    if input keyevent "$K" > /dev/null 2>&1; then
                        ok "KEY:$K"
                    else
                        ko "touche refusee ($K)"
                    fi
                else
                    ko "parametre k manquant"
                fi
                ;;

            TAP)
                X="$(param x | tr -cd '0-9' | cut -c1-5)"
                Y="$(param y | tr -cd '0-9' | cut -c1-5)"
                if [ -n "$X" ] && [ -n "$Y" ]; then
                    input tap "$X" "$Y" > /dev/null 2>&1 && ok "TAP:$X,$Y" || ko "tap echoue"
                else
                    ko "parametres x/y manquants"
                fi
                ;;

            SHOT)
                if command -v screencap > /dev/null 2>&1; then
                    OUT="$SHOTS_DIR/latest.png"
                    if screencap -p "$OUT" 2>/dev/null && [ -s "$OUT" ]; then
                        SIZE="$(wc -c < "$OUT" 2>/dev/null | tr -dc '0-9')"
                        log "SHOT -> $OUT ($SIZE octets)"
                        reply 200 OK "{\"status\":\"ok\",\"action\":\"SHOT\",\"file\":\"/log/gui_shots/latest.png\",\"size\":${SIZE:-0}}"
                    else
                        ko "capture vide"
                    fi
                else
                    ko "screencap absent"
                fi
                ;;

            "")
                ko "action absente"
                ;;

            *)
                log "REJET action inconnue : $ACTION"
                reply 404 Not Found '{"status":"error","message":"unknown action"}'
                ;;
        esac

        rm -f /data/local/tmp/gui_request
    done
) &

PID="$!"
echo "$PID" > "$PIDFILE"

sleep 1

if kill -0 "$PID" 2>/dev/null; then
    echo "GUI SERVER STARTED"
    echo "PID: $PID"
    echo "PORT: $PORT"
    [ -f "$TOKEN_FILE" ] && echo "SECURITE: token requis (?token=...)"
else
    echo "GUI SERVER FAILED"
    rm -f "$PIDFILE"
    exit 1
fi
