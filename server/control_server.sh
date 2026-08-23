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
TMP_REQ="/data/local/tmp/control_request"

mkdir -p "$USB/server" "$USB/log" "$INCOMING"

log()
{
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
}

# reply <code> <status> <body> [content-type]
# En-tete CORS obligatoire : le panneau est servi sur :8000 et l'API sur
# :8080 -> origines differentes ; sans Access-Control-Allow-Origin le
# navigateur bloque la lecture de la reponse (fetch rejette cote IHM).
# Content-Length calcule en OCTETS (wc -c) : ${#var} compte des caracteres
# et tronquerait les corps UTF-8 (text/plain accentues).
reply()
{
    LEN="$(printf '%s' "$3" | wc -c | tr -dc '0-9')"
    printf 'HTTP/1.1 %s %s\r\nContent-Type: %s\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s' \
        "$1" "$2" "${4:-application/json}" "$LEN" "$3"
}

# --------------------------------------------------------------- upload
# POST /api/UPLOAD?name=<fichier>&sha=<hex64>&dir=<upload|root>
# Le corps binaire suit les en-tetes dans TMP_REQ : on attend l'arrivee
# complete (Content-Length), on extrait par offset d'octets (jamais via
# une variable shell : NUL non preservables), on verifie le sha256.

MAX_UPLOAD=20971520   # 20 Mo

json_reply()
{
    reply 200 OK "{\"status\":\"$1\",\"message\":\"$2\"}"
}

post_qs()
{
    printf '%s' "$REQUEST" | sed -n 's#POST /api/UPLOAD?\([^ ]*\).*#\1#p'
}

post_param()
{
    # $1 nom du parametre, dans $QS_POST
    printf '%s' "$QS_POST" | tr '&' '\n' | sed -n "s#^$1=\([0-9a-zA-Z._-]*\).*#\1#p" | head -n 1
}

