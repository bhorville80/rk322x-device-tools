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

# racine = CLE en priorite (scan media_rw), fallback repertoire du script :
# lance depuis /data/scripts/server (pile installlee), dirname aurait fait
# ecrire logs/pidfiles/shots dans /data/scripts -> invisibles a SEND_LOGS
# (srv_logs ne lit que <cle>/log) et a deploy STOP (pidfiles <cle>/server),
# pendant que le panneau servi par httpd reste la cle. Temoin terrain :
# CONTROL STARTED trace par start_server mais ni control_server.log ni
# gui_server.log sur la cle.
USB=""
for d in /mnt/media_rw/*; do
    if [ -f "$d/deploy.sh" ]; then
        USB="$d"
        break
    fi
done
if [ -z "$USB" ]; then
    USB="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)"
    [ -f "$USB/deploy.sh" ] || USB=""
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
TMP_REQ="/data/local/tmp/gui_request"

mkdir -p "$USB/server" "$USB/log" "$SHOTS_DIR"

log()
{
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
}

# port en ecoute ? netstat, sinon /proc/net/tcp (hexa, etat 0A=LISTEN)
port_up()
{
    P_="$1"
    if command -v netstat > /dev/null 2>&1; then
        netstat -tln 2>/dev/null | grep -q ":$P_ " && return 0
    fi
    PH="$(printf '%04X' "$P_" 2>/dev/null)"
    [ -n "$PH" ] || return 1
    grep -qi ":$PH .* 0A " /proc/net/tcp  2>/dev/null && return 0
    grep -qi ":$PH .* 0A " /proc/net/tcp6 2>/dev/null && return 0
    return 1
}

case "$1" in
    start) ;;
    *)     echo "Usage: sh $0 start" ; exit 1 ;;
esac

if [ -f "$PIDFILE" ]; then
    PID="$(cat "$PIDFILE" 2>/dev/null)"
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        # un pid vivant ne prouve pas le service : une boucle sh dont le nc
        # est mort repond ALREADY RUNNING sans ouvrir le port, et la reprise
        # d'orphelin ci-dessous n'etait JAMAIS atteinte (temoin terrain :
        # 8081 "deja actif" muet, aucune trace nulle part). Port verifie :
        # up -> sortie normale ; muet -> on abat ce PID et on ENCHAINE vers
        # la reprise au lieu de sortir.
        if port_up "$PORT"; then
            log "DEJA ACTIF (PID $PID), port $PORT en ecoute"
            echo "GUI SERVER ALREADY RUNNING"
            echo "PID: $PID"
            exit 0
        fi
        log "PID $PID vivant MAIS port $PORT muet -> reprise orphelin"
        kill "$PID" 2>/dev/null
        sleep 1
        kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null
    fi
    rm -f "$PIDFILE"
fi

# --- reprise d'orphelin -----------------------------------------------------
# Un nc en ecoute sur $PORT sans boucle serveur vivante (cle debranchee entre
# deux, pidfile perdu) garde le bind SANS traiter la moindre requete
# (temoin recette v18 : 8081 "up" aux sondes TCP mais SHOT muet -> ecran TV
# jamais affiche sur la telecommande). Avant d'ouvrir notre boucle on vise
# les restes de CE serveur (boucle sh + listener nc) ; si le port reste tenu
# apres ca, c'est un processus etranger -> echec CLAIR plutot que bind mort.
if port_up "$PORT"; then
    K_=0
    for D in /proc/[0-9]*; do
        P_="${D#/proc/}"
        [ "$P_" = "$$" ] && continue
        [ -r "$D/cmdline" ] || continue
        C="$(tr '\0' ' ' < "$D/cmdline" 2>/dev/null)"
        case "$C" in
            *gui_server.sh*|*"nc -l -p $PORT"*|*"nc -lp $PORT"*) ;;
            *) continue ;;
        esac
        if kill "$P_" 2>/dev/null; then
            K_=$((K_+1))
            log "ORPHELIN arrete (PID $P_) avant demarrage"
        fi
    done
    [ "$K_" -gt 0 ] && sleep 1
    if port_up "$PORT"; then
        log "DEMARRAGE IMPOSSIBLE : port $PORT encore tenu par un processus etranger"
        echo "GUI SERVER FAILED"
        echo "PORT: $PORT occupe par un processus non kit (deploy STOP puis retry, sinon reboot)"
        exit 1
    fi
    [ "$K_" -gt 0 ] && log "REPRISE ORPHELIN : port $PORT libere ($K_ processus arretes)"
fi

# sockets residuels hors LISTEN (TIME_WAIT ~60 s apres du trafic SHOT) :
# ils bloquent le rebind d'un nc sans SO_REUSEADDR -> vidange avant ouverture
tw_count()
{
    H_="$(printf '%04X' "$PORT" 2>/dev/null)"
    [ -n "$H_" ] || { printf '0' ; return 0 ; }
    N_=0
    for F_ in /proc/net/tcp /proc/net/tcp6; do
        [ -f "$F_" ] || continue
        C_="$(awk -v p=":${H_}$" '$2 ~ p && $4 != "0A" {n++} END {printf "%d", n}' "$F_" 2>/dev/null)"
        [ -n "$C_" ] && N_=$((N_ + C_))
    done
    printf '%d' "$N_"
}

wait_drain()
{
    i_=0
    while [ "$i_" -lt 30 ]; do
        N_="$(tw_count)"
        [ "${N_:-0}" -le 0 ] && return 0
        [ "$i_" -eq 0 ] && \
            log "port $PORT : ${N_} socket(s) residuel(s) (TIME_WAIT), attente de vidange (max 60 s)..."
        sleep 2
        i_=$((i_ + 1))
    done
    N_="$(tw_count)"
    [ "${N_:-0}" -gt 0 ] && \
        log "port $PORT : encore ${N_} residu(s) apres 60 s -> premier bind possiblement refuse, la boucle reessaie"
    return 0
}

reply()
{
    # reply <code> <status> <body> ; CORS : panneau sur :8000, API ici :8081
    # Content-Length en OCTETS (wc -c), pas ${#var} (tronquerait l'UTF-8)
    LEN="$(printf '%s' "$3" | wc -c | tr -dc '0-9')"
    printf 'HTTP/1.1 %s %s\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s' \
        "$1" "$2" "$LEN" "$3"
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

# traite la requete courante (variables REQUEST/ACTION/QS deja extraites) et
# ecrit la reponse HTTP sur stdout -> pipee vers nc -> socket navigateur
handle_request()
{
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
                    # trace indispensable : sans elle un echec screencap est
                    # invisible cote box (panneau : seule l'image manque)
                    SZ_="$(wc -c < "$OUT" 2>/dev/null | tr -dc '0-9')"
                    log "SHOT ECHOUE : screencap en echec ou fichier vide ($SZ_:0 octets) -> $OUT"
                    ko "capture vide"
                fi
            else
                log "SHOT ECHOUE : binaire screencap absent du firmware"
                ko "screencap absent"
            fi
            ;;

        "")
            log "REJET requete sans action : ${REQUEST:-<ligne vide>}"
            ko "action absente"
            ;;

        *)
            log "REJET action inconnue : $ACTION"
            reply 404 "Not Found" '{"status":"error","message":"unknown action"}'
            ;;
    esac
}

(
    # immunise contre SIGHUP : la fermeture de la session adb ne doit pas
    # tuer le service lance en arriere-plan
    trap '' HUP

    # attente de l'arrivee de la requete : sleep fractionnaire si supporte,
    # sinon pas de 1 s (bornes ajustees pour ~6 s d'attente max)
    if sleep 0.1 2>/dev/null; then STEP="0.1"; MAX=50; else STEP="1"; MAX=6; fi

    # timeout dispo ? ceinture de securite si un client reste connecte
    # sans lire pendant un traitement (am start, screencap)
    RUNNC="busybox nc"
    command -v timeout > /dev/null 2>&1 && RUNNC="timeout 90 busybox nc"

    while true
    do
        rm -f "$TMP_REQ"

        # La reponse est PIPEE DANS nc : elle part reellement sur la socket
        # tant que la connexion est ouverte. nc ecrit la requete recue dans
        # TMP_REQ ; on ne genere la reponse qu'APRES son arrivee complete.
        {
            i=0
            while [ ! -s "$TMP_REQ" ] && [ "$i" -lt "$MAX" ]; do
                sleep "$STEP"
                i=$((i + 1))
            done
            sleep "$STEP"

            REQUEST="$(head -n 1 "$TMP_REQ" 2>/dev/null)"

            if [ -n "$REQUEST" ]; then

                ACTION="$(printf '%s' "$REQUEST" | sed -n 's#GET /gui/\([^ ?]*\).*#\1#p')"
                QS="$(printf '%s' "$REQUEST" | sed -n 's#GET /gui/[^ ?]*?\([^ ]*\).*#\1#p')"

                if [ -f "$TOKEN_FILE" ]; then
                    TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE" 2>/dev/null)"
                    GOT="$(param token)"
                    GOT="$(printf '%s' "$GOT" | tr -cd '0-9a-zA-Z')"
                    if [ -z "$GOT" ] || [ "$GOT" != "$TOKEN" ]; then
                        log "REJET token invalide (${ACTION:-<inconnu>})"
                        reply 403 Forbidden '{"status":"error","message":"forbidden"}'
                    else
                        handle_request
                    fi
                else
                    handle_request
                fi

            fi
        } | $RUNNC -l -p "$PORT" > "$TMP_REQ" 2>/dev/null

        rm -f "$TMP_REQ"
    done
) >> "$LOG" 2>&1 &

PID="$!"
echo "$PID" > "$PIDFILE"

# un port deja en ecoute SANS pidfile vivant = orphelin suspect : le bind
# ci-dessous echouera silencieusement, d'ou ce constat ante (cf manage :
# 8081 en ecoute alors que la pile etait arretee)
WAS_UP=0
if port_up "$PORT"; then
    WAS_UP=1
    log "GUI : port $PORT DEJA en ecoute avant demarrage (orphelin ? deploy STOP)"
fi

wait_drain

sleep 1

if kill -0 "$PID" 2>/dev/null; then
    echo "GUI SERVER STARTED"
    echo "PID: $PID"
    echo "PORT: $PORT"

    # le pid vivant ne prouve pas le bind : verdict sur l'ecoute reelle,
    # trace dans gui_server.log (un echec n'apparait plus nulle part sinon)
    UP_=""
    for W_ in 1 2 3; do
        if port_up "$PORT"; then UP_="oui"; break; fi
        sleep 1
    done
    case "$UP_" in
        "")  R_="$(tw_count)"
             log "GUI : ATTENTION port $PORT NON ouvert (bind refuse)${R_:+ -- $R_ residu(s) TIME_WAIT, la boucle reessaie}" ;;
        oui) if [ "$WAS_UP" -eq 1 ]; then
                 log "GUI : port $PORT en ecoute MAIS l'etait deja avant (bind incertain, orphelin possible)"
             else
                 log "GUI : port $PORT en ecoute (verifie)"
             fi ;;
    esac

    [ -f "$TOKEN_FILE" ] && echo "SECURITE: token requis (?token=...)"
else
    echo "GUI SERVER FAILED"
    rm -f "$PIDFILE"
    exit 1
fi
