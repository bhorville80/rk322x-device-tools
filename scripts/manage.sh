#!/system/bin/sh
# manage - point d'entree unique etat/gestion des services et du web.
#
# Delegue aux outils existants (aucune logique re-implantee) :
#   wifi/bt      -> disable_wireless
#   ssh          -> server/ssh_server.sh
#   pile web     -> deploy.sh EXPOSE/STOP/TOKEN + sondes locales
#   diagnostics  -> check_state / net_diag / run_state (rappels en fin d'aide)
#
# Usage:
#   manage                    apercu global : services + web + ports (1 page)
#   manage service            detail services + actions possibles
#   manage service <action>   wifi-off|wifi-on|ssh-start|ssh-stop|ssh-status
#   manage web                sante de la pile web exposee
#   manage web <action>       expose|stop|restart|token-status
#   manage ports              ports connus de la box et etat d'ecoute
#   manage HELP               cette aide

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

BASE="$(cd "$(dirname "$0")" && pwd)"

KEY=""
for d in /mnt/media_rw/*; do
    [ -f "$d/deploy.sh" ] && { KEY="$d"; break; }
done

DEPLOY_SH=""
for F in "$BASE/deploy.sh" /data/scripts/deploy.sh "$KEY/deploy.sh"; do
    [ -f "$F" ] && DEPLOY_SH="$F" && break
done

SSH_SH=""
for F in "$BASE/server/ssh_server.sh" /data/scripts/server/ssh_server.sh; do
    [ -f "$F" ] && SSH_SH="$F" && break
done

WL_SH=""
for F in "$BASE/disable_wireless.sh" /data/scripts/disable_wireless.sh; do
    [ -f "$F" ] && WL_SH="$F" && break
done

ok_ko()   { printf '  [%s] %s\n' "$1" "$2"; }

# sonde port local : netstat, sinon /proc/net/tcp (hexa, 0A=LISTEN)
port_up()
{
    P_="$1"
    if command -v netstat > /dev/null 2>&1; then
        netstat -tln 2>/dev/null | grep -q ":$P_ " && return 0
    fi
    if command -v busybox > /dev/null 2>&1; then
        PH="$(busybox printf '%04X' "$P_" 2>/dev/null)"
    else
        PH="$(printf '%04X' "$P_" 2>/dev/null)"
    fi
    [ -n "$PH" ] || return 1
    grep -qi ":$PH .* 0A " /proc/net/tcp  2>/dev/null && return 0
    grep -qi ":$PH .* 0A " /proc/net/tcp6 2>/dev/null && return 0
    return 1
}

pid_alive()
{
    # $1 fichier pid -> rc 0 si processus vivant
    P_="$(cat "$1" 2>/dev/null | tr -dc '0-9')"
    [ -n "$P_" ] && kill -0 "$P_" 2>/dev/null
}

ports_table()
{
    echo ""
    echo "--- Ports connus ---"
    printf '  %-6s %-10s %-8s %s\n' "PORT" "SERVICE" "ETAT" "ORIGINE"
    for ENTRY in \
        "5555|adb|adbd (USB/reseau developpeur)" \
        "2222|ssh|dropbear (server/ssh_server)" \
        "8000|panneau|busybox httpd (cle servie)" \
        "8080|api|control_server.sh" \
        "8081|gui|gui_server.sh (telecommande TV)" ; do
        P_="$(printf '%s' "$ENTRY" | cut -d'|' -f1)"
        S_="$(printf '%s' "$ENTRY" | cut -d'|' -f2)"
        O_="$(printf '%s' "$ENTRY" | cut -d'|' -f3)"
        if port_up "$P_"; then E_="ECOUTE" ; else E_="--" ; fi
        printf '  %-6s %-10s %-8s %s\n' "$P_" "$S_" "$E_" "$O_"
    done
}

web_page()
{
    echo ""
    echo "--- Pile web ---"

    PIDDIR="${KEY:-}"
    [ -z "$PIDDIR" ] && PIDDIR="/data/local/tmp"
    NB_PID=0
    for PF in "$PIDDIR/server/server.pid" "$PIDDIR/server/control_server.pid" \
              "$PIDDIR/server/gui_server.pid"; do
        [ -f "$PF" ] || continue
        N_="$(basename "$PF" .pid)"
        if pid_alive "$PF"; then ok_ko OK "$N_ actif ($(cat "$PF"))"
        else ok_ko KO "$N_ pid mort ($(cat "$PF" 2>/dev/null)) - deploy STOP puis EXPOSE"; fi
        NB_PID=$((NB_PID+1))
    done
    [ "$NB_PID" -eq 0 ] && echo "  [--] aucun pidfile ($PIDDIR/server/) - pile probablement arretee"

    port_up 8000 && ok_ko OK "port 8000 (panneau) en ecoute" \
                 || ok_ko KO "port 8000 absent"
    port_up 8080 && ok_ko OK "port 8080 (api) en ecoute" \
                 || ok_ko KO "port 8080 absent"
    port_up 8081 && ok_ko OK "port 8081 (gui) en ecoute" \
                 || ok_ko KO "port 8081 absent"

    if command -v busybox > /dev/null 2>&1; then
        IDX_="$(timeout 8 busybox wget -qO- http://127.0.0.1:8000/index.html 2>/dev/null | grep -c RK322X)"
        case "${IDX_:-0}" in
            ''|0) ok_ko KO "panneau : index.html sans marque RK322X" ;;
            *)    ok_ko OK "panneau : index.html servi" ;;
        esac
        API_="$(timeout 8 busybox wget -qO- http://127.0.0.1:8080/api/HELP 2>/dev/null | head -c 60)"
        case "$API_" in
            *status*)  ok_ko OK "api : HELP repond" ;;
            "")        if [ -f "${KEY:-/x}/server/token" ]; then
                             ok_ko OK "api : protégée par token (403 attendu sans token)"
                       else
                             ok_ko KO "api : aucune reponse HELP"
                       fi ;;
            *)         ok_ko OK "api : reponse recue" ;;
        esac
    fi

    if [ -f "${KEY:-/x}/server/token" ]; then
        ok_ko "--" "token actif sur 8080/8081 (deploy TOKEN STATUS pour details)"
    else
        ok_ko "--" "token absent (API ouverte sur le reseau local)"
    fi
}

service_page()
{
    echo ""
    echo "--- Services ---"

    if [ -n "$WL_SH" ]; then
        OUT_="$(sh "$WL_SH" STATUS 2>/dev/null)"
        WIFI_="$(printf '%s\n' "$OUT_" | sed -n 's/[Ww]i-[Ff]i[^:]*: */p')"
        case "$OUT_" in
            *"desactive"*|*"desactiv"*) ok_ko OK "wifi/bt : desactives (disable_wireless STATUS)" ;;
            *)                          ok_ko -- "wifi/bt : verifier (manage service ssh-status equiv.)" ;;
        esac
    else
        ok_ko KO "disable_wireless introuvable"
    fi

    if [ -n "$SSH_SH" ]; then
        if sh "$SSH_SH" STATUS > /dev/null 2>&1; then
            ok_ko OK "ssh dropbear actif (2222)"
        else
            ok_ko -- "ssh dropbear inactif (ssh-start pour demarrer)"
        fi
    else
        ok_ko KO "ssh_server.sh introuvable"
    fi

    for TOOL in front_digit motd; do
        TS_="$BASE/$TOOL.sh"
        [ -f "$TS_" ] || TS_="/data/scripts/$TOOL.sh"
        if [ -f "$TS_" ] && sh "$TS_" STATUS > /dev/null 2>&1; then
            ok_ko OK "$TOOL actif"
        else
            ok_ko -- "$TOOL inactif/absent"
        fi
    done
}