handle_post()
{
    QS_POST="$(post_qs)"

    NAME="$(post_param name)"
    SHA_WANT="$(post_param sha | tr 'A-Z' 'a-z')"
    DIR_="$(post_param dir)"
    case "$DIR_" in root) DEST_DIR="$USB" ;; *) DEST_DIR="$USB/upload" ;; esac

    case "$NAME" in
        ""|*[!A-Za-z0-9._-]*)
            reply 400 "Bad Request" '{"status":"error","message":"nom de fichier invalide"}'
            return 0 ;;
    esac
    case "$NAME" in
        *.dpk|*.sha256|*.txt|*.sha|*.log) ;;
        *) reply 400 "Bad Request" '{"status":"error","message":"extension non autorisee (.dpk/.sha256/.txt/.sha/.log)"}'
           return 0 ;;
    esac
    if [ ! -d "$DEST_DIR" ]; then
        mkdir -p "$DEST_DIR" 2>/dev/null \
            || { reply 500 "Internal Server Error" '{"status":"error","message":"destination inaccessible"}'; return 0; }
    fi

    # --- en-tetes : offset du corps + Content-Length ---
    OFF=0 ; CL=0 ; FOUND=0
    # lecture ligne a ligne du fichier : read conserve \r, ajoute le \n
    while IFS= read -r LINE; do
        OFF=$((OFF + ${#LINE} + 1))
        case "$LINE" in
            [Cc]ontent-[Ll]ength:*) CL="$(printf '%s' "$LINE" | sed 's#^[^:]*: *##' | tr -dc '0-9')" ;;
            "") FOUND=1 ; break ;;
        esac
    done < "$TMP_REQ"

    if [ "$FOUND" -ne 1 ]; then
        sleep 2
        OFF=0 ; FOUND=0 ; CL=0
        while IFS= read -r LINE; do
            OFF=$((OFF + ${#LINE} + 1))
            case "$LINE" in
                [Cc]ontent-[Ll]ength:*) CL="$(printf '%s' "$LINE" | sed 's#^[^:]*: *##' | tr -dc '0-9')" ;;
                "") FOUND=1 ; break ;;
            esac
        done < "$TMP_REQ"
    fi

    if [ "$FOUND" -ne 1 ] || [ "${CL:-0}" -le 0 ]; then
        reply 400 "Bad Request" '{"status":"error","message":"requete POST incomprehensible"}'
        return 0
    fi
    if [ "$CL" -gt "$MAX_UPLOAD" ]; then
        reply 413 "Payload Too Large" "{\"status\":\"error\",\"message\":\"fichier > 20 Mo\"}"
        return 0
    fi

    TOTAL=$((OFF + CL))

    # --- attendre la fin du transfert (borne ~60 s) ---
    j=0
    while [ "$j" -lt 200 ]; do
        SIZE_NOW="$(wc -c < "$TMP_REQ" 2>/dev/null | tr -dc '0-9')"
        [ "${SIZE_NOW:-0}" -ge "$TOTAL" ] && break
        sleep 0.3 2>/dev/null || sleep 1
        j=$((j+1))
    done
    SIZE_NOW="$(wc -c < "$TMP_REQ" 2>/dev/null | tr -dc '0-9')"
    if [ "${SIZE_NOW:-0}" -lt "$TOTAL" ]; then
        reply 408 "Request Timeout" '{"status":"error","message":"transfert incomplet"}'
        return 0
    fi

    # --- extraction par octets + controle ---
    PART="$DEST_DIR/.$NAME.part"
    tail -c +"$((OFF + 1))" "$TMP_REQ" > "$PART" 2>/dev/null
    SIZE_PART="$(wc -c < "$PART" 2>/dev/null | tr -dc '0-9')"
    if [ "${SIZE_PART:-0}" -ne "$CL" ]; then
        rm -f "$PART"
        reply 500 "Internal Server Error" "{\"status\":\"error\",\"message\":\"taille recue $SIZE_PART != annonce $CL\"}"
        return 0
    fi

    SHA_OK="non"
    if [ -n "$SHA_WANT" ]; then
        SHA_GOT=""
        if command -v sha256sum > /dev/null 2>&1; then
            SHA_GOT="$(sha256sum "$PART" 2>/dev/null | cut -d' ' -f1)"
        elif command -v busybox > /dev/null 2>&1 && busybox sha256sum >/dev/null 2>&1 <<<''; then
            SHA_GOT="$(busybox sha256sum "$PART" 2>/dev/null | cut -d' ' -f1)"
        fi
        if [ -z "$SHA_GOT" ]; then
            rm -f "$PART"
            reply 500 "Internal Server Error" '{"status":"error","message":"sha256sum indisponible sur la box"}'
            return 0
        fi
        if [ "$SHA_GOT" = "$SHA_WANT" ]; then
            SHA_OK="oui"
        else
            rm -f "$PART"
            log "UPLOAD REJETE: sha256 $NAME (attendu $SHA_WANT, recu $SHA_GOT)"
            reply 422 "Unprocessable Entity" "{\"status\":\"error\",\"message\":\"sha256 different ($SHA_GOT)\"}"
            return 0
        fi
    fi

    mv -f "$PART" "$DEST_DIR/$NAME" 2>/dev/null \
        || { reply 500 "Internal Server Error" '{"status":"error","message":"renommage impossible"}'; return 0; }

    log "UPLOAD OK: $DEST_DIR/$NAME ($CL octets, sha:$SHA_OK)"
    json_reply "ok" "depose : ${DEST_DIR#$USB/}/$NAME ($CL o, sha256:$SHA_OK)"
}

# GET /api/APPLY_DPK?name=<pkg.dpk> : extrait l'archive sur la cle
# (format tar.gz au layout depot/cle) apres controle deploy.sh present.
apply_dpk()
{
    NAME="$(printf '%s' "$1" | sed -n 's#.*name=\([0-9A-Za-z._-]*\).*#\1#p')"
    case "$NAME" in
        *.dpk) ;;
        "") reply 400 "Bad Request" '{"status":"error","message":"name=.dpk requis"}' ; return 0 ;;
        *)  reply 400 "Bad Request" '{"status":"error","message":"extension .dpk requise"}' ; return 0 ;;
    esac

    PKG=""
    for CAND in "$USB/upload/$NAME" "$USB/$NAME"; do
        [ -s "$CAND" ] && { PKG="$CAND"; break; }
    done
    if [ -z "$PKG" ]; then
        reply 404 "Not Found" "{\"status\":\"error\",\"message\":\"$NAME introuvable (upload/ ou racine cle)\"}"
        return 0
    fi

    if ! command -v tar > /dev/null 2>&1 && ! command -v busybox > /dev/null 2>&1; then
        reply 500 "Internal Server Error" '{"status":"error","message":"tar indisponible"}'
        return 0
    fi

    LISTING="$(tar -tzf "$PKG" 2>/dev/null || busybox tar -tzf "$PKG" 2>/dev/null)"
    case "$LISTING" in
        *deploy.sh*) ;;
        "")
            reply 500 "Internal Server Error" '{"status":"error","message":"archive illisible (tar.gz requis)"}'
            return 0 ;;
        *)
            reply 500 "Internal Server Error" '{"status":"error","message":"deploy.sh absent de l archive (refus)"}'
            return 0 ;;
    esac

    if tar -xzf "$PKG" -C "$USB" 2>/dev/null || busybox tar -xzf "$PKG" -C "$USB" 2>/dev/null; then
        VER="$(sed -n 's/^version *: *//p' "$USB/scripts/VERSION" 2>/dev/null | head -n 1)"
        log "APPLY_DPK OK: $NAME -> $USB (version cle : ${VER:-?})"
        json_reply "ok" "archive extraite sur la cle (version scripts : ${VER:-?}) ; ensuite : deploy INSTALL puis REBOX"
    else
        reply 500 "Internal Server Error" '{"status":"error","message":"extraction echouee"}'
    fi
}

