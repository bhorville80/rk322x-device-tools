#!/system/bin/sh
# net_watch - surveillance reseau temps reel, zero dependance.
#
# Analyse /proc/net/tcp (+tcp6) : etats de connexions, top clients,
# nouvelles IP, alertes (half-open = scan, IP bavarde), et blocage
# iptables. Rien a installer, tourne en quelques centaines de Ko.
#
#   net_watch STATUS                 snapshot instantane
#   net_watch WATCH [s] [duree_s]    boucle visible (defaut 5 s x 60)
#   net_watch DAEMON [s]             meme boucle en arriere-plan (csv+events)
#   net_watch STOP                   arrete le daemon
#   net_watch LOGSCAN [seuil]        comportemental : IP agressives dans les
#                                    logs serveurs (defaut seuil 20)
#   net_watch BAN <ip> | UNBAN <ip>  blocage iptables INPUT
#   net_watch BANS                   liste des blocages actifs
#
# Sorties daemon : log/net_watch_<ts>/watch.csv + events.log sur la cle.

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" "$(dirname "$0")/.." /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

PIDFILE="/data/local/tmp/net_watch.pid"
HALF_OPEN_MAX="${NET_WATCH_HALF_OPEN_MAX:-40}"

state_name()
{
    case "$1" in
        01) echo ESTAB ;;   02) echo SYNSENT ;; 03) echo SYNRECV ;;
        06) echo TIMEDWAIT ;; 0A) echo LISTEN ;; *) echo "$1" ;;
    esac
}

hex_ip()
{
    H="$1"
    case "$H" in
        ''|*[!0-9A-Fa-f]*) echo "0.0.0.0"; return ;;
        ???*) ;;
        *) echo "0.0.0.0"; return ;;
    esac
    B1=$((16#${H:6:2})); B2=$((16#${H:4:2}))
    B3=$((16#${H:2:2})); B4=$((16#${H:0:2}))
    printf '%d.%d.%d.%d' "$B1" "$B2" "$B3" "$B4"
}

hex_port() { printf '%d' "0x$1"; }

conns_raw()
{
    # sortie : lport rip rport st  (ipv4+ipv6)
    cat /proc/net/tcp /proc/net/tcp6 2>/dev/null | tail -n +2 | \
    while read -r _ SL LOCAL REM REST; do
        [ -n "${LOCAL:-}" ] || continue
        LP="${LOCAL##*:}"
        RI="${REM%%:*}"
        RP="${REM##*:}"
        set -- ${REST:-}
        ST="$(state_name "${1:-00}")"
        printf '%s %s %s %s\n' "$(hex_port "$LP")" "$(hex_ip "$RI")" "$(hex_port "$RP")" "$ST"
    done 2>/dev/null
}

snapshot_block()
{
    echo "-- $(date '+%Y-%m-%d %H:%M:%S') --"
    TOT="$(conns_raw | grep -cv '^LISTEN$')"
    printf '  connexions      : %s\n' "${TOT:-0}"
    for S in ESTAB SYNRECV SYNSENT TIMEDWAIT; do
        NB="$(conns_raw | grep -c "^$S\$")"
        case "$S" in
            SYNRECV|SYNSENT) TAG="half-open ($S)" ;;
            *) TAG="$S" ;;
        esac
        [ "${NB:-0}" -gt 0 ] && printf '  %-15s : %s\n' "$TAG" "$NB"
    done
    TOP="$(conns_raw | grep -v ' LISTEN$' | cut -d' ' -f2 | grep -vE '^(0\.|127\.)' | sort | uniq -c | sort -rn | head -n 5)"
    if [ -n "$TOP" ]; then
        echo "  top distants    :"
        printf '%s\n' "$TOP" | while read -r N IP; do
            printf '    %-5s %s\n' "$N" "$IP"
        done
    fi
}

do_status()
{
    echo ""
    echo "=== NET WATCH STATUS ==="
    DPID=""
    [ -f "$PIDFILE" ] && { DPID="$(cat "$PIDFILE" 2>/dev/null)"; kill -0 "$DPID" 2>/dev/null || DPID=""; }
    echo "  Daemon       : ${DPID:+actif (PID $DPID)}${DPID:-inactif}"
    echo ""
    snapshot_block
    echo ""
    return 0
}

alert_check()
{
    HO="$(conns_raw | grep -cE '^(SYNRECV|SYNSENT)$')"
    [ "${HO:-0}" -gt "$HALF_OPEN_MAX" ] && \
        echo "[ALERTE] $(date '+%H:%M:%S') half-open=${HO} (seuil $HALF_OPEN_MAX) : scan possible ?"

    BUSY="$(conns_raw | grep -E ' (ESTAB|SYNRECV)$' | cut -d' ' -f2 | grep -vE '^(0\.|127\.)' | sort | uniq -c | sort -rn | head -n 1)"
    NB_="$(printf '%s' "$BUSY" | tr -dc '0-9')"
    IP_="$(printf '%s' "$BUSY" | tr -dc '0-9.')"
    case "$NB_" in ''|0) return 0 ;; esac
    [ "$NB_" -gt 25 ] && [ -n "$IP_" ] && \
        echo "[ALERTE] $(date '+%H:%M:%S') ip $IP_ : $NB_ connexions actives (brute force ?)"
    return 0
}

