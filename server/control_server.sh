#!/system/bin/sh

PORT=8080

# detection root robuste : id -u, sinon parsing du "id" brut (vieux toolbox)
is_root()
{
    case "$(id -u 2>/dev/null)" in
        0) return 0 ;;
    esac
    case "$(id 2>/dev/null)" in
        "uid=0("*) return 0 ;;
    esac
    return 1
}

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

# reply <code> <status> <body> [content-type]
# En-tete CORS obligatoire : le panneau est servi sur :8000 et l'API sur
# :8080 -> origines differentes ; sans Access-Control-Allow-Origin le
# navigateur bloque la lecture de la reponse (fetch rejette cote IHM).
reply()
{
    printf 'HTTP/1.1 %s %s\r\nContent-Type: %s\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s' \
        "$1" "$2" "${4:-application/json}" "${#3}" "$3"
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
            timeout 30 busybox nc -l -p "$PORT" > /data/local/tmp/control_request 2>/dev/null
        else
            busybox nc -l -p "$PORT" > /data/local/tmp/control_request 2>/dev/null
        fi

        REQUEST="$(head -n 1 /data/local/tmp/control_request 2>/dev/null)"

        # connexion silencieuse expiree (timeout) : rien a traiter
        if [ -z "$REQUEST" ]; then
            rm -f /data/local/tmp/control_request
            continue
        fi

        # preflight eventuel du navigateur : reponse seche avec CORS
        case "$REQUEST" in
            OPTIONS*)
                printf 'HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, OPTIONS\r\nAccess-Control-Allow-Headers: *\r\nContent-Length: 0\r\nConnection: close\r\n\r\n'
                rm -f /data/local/tmp/control_request
                continue
                ;;
        esac

        COMMAND="$(echo "$REQUEST" | sed -n 's#GET /api/\([^ ?]*\).*#\1#p')"

        if [ -f "$TOKEN_FILE" ]; then
            TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE" 2>/dev/null)"
            GOT="$(echo "$REQUEST" | sed -n 's#.*token=\([0-9a-zA-Z]*\).*#\1#p')"
            if [ -z "$GOT" ] || [ "$GOT" != "$TOKEN" ]; then
                log "REQUEST REJECTED: token invalide (${COMMAND:-<inconnu>})"
                reply 403 Forbidden '{"status":"error","message":"forbidden"}'
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
                    reply 200 OK "$BODY" "text/plain; charset=utf-8"
                else
                    log "COMMANDE REJECTED: CONFIG introuvable"
                    reply 404 Not Found '{"status":"error","message":"config introuvable"}'
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
                    reply 200 OK "$OUT" "text/plain; charset=utf-8"
                else
                    log "COMMANDE REJECTED: CONF_CHECK introuvable"
                    reply 404 Not Found '{"status":"error","message":"conf_check introuvable"}'
                fi
                ;;

            # reponse synchrone : remise a l'heure de la box (t=YYYYMMDD.HHMMSS, UTC)
            TIME_SYNC)
                V="$(printf '%s' "$REQUEST" | sed -n 's#.*[?&]t=\([0-9]\{8\}\.[0-9]\{6\}\).*#\1#p')"
                if ! is_root; then
                    log "COMMANDE REJECTED: TIME_SYNC (root requis)"
                    reply 403 Forbidden '{"status":"error","message":"root requis"}'
                elif [ -z "$V" ]; then
                    log "COMMANDE REJECTED: TIME_SYNC (parametre manquant)"
                    reply 400 Bad Request '{"status":"error","message":"t=YYYYMMDD.HHMMSS attendu"}'
                else
                    date -u -s "$V" > /dev/null 2>&1
                    NEW="$(date '+%Y-%m-%d %H:%M:%S')"
                    log "TIME_SYNC -> $NEW (UTC)"
                    reply 200 OK "{\"status\":\"ok\",\"box_time_utc\":\"$NEW\"}"
                fi
                ;;

            HELP|SEND_LOGS|PURGE_LOG|SYNC|FIELD_OFF|FIELD_ON|HDMI_OFF|HDMI_ON|PANEL|STATE|REBOX|ROTATE_LOGS|ECO_MODE|PERF_MODE|VITALS|RECETTE|RECETTE_P1|RECETTE_P2|RECETTE_P3|RECETTE_P4|RECETTE_P5|RECETTE_P6|RECETTE_P7|RECETTE_RETOUR|RECETTE_MANIFEST)
                touch "$INCOMING/$COMMAND"
                log "COMMANDE ACCEPTED: $COMMAND"

                reply 200 OK "{\"status\":\"ok\",\"command\":\"$COMMAND\"}"
                ;;

            *)
                log "COMMANDE REJECTED: inconnue"

                reply 404 Not Found '{"status":"error","message":"unknown command"}'
                ;;
        esac

        rm -f /data/local/tmp/control_request
    done
) >> "$LOG" 2>&1 &

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