# traite la requete GET courante (variables REQUEST/COMMAND deja extraites)
# et ecrit la reponse HTTP sur stdout -> pipee vers nc -> socket navigateur
handle_request()
{
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
                reply 404 "Not Found" '{"status":"error","message":"config introuvable"}'
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
                reply 404 "Not Found" '{"status":"error","message":"conf_check introuvable"}'
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

        # reponse synchrone : rapport materiel complet (recherche puces/net)
        # + ecriture sur la cle pour telechargement direct via httpd 8000
        HW_REPORT)
            SRC=""
            if [ -f /data/scripts/hw_report.sh ]; then
                SRC="/data/scripts/hw_report.sh"
            elif [ -f "$USB/scripts/hw_report.sh" ]; then
                SRC="$USB/scripts/hw_report.sh"
            fi

            if [ -z "$SRC" ]; then
                log "COMMANDE REJECTED: HW_REPORT (hw_report.sh introuvable)"
                reply 404 "Not Found" '{"status":"error","message":"hw_report introuvable"}'
            else
                OUT="$(sh "$SRC" SAVE 2>&1)"
                RC=$?
                log "COMMANDE ACCEPTED: HW_REPORT (rc=$RC)"
                if [ -f "$USB/log/hardware_latest.txt" ]; then
                    R_="$(cat "$USB/log/hardware_latest.txt" 2>/dev/null)"
                    BODY="${R_}

--- rapport sauvegarde sur la cle : /log/hardware_latest.txt
--- telechargement direct       : http://<ip-box>:8000/log/hardware_latest.txt"
                    reply 200 OK "$BODY" "text/plain; charset=utf-8"
                else
                    reply 200 OK "$OUT" "text/plain; charset=utf-8"
                fi
            fi
            ;;

        HELP|SEND_LOGS|PURGE_LOG|SYNC|FIELD_OFF|FIELD_ON|HDMI_OFF|HDMI_ON|PANEL|STATE|REBOX|ROTATE_LOGS|ECO_MODE|PERF_MODE|VITALS|RECETTE|RECETTE_P1|RECETTE_P2|RECETTE_P3|RECETTE_P4|RECETTE_P5|RECETTE_P6|RECETTE_P7|RECETTE_RETOUR|RECETTE_MANIFEST)
            touch "$INCOMING/$COMMAND"
            log "COMMANDE ACCEPTED: $COMMAND"

            reply 200 OK "{\"status\":\"ok\",\"command\":\"$COMMAND\"}"
            ;;

        # reponse synchrone : donnees statiques systeme (page Infos)
        SYS_INFO)
            OUT_="=== SYSTEME ==="
            for P_ in ro.product.device ro.product.model ro.product.brand \
                      ro.build.version.release ro.build.version.sdk \
                      ro.build.version.security_patch ro.build.version.incremental \
                      ro.hardware ro.board.platform; do
                V_="$(getprop "$P_" 2>/dev/null)"
                [ -n "$V_" ] && OUT_="$OUT_
