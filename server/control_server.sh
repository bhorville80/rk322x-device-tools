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

            # reponse synchrone : contenu de la configuration active
            CONFIG)
                CONF=""
                if [ -f /data/scripts/config/device.conf ]; then
                    CONF="/data/scripts/config/device.conf"
                elif [ -f "$USB/scripts/config/device.conf" ]; then
                    CONF="$USB/scripts/config/device.conf"
                fi

                if [ -n "$CONF" ]; then
                    VER_LINE="version installee : inconnue"
                    [ -f /data/scripts/VERSION ] && \
                        VER_LINE="$(grep '^version' /data/scripts/VERSION 2>/dev/null | head -n 1)"
                    BODY="### configuration active ($CONF)\n$VER_LINE\n\n$(cat "$CONF" 2>/dev/null)"
                    log "COMMANDE ACCEPTED: CONFIG -> $CONF"
                    printf 'HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s' \
                        "${#BODY}" "$BODY"
                else
                    log "COMMANDE REJECTED: CONFIG introuvable"
                    BODY='{"status":"error","message":"config introuvable"}'
                    printf 'HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s' \
                        "${#BODY}" "$BODY"
                fi
                ;;

            # reponse synchrone : validation de la configuration active (conf_check)
            CONF_CHECK)
                CHK=""
                if [ -f /data/scripts/conf_check.sh ]; then
                    CHK="/data/scripts/conf_check.sh"
                elif [ -f "$USB/scripts/conf_check.sh" ]; then
                    CHK="$USB/scripts/conf_check.sh"
                fi

                if [ -n "$CHK" ]; then
                    OUT="$(sh "$CHK" 2>&1)"
                    RC=$?
                    log "COMMANDE ACCEPTED: CONF_CHECK (rc=$RC)"
                    printf 'HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s' \
                        "${#OUT}" "$OUT"
                else
                    log "COMMANDE REJECTED: CONF_CHECK introuvable"
                    BODY='{"status":"error","message":"conf_check introuvable"}'
                    printf 'HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s' \
                        "${#BODY}" "$BODY"
                fi
                ;;

            # reponse synchrone : remise a l'heure de la box (t=YYYYMMDD.HHMMSS, UTC)
            TIME_SYNC)
                V="$(printf '%s' "$REQUEST" | sed -n 's#.*[?&]t=\([0-9]\{8\}\.[0-9]\{6\}\).*#\1#p')"
                if [ "$(id -u 2>/dev/null)" != "0" ]; then
                    log "COMMANDE REJECTED: TIME_SYNC (root requis)"
                    BODY='{"status":"error","message":"root requis"}'
                    printf 'HTTP/1.1 403 Forbidden\r\nContent-Type: application/json\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s' \
                        "${#BODY}" "$BODY"
                elif [ -z "$V" ]; then
                    log "COMMANDE REJECTED: TIME_SYNC (parametre manquant)"
                    BODY='{"status":"error","message":"t=YYYYMMDD.HHMMSS attendu"}'
                    printf 'HTTP/1.1 400 Bad Request\r\nContent-Type: application/json\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s' \
                        "${#BODY}" "$BODY"
                else
                    date -u -s "$V" > /dev/null 2>&1
                    NEW="$(date '+%Y-%m-%d %H:%M:%S')"
                    log "TIME_SYNC -> $NEW (UTC)"
                    BODY="{\"status\":\"ok\",\"box_time_utc\":\"$NEW\"}"
                    printf 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s' \
                        "${#BODY}" "$BODY"
                fi
                ;;

            HELP|SEND_LOGS|PURGE_LOG|SYNC|FIELD_OFF|FIELD_ON|HDMI_OFF|HDMI_ON|PANEL|STATE|REBOX|ROTATE_LOGS|ECO_MODE|PERF_MODE|VITALS|RECETTE|RECETTE_P1|RECETTE_P2|RECETTE_P3|RECETTE_P4|RECETTE_P5|RECETTE_P6|RECETTE_P7|RECETTE_RETOUR|RECETTE_MANIFEST)
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