service_action()
{
    A="$1"
    case "$A" in
        wifi-off)
            [ -n "$WL_SH" ] && sh "$WL_SH" OFF && return 0
            echo "[ERREUR] disable_wireless introuvable" ; return 1 ;;
        wifi-on)
            [ -n "$WL_SH" ] && sh "$WL_SH" ON && return 0
            echo "[ERREUR] disable_wireless introuvable" ; return 1 ;;
        ssh-start)
            [ -n "$SSH_SH" ] && sh "$SSH_SH" START && return 0
            echo "[ERREUR] ssh_server.sh introuvable" ; return 1 ;;
        ssh-stop)
            [ -n "$SSH_SH" ] && sh "$SSH_SH" STOP && return 0
            echo "[ERREUR] ssh_server.sh introuvable" ; return 1 ;;
        ssh-status)
            [ -n "$SSH_SH" ] && sh "$SSH_SH" STATUS && return 0
            echo "[ERREUR] ssh_server.sh introuvable" ; return 1 ;;
        *)
            echo "action service inconnue : $A"
            echo "actions : wifi-off | wifi-on | ssh-start | ssh-stop | ssh-status"
            return 1 ;;
    esac
}

web_action()
{
    A="$1"
    if [ -z "$DEPLOY_SH" ]; then
        echo "[ERREUR] deploy.sh introuvable"
        return 1
    fi
    case "$A" in
        expose)       sh "$DEPLOY_SH" EXPOSE ;;
        stop)         sh "$DEPLOY_SH" STOP ;;
        restart)      sh "$DEPLOY_SH" STOP && sleep 2 && sh "$DEPLOY_SH" EXPOSE ;;
        token-status) sh "$DEPLOY_SH" TOKEN STATUS ;;
        *)
            echo "action web inconnue : $A"
            echo "actions : expose | stop | restart | token-status"
            return 1 ;;
    esac
}