$P_ = $V_"
            done
            OUT_="$OUT_

kernel : $(cat /proc/version 2>/dev/null)"
            UP_="$(cut -d. -f1 /proc/uptime 2>/dev/null | tr -dc '0-9')"
            if [ -n "${UP_:-}" ]; then
                OUT_="$OUT_
uptime : $((UP_ / 86400))j $((UP_ % 86400 / 3600))h $((UP_ % 3600 / 60))m"
            fi
            MEM_="$(sed -n 's/^MemTotal: *\([0-9]*\) kB/\1/p' /proc/meminfo 2>/dev/null | head -n 1)"
            [ -n "$MEM_" ] && OUT_="$OUT_
ram    : $((MEM_ / 1024)) Mo"
            GV_="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)"
            GF_="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null)"
            [ -n "$GV_" ] && OUT_="$OUT_
cpu    : $GV_${GF_:+ @ $((GF_ / 1000)) MHz}"
            DF_="$(df -h /data 2>/dev/null | tail -n 1 | awk '{print $3 "/" $2 " (" $5 ")"}')"
            [ -n "$DF_" ] && OUT_="$OUT_
/data  : $DF_"

            log "COMMANDE ACCEPTED: SYS_INFO"
            reply 200 OK "$OUT_" "text/plain; charset=utf-8"
            ;;

        # reponse synchrone : horloge de la box (epoch + lisible)
        BOX_TIME)
            E_="$(date +%s 2>/dev/null | tr -dc '0-9')"
            H_="$(date '+%Y-%m-%d %H:%M:%S')"
            log "COMMANDE ACCEPTED: BOX_TIME ($H_)"
            reply 200 OK "{\"status\":\"ok\",\"epoch\":${E_:-0},\"box_time\":\"$H_\"}"
            ;;

        # console distante (equivalent adb shell) : une ligne, sortie bornee.
        # Double garde : WEB_RUN=1 dans device.conf ET token obligatoire.
        RUN)
            CFG_F=""
            if [ -f /data/scripts/config/device.conf ]; then
                CFG_F=/data/scripts/config/device.conf
            elif [ -f "$USB/scripts/config/device.conf" ]; then
                CFG_F="$USB/scripts/config/device.conf"
            fi
            WEB_RUN=""
            [ -n "$CFG_F" ] && WEB_RUN="$(sed -n 's/^WEB_RUN=//p' "$CFG_F" 2>/dev/null | head -n 1 | tr -d '\r')"
            if [ "$WEB_RUN" != "1" ] || [ ! -f "$TOKEN_FILE" ]; then
                log "COMMANDE REJECTED: RUN (WEB_RUN='${WEB_RUN:-vide}', token=$([ -f "$TOKEN_FILE" ] && echo oui || echo non))"
                reply 403 Forbidden '{"status":"error","message":"console desactivee : WEB_RUN=1 dans device.conf et token actif requis"}'
            else
                CMD_="$(printf '%s' "$REQUEST" | sed -n 's#.*[?&]cmd=\([^ &]*\).*#\1#p')"
                CMD_="$(busybox httpd -d "$CMD_" 2>/dev/null || printf '%s' "$CMD_")"
                log "RUN: $CMD_"
                if command -v timeout > /dev/null 2>&1; then
                    OUT="$(timeout 15 sh -c "$CMD_" 2>&1)"
                else
                    OUT="$(sh -c "$CMD_" 2>&1)"
                fi
                RC_RUN=$?
                OUT="$(printf '%s' "$OUT" | head -c 8192)"
                log "RUN rc=$RC_RUN ($(printf '%s' "$OUT" | wc -c) octets)"
                reply 200 OK "rc=$RC_RUN
