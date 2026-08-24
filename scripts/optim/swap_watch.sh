#!/system/bin/sh
# swap_watch - gardien resident de la memoire : exploite les services deja
# en place (pattern daemon net_watch, primitives pm trim-caches et
# mem_tune OPTIMIZE) pour reagir EN RUNTIME, la ou le boot hook ne passe
# qu'une seule fois. Sans lui : pression memoire a 3h du matin ou cle
# swap morte = aucune reaction avant le prochain reboot.
#
# A chaque cycle (SWAP_WATCH_SEC) :
#   [1] swaps actifs absents      -> relance mem_tune OPTIMIZE (chaine
#                                    cle -> repli /data), evenement RESCUE
#   [2] MemAvailable < seuil      -> pm trim-caches (purge caches apps),
#                                    evenement TRIM (bornes : 1/cycle)
#   [3] activite pswpin/pswpout   -> evenement THRASH si le swap tourne
#                                    fort entre deux cycles (info)
#
# Usage:
#   swap_watch                 ou STATUS : config + daemon + derniers evenements
#   swap_watch START [sec]     lance le daemon (defaut SWAP_WATCH_SEC)
#   swap_watch STOP            arrete le daemon
#   swap_watch RUN             un cycle verbeux maintenant (diagnostic)
#   swap_watch HELP            cette aide
#
# Pilotage (device.conf) :
#   BOOT_SWAP_WATCH=1          START a chaque boot (hook init, root)
#   SWAP_WATCH_SEC=60          periode d'observation
#   SWAP_WATCH_MIN_MB=150      seuil MemAvailable declenchant TRIM
#   SWAP_WATCH_TRIM=1          action trim-caches autorisee
#   SWAP_WATCH_RESCUE=1        relance auto chaine swap autorisee

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" "$(dirname "$0")/.." /data/scripts; do
    [ -f "$B/core/runlog.sh" ] && { . "$B/core/runlog.sh"; RUNLOG_LOADED=1; break; }
done

for B in "$(dirname "$0")/core" "$(dirname "$0")/../core" /data/scripts/core; do
    [ -f "$B/config.sh" ] && { . "$B/config.sh"; break; }
done

command -v config_get >/dev/null 2>&1 || config_get() { echo "$2"; }

PIDFILE="/data/local/tmp/swap_watch.pid"
STATE="/data/local/tmp/swap_watch.state"

ok_ko() { printf '  [%s] %s\n' "$1" "$2" ; }
row()   { printf '  %-16s %s\n' "$1" "$2" ; }

memfield()
{
    sed -n "s/^$1: *\([0-9]*\) kB/\1/p" /proc/meminfo 2>/dev/null | head -n 1
}

swap_counts()   # echo "total free" (ko, 0 0 si aucun swap)
{
    awk 'NR>1 { t+=$3 ; f+=$4 ; n++ } END { printf "%d %d\n", t*1024, f*1024 }' /proc/swaps 2>/dev/null
}

pswap_pages()
{
    awk '$1=="pswpin"{i=$2}$1=="pswpout"{o=$2}END{printf "%d\n", i+o}' /proc/vmstat 2>/dev/null
}

event_log()
{
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$EVTF" 2>/dev/null
}