help_show()
{
    echo ""
    echo "=== MANAGE - etat & gestion services/web ==="
    echo ""
    echo "Usage:"
    echo "  manage                    apercu global (services + web + ports)"
    echo "  manage service            detail services"
    echo "  manage service <action>   wifi-off | wifi-on | ssh-start |"
    echo "                            ssh-stop | ssh-status"
    echo "  manage web                sante pile web (ports/panneau/api/token)"
    echo "  manage web <action>       expose | stop | restart | token-status"
    echo "  manage ports              table des ports connus"
    echo "  manage HELP               cette aide"
    echo ""
    echo "Pour aller plus loin (outils dedies, pas de doublon ici) :"
    echo "  check_state    verdict complet boitier/reseau/hdmi"
    echo "  net_diag PORTS connectivite reseau detaillee"
    echo "  deploy STATUS  etat installation vs cle"
    echo "  run_state      traces d'execution des outils"
}

main()
{
    case "$1" in
        ""|overview)
            echo "=== MANAGE BOX - $(date '+%Y-%m-%d %H:%M:%S') ==="
            service_page
            web_page
            ports_table
            echo ""
            ;;
        service)
            case "$2" in
                "")             service_page ;;
                wifi-off|wifi-on|ssh-start|ssh-stop|ssh-status)
                                service_action "$2" ;;
                *)              echo "action service inconnue : $2 (manage HELP)" ; return 1 ;;
            esac
            ;;
        web)
            case "$2" in
                "")                                     web_page ;;
                expose|stop|restart|token-status)       web_action "$2" ;;
                *)              echo "action web inconnue : $2 (manage HELP)" ; return 1 ;;
            esac
            ;;
        ports)
            ports_table
            echo ""
            ;;
        HELP|-h|--help)
            help_show
            ;;
        *)
            echo "sujet inconnu : $1 (voir : manage HELP)"
            return 1
            ;;
    esac
    return 0
}

if [ "$RUNLOG_LOADED" -eq 1 ] && runlog_start "$SCRIPT_ID"; then
    main "$@" >> "$RUNLOG_FILE" 2>&1
    RC=$?
    runlog_end "$RC"
    cat "$RUNLOG_FILE"
else
    main "$@"
    RC=$?
fi
exit "$RC"