$OUT" "text/plain; charset=utf-8"
            fi
            ;;

        *)
            log "COMMANDE REJECTED: inconnue"

            reply 404 "Not Found" '{"status":"error","message":"unknown command"}'
            ;;
    esac
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

    # attente de l'arrivee de la requete : sleep fractionnaire si supporte,
    # sinon pas de 1 s (borne courte : une connexion oisive ne doit pas
    # monopoliser le slot unique - les navigateurs ouvrent des preconnect)
    if sleep 0.1 2>/dev/null; then STEP="0.1"; MAX=25; else STEP="1"; MAX=3; fi

    # ceinture de securite globale par connexion (transferts inclus)
    RUNNC="busybox nc"
    command -v timeout > /dev/null 2>&1 && RUNNC="timeout 180 busybox nc"

    FIFO="/data/local/tmp/control_resp"

    while true
    do
        rm -f "$TMP_REQ"
        rm -f "$FIFO"
        mkfifo "$FIFO" 2>/dev/null || { sleep 1; continue; }

        # Le handler tourne en DETACHE et ecrit dans le FIFO : il traque
        # l'arrivee de la requete puis produit la reponse. nc sert de pont
        # FIFO -> socket. Une connexion oisive coute ~2 s (le handler ferme
        # le FIFO, nc sort), pas 90 s.
        {
            i=0
            while [ ! -s "$TMP_REQ" ] && [ "$i" -lt "$MAX" ]; do
                sleep "$STEP"
                i=$((i + 1))
            done
            sleep "$STEP"

            REQUEST="$(head -n 1 "$TMP_REQ" 2>/dev/null)"

            if [ -n "$REQUEST" ]; then

                # preflight eventuel du navigateur : reponse seche avec CORS
                case "$REQUEST" in
                    OPTIONS*)
                        printf 'HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: *\r\nContent-Length: 0\r\nConnection: close\r\n\r\n'
                        ;;
                    POST*)
                        # depot de fichiers sur la cle (dpk/sha256/txt...)
                        if [ -f "$TOKEN_FILE" ]; then
                            TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE" 2>/dev/null)"
                            GOT="$(printf '%s' "$REQUEST" | sed -n 's#.*token=\([0-9a-zA-Z]*\).*#\1#p')"
                            if [ -z "$GOT" ] || [ "$GOT" != "$TOKEN" ]; then
                                log "UPLOAD REJETE: token invalide"
                                reply 403 Forbidden '{"status":"error","message":"forbidden"}'
                            else
                                handle_post
                            fi
                        else
                            handle_post
                        fi
                        ;;
                    *)
                        COMMAND="$(printf '%s' "$REQUEST" | sed -n 's#GET /api/\([^ ?]*\).*#\1#p')"

                        # application d'un dpk depose sur la cle
                        if [ "$COMMAND" = "APPLY_DPK" ]; then
                            if [ -f "$TOKEN_FILE" ]; then
                                TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE" 2>/dev/null)"
                                GOT="$(printf '%s' "$REQUEST" | sed -n 's#.*token=\([0-9a-zA-Z]*\).*#\1#p')"
                                if [ -z "$GOT" ] || [ "$GOT" != "$TOKEN" ]; then
                                    log "APPLY_DPK REJETE: token invalide"
                                    reply 403 Forbidden '{"status":"error","message":"forbidden"}'
                                    COMMAND=""
                                fi
                            fi
                            [ -n "$COMMAND" ] && { apply_dpk "$REQUEST" ; COMMAND="" ; }
                        fi

                        if [ -n "$COMMAND" ]; then
                            if [ -f "$TOKEN_FILE" ]; then
                                TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE" 2>/dev/null)"
                                GOT="$(printf '%s' "$REQUEST" | sed -n 's#.*token=\([0-9a-zA-Z]*\).*#\1#p')"
                                if [ -z "$GOT" ] || [ "$GOT" != "$TOKEN" ]; then
                                    log "REQUEST REJECTED: token invalide (${COMMAND:-<inconnu>})"
                                    reply 403 Forbidden '{"status":"error","message":"forbidden"}'
                                else
                                    handle_request
                                fi
                            else
                                handle_request
                            fi
                        fi
                        ;;
                esac

            fi
        } > "$FIFO" &
        HP="$!"

        $RUNNC -l -p "$PORT" < "$FIFO" > "$TMP_REQ" 2>/dev/null

        # si nc est sorti avant le handler (timeout, client parti), lui
        # laisser <= 3 s de grace puis terminer (pas de zombie qui s'accumule)
        k=0
        while kill -0 "$HP" 2>/dev/null && [ "$k" -lt 30 ]; do
            sleep 0.1
            k=$((k + 1))
        done
        kill "$HP" 2>/dev/null
        wait "$HP" 2>/dev/null

        rm -f "$FIFO"
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