watch_once_csv()
{
    T="$(date '+%Y-%m-%d %H:%M:%S')"
    E="$(conns_raw | grep -c '^ESTAB$')"
    H="$(conns_raw | grep -cE '^(SYNRECV|SYNSENT)$')"
    TW="$(conns_raw | grep -c '^TIMEDWAIT$')"
    LI="$(conns_raw | grep -c '^LISTEN$')"
    printf '%s,%s,%s,%s,%s\n' "$T" "${E:-0}" "${H:-0}" "${TW:-0}" "${LI:-0}"
}

csv_header() { echo "date,estab,halfopen,timewait,listen"; }

do_watch_fg()
{
    INT="${1:-5}" ; DUR="${2:-300}"
    case "$INT" in ''|*[!0-9]*) INT=5 ;; esac
    case "$DUR" in ''|*[!0-9]*) DUR=300 ;; esac
    END=$(( $(date '+%s') + DUR ))
    csv_header
    while [ "$(date '+%s')" -lt "$END" ]; do
        watch_once_csv
        alert_check
        sleep "$INT"
    done
    return 0
}

do_daemon()
{
    INT="${1:-5}"
    case "$INT" in ''|*[!0-9]*) INT=5 ;; esac
    if [ -f "$PIDFILE" ]; then
        OP="$(cat "$PIDFILE" 2>/dev/null)"
        kill -0 "$OP" 2>/dev/null && { echo "[ -- ] deja actif (PID $OP)"; return 0; }
    fi
    KEY_=""
    for d in /mnt/media_rw/*; do
        [ -f "$d/deploy.sh" ] && { KEY_="$d"; break; }
    done
    if [ -n "$KEY_" ]; then
        mkdir -p "$KEY_/log/net_watch_daemon" 2>/dev/null
        CSVF="$KEY_/log/net_watch_daemon/watch.csv"
        EVTF="$KEY_/log/net_watch_daemon/events.log"
    else
        mkdir -p /data/local/tmp/net_watch 2>/dev/null
        CSVF="/data/local/tmp/net_watch/watch.csv"
        EVTF="/data/local/tmp/net_watch/events.log"
    fi

    (
        [ -s "$CSVF" ] || csv_header > "$CSVF"
        while true; do
            watch_once_csv >> "$CSVF" 2>/dev/null
            AL="$(alert_check 2>/dev/null)"
            [ -n "$AL" ] && printf '%s\n' "$AL" >> "$EVTF" 2>/dev/null
            sleep "$INT"
        done
    ) >/dev/null 2>&1 &
    echo "$!" > "$PIDFILE"
    echo "[ OK ] daemon net_watch lance (PID $!, toutes les ${INT}s)"
    echo "       csv : $CSVF"
    echo "     event : $EVTF"
    return 0
}

do_stop()
{
    if [ -f "$PIDFILE" ]; then
        P="$(cat "$PIDFILE" 2>/dev/null)"
        kill "$P" 2>/dev/null && echo "[ OK ] daemon arrete (PID $P)" || echo "[ -- ] PID $P inexistant"
        rm -f "$PIDFILE"
    else
        echo "[ -- ] aucun daemon"
    fi
    return 0
}

valid_ip()
{
    case "$1" in
        *[!0-9.]*) return 1 ;;
    esac
    O1="${1%%.*}" ; R="${1#*.}"
    [ "$R" = "$1" ] && return 1
    O2="${R%%.*}" ; R="${R#*.}"
    O3="${R%%.*}" ; O4="${R##*.}"
    for O in "$O1" "$O2" "$O3" "$O4"; do
        case "$O" in ''|*[!0-9]*) return 1 ;; esac
        [ "$O" -le 255 ] || return 1
    done
    return 0
}

ipt()
{
    if command -v iptables > /dev/null 2>&1; then iptables "$@" ; else echo "[ERREUR] iptables absent"; return 1; fi
}

do_ban()
{
    IP="$1"
    valid_ip "$IP" || { echo "[ERREUR] ip invalide : '$IP'"; return 1; }
    is_root || require_root_banner
    if ipt -C INPUT -s "$IP" -j DROP 2>/dev/null; then
        echo "[ -- ] $IP deja bloque"
        return 0
    fi
    ipt -I INPUT -s "$IP" -j DROP && echo "[ OK ] $IP bloque (INPUT DROP)" 
}

do_unban()
{
    IP="$1"
    valid_ip "$IP" || { echo "[ERREUR] ip invalide"; return 1; }
    is_root || require_root_banner
    ipt -D INPUT -s "$IP" -j DROP 2>/dev/null && echo "[ OK ] $IP debloque" || echo "[ -- ] $IP n'etait pas bloque"
    return 0
}

require_root_banner()
{
    echo "[ERREUR] privileges root requis : su -c \"sh $0 ...\""
    exit 1
}

do_bans()
{
    echo ""
    echo "=== BLOCAGES IPTABLES (INPUT DROP) ==="
    ipt -S INPUT 2>/dev/null | grep 'DROP' | sed 's/^-A INPUT /  /' || echo "  (aucun ou iptables indisponible)"
    echo ""
    return 0
}

do_logscan()
{
    THRESH="${1:-20}"
    case "$THRESH" in ''|*[!0-9]*) THRESH=20 ;; esac
    KEY_=""
    for d in /mnt/media_rw/*; do
        [ -f "$d/deploy.sh" ] && { KEY_="$d"; break; }
    done
    echo ""
    echo "=== LOGSCAN - IP agressives (seuil $THRESH lignes) ==="
    TMPF="$(mktemp /data/local/tmp/nw_scan_XXXXXX 2>/dev/null)" || TMPF=/tmp/nw_scan_$$
    : > "$TMPF"
    if [ -n "$KEY_" ]; then
        cat "$KEY_"/log/control_server.log "$KEY_"/log/gui_server.log "$KEY_"/log/http_server.log 2>/dev/null | tail -n 1000 >> "$TMPF"
    fi
    cat /data/local/tmp/net_watch/events.log 2>/dev/null >> "$TMPF"
    NB_L="$(grep -c . "$TMPF" 2>/dev/null)"
    if [ "${NB_L:-0}" -eq 0 ]; then
        echo "  [ -- ] aucun log serveur exploitable (EXPOSE jamais lance ?)"
        rm -f "$TMPF"
        return 0
    fi
    RESULT="$(grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' "$TMPF" 2>/dev/null | grep -vE '^(127\.|0\.0\.0\.0)' | sort | uniq -c | sort -rn)"
    rm -f "$TMPF"

    HITLIST="$(printf '%s\n' "$RESULT" | while read -r N IP; do
        case "${N:-}" in ''|*[!0-9]*|"") continue ;; esac
        [ "$N" -lt "$THRESH" ] && continue
        printf '  %-11s %-5s -> net_watch BAN %s\n' "$IP" "$N" "$IP"
    done)"

    if [ -n "$HITLIST" ]; then
        echo "  IP          occurrences"
        printf '%s\n' "$HITLIST"
    else
        echo "  [ OK ] aucune IP au-dessus du seuil $THRESH"
    fi
    echo ""
    return 0
}

usage()
{
    echo ""
    echo "Usage: net_watch <STATUS|WATCH [s] [duree]|DAEMON [s]|STOP|LOGSCAN [seuil]|BAN ip|UNBAN ip|BANS>"
    echo ""
    return 0
}

case "$1" in
    ""|STATUS|status)   do_status ;;
    WATCH|watch)        shift; do_watch_fg "$@" ;;
    DAEMON|daemon)      shift; do_daemon "$@" ;;
    STOP|stop)          do_stop ;;
    LOGSCAN|logscan)    shift; do_logscan "$@" ;;
    BAN|ban)            shift; do_ban "$@" ;;
    UNBAN|unban)        shift; do_unban "$@" ;;
    BANS|bans)          do_bans ;;
    HELP|help|-h|--help) usage ;;
    *)                  usage ;;
esac