find_key_dir()
{
    for d in /mnt/media_rw/*; do
        [ -f "$d/deploy.sh" ] && { echo "$d" ; return 0 ; }
    done
    return 1
}

resolve_dirs()
{
    KD="$(find_key_dir)"
    if [ -n "$KD" ]; then
        DIR_="$KD/log/swap_watch"
    else
        DIR_="/data/local/tmp/swap_watch"
    fi
    mkdir -p "$DIR_" 2>/dev/null
    EVTF="$DIR_/events.log"
}

# ------------------------------------------------------------------ cycle

do_cycle()   # $1 = verbeux (1) ou silencieux (0)
{
    V_="${1:-0}"
    resolve_dirs

    MA="$(memfield MemAvailable)" ; MT="$(memfield MemTotal)"
    SC="$(swap_counts)" ; ST="${SC%% *}" ; SF="${SC##* }"
    case "$MA" in ''|*[!0-9]*) MA=0 ;; esac
    case "$MT" in ''|*[!0-9]*) MT=0 ;; esac
    case "$ST" in ''|*[!0-9]*) ST=0 ;; esac
    case "$SF" in ''|*[!0-9]*) SF=0 ;; esac
    [ "$SF" -gt "$ST" ] && SF="$ST"
    PG="$(pswap_pages)"

    # delta avec cycle precedent (thrashing)
    PP=""
    [ -r "$STATE" ] && PP="$(sed -n 's/^pages=//p' "$STATE" | head -n 1)"
    case "$PG" in ''|*[!0-9]*) PG="" ;; esac
    DELTA=""
    if [ -n "$PG" ] && [ -n "$PP" ]; then
        D=$((PG - PP))
        [ "$D" -lt 0 ] && D=0
        DELTA="$D"
    fi
    {
        echo "pages=${PG:-0}"
        echo "avail=${MA:-0}"
        date '+%H:%M:%S'
    } > "$STATE"

    ACTIONS=""

    # [1] RESCUE : plus aucun swap actif -> relancer la chaine
    if [ "${ST:-0}" -eq 0 ]; then
        if [ "$(config_get SWAP_WATCH_RESCUE 1)" = "1" ] && is_root; then
            MTUNE=""
            for C in "$(dirname "$0")/mem_tune.sh" /data/scripts/mem_tune.sh; do
                [ -f "$C" ] && { MTUNE="$C" ; break ; }
            done
            if [ -n "$MTUNE" ]; then
                sh "$MTUNE" OPTIMIZE >/dev/null 2>&1 \
                    && ACTIONS="$ACTIONS RESCUE(ok)" \
                    || ACTIONS="$ACTIONS RESCUE(ko)"
                SC2="$(swap_counts)" ; ST="${SC2%% *}" ; SF="${SC2##* }"
            fi
        else
            ACTIONS="$ACTIONS NOSWAP"
        fi
    fi

    # [2] TRIM : Memoire disponible sous le seuil
    MINMB="$(config_get SWAP_WATCH_MIN_MB 150)"
    case "$MINMB" in ''|*[!0-9]*) MINMB=150 ;; esac
    if [ -n "$MA" ] && [ "$MA" -lt $((MINMB * 1024)) ]; then
        if [ "$(config_get SWAP_WATCH_TRIM 1)" = "1" ] && command -v pm >/dev/null 2>&1 && is_root; then
            pm trim-caches 999G >/dev/null 2>&1 \
                && ACTIONS="$ACTIONS TRIM(ok)" \
                || ACTIONS="$ACTIONS TRIM(ko)"
        else
            ACTIONS="$ACTIONS LOWMEM"
        fi
    fi

    # [3] THRASH : swap tres actif depuis le cycle precedent
    case "$DELTA" in
        ''|0|*[!0-9]*) ;;
        *) if [ "$DELTA" -gt 2048 ]; then ACTIONS="$ACTIONS THRASH(${DELTA}p)" ; fi ;;
    esac

    if [ -n "$ACTIONS" ]; then
        event_log "MA=$((MA/1024))Mo sw_used=$(( (ST-SF)/1048576 ))Mo actions:$ACTIONS"
    fi
    if [ "$V_" = "1" ]; then
        row MemAvailable "$((MA / 1024)) Mo / $((MT / 1024)) Mo"
        row "swap total/libre" "$((ST / 1048576)) Mo / $((SF / 1048576)) Mo"
        row pages_pswp "${PG:-?} (delta cycle: ${DELTA:-premier})"
        row decisions "${ACTIONS:-(rien a faire)}"
    fi
    return 0
}

# ------------------------------------------------------------------ commandes

daemon_alive()
{
    [ -f "$PIDFILE" ] || return 1
    DP="$(cat "$PIDFILE" 2>/dev/null)"
    kill -0 "$DP" 2>/dev/null
}

cmd_status()
{
    echo ""
    echo "=== SWAP WATCH ==="
    if daemon_alive; then
        ok_ko OK "daemon actif (PID $(cat "$PIDFILE"))"
    else
        ok_ko -- "daemon inactif (START pour lancer ; BOOT_SWAP_WATCH=1 au boot)"
    fi
    row periode "$(config_get SWAP_WATCH_SEC 60)s"
    row seuil_trim "$(config_get SWAP_WATCH_MIN_MB 150) Mo dispo"
    row actions "trim=$(config_get SWAP_WATCH_TRIM 1) rescue=$(config_get SWAP_WATCH_RESCUE 1)"
    resolve_dirs
    if [ -r "$STATE" ]; then
        row dernier_cycle "$(tail -n 1 "$STATE" 2>/dev/null)"
    fi
    if [ -f "$EVTF" ]; then
        echo ""
        echo "  derniers evenements :"
        tail -n 5 "$EVTF" 2>/dev/null | sed 's/^/    /'
    else
        echo ""
        echo "  aucun evenement (aucun probleme detecte, ou jamais lance)"
    fi
    echo ""
    return 0
}

cmd_start()
{
    S="${1:-$(config_get SWAP_WATCH_SEC 60)}"
    case "$S" in ''|*[!0-9]*) S=60 ;; esac
    if daemon_alive; then
        echo "[ -- ] deja actif (PID $(cat "$PIDFILE"))"
        return 0
    fi
    if ! is_root; then
        echo "[ERREUR] privileges root requis (actions trim/rescue) : su -c \"sh $0 START\""
        return 1
    fi
    resolve_dirs
    (
        while true; do
            do_cycle 0
            sleep "$S"
        done
    ) >/dev/null 2>&1 &
    echo "$!" > "$PIDFILE"
    echo "[ OK ] gardien swap lance (PID $!, toutes les ${S}s)"
    echo "       evenements : $EVTF"
    return 0
}

cmd_stop()
{
    if daemon_alive; then
        P="$(cat "$PIDFILE")"
        kill "$P" 2>/dev/null && echo "[ OK ] arrete (PID $P)" || echo "[ -- ] PID $P inexistant"
        rm -f "$PIDFILE"
    else
        echo "[ -- ] aucun daemon actif"
    fi
    return 0
}

usage()
{
    sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
}

main()
{
    case "$1" in
        ""|STATUS|status) cmd_status ;;
        START|start)      shift ; cmd_start "$@" ;;
        STOP|stop)        cmd_stop ;;
        RUN|run)          shift ; do_cycle 1 ;;
        HELP|-h|--help)   usage ;;
        *)                echo "option inconnue : $1 (voir swap_watch HELP)" ; return 1 ;;
    esac
}

if [ "$RUNLOG_LOADED" -eq 1 ] && runlog_start "$SCRIPT_ID"; then
    main "$@" >> "$RUNLOG_FILE" 2>&1 ; RC=$?
    runlog_end "$RC" ; cat "$RUNLOG_FILE"
else
    main "$@" ; RC=$?
fi
exit "$RC"
