#!/system/bin/sh
# ramstep - deploiement instrumente : une mesure RAM avant/apres chaque etape.
#
# Permet d'isoler le benefice de chaque optimisation, puis l'effet du
# demarrage de la pile web. Entre chaque etape : pause d'observation.
#
# Usage:
#   ramstep              sequence complete standard (pause 30 s par defaut)
#   ramstep <secondes>   sequence complete avec une autre pause
#   ramstep ONE "<label>" <commande...>   encapsule une commande seule
#   ramstep HELP
#
# Chronologie ecrite dans log/ram_steps_<TS>.txt (cle USB si presente).

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

PAUSE="${1:-30}"
case "$PAUSE" in ''|*[!0-9]*) PAUSE=30 ;; esac

KEY=""
for d in /mnt/media_rw/*; do
    [ -f "$d/deploy.sh" ] && { KEY="$d"; break; }
done

OUT=""
init_out()
{
    TS="$(date '+%Y%m%d-%H%M%S')"
    DEST="${KEY:-/data/local/tmp}/log"
    mkdir -p "$DEST" 2>/dev/null
    OUT="$DEST/ram_steps_$TS.txt"
}

# --- mesure ---------------------------------------------------------------

memfield() { sed -n "s/^$1: *\([0-9]*\) kB/\1/p" /proc/meminfo 2>/dev/null | head -n 1; }

snap()
{
    AV="$(memfield MemAvailable)"
    FR="$(memfield MemFree)"
    CA="$(memfield Cached)"
    ST="$(memfield SwapTotal)"
    SF="$(memfield SwapFree)"
    UP="$(cut -d. -f1 /proc/uptime 2>/dev/null | tr -dc '0-9')"

    SNAP_AV="${AV:-0}"
    echo ""
    echo ">>> MESURE $(date '+%H:%M:%S')"
    echo "    MemAvailable : $((AV / 1024)) Mo   (free $((FR / 1024)) Mo, cached $((CA / 1024)) Mo)"
    if [ "${ST:-0}" -gt 0 ] 2>/dev/null; then
        echo "    Swap         : $(((ST - SF) / 1024))/$((ST / 1024)) Mo"
    fi
    ps 2>/dev/null | awk 'NR>1 {rss=$6; n=""; for(i=9;i<=NF;i++) n=n (n?" ":"")$i; if(rss+0>0) printf "%10d %s\n", rss*4, n}' \
        | sort -rn | head -n 5 | sed 's/^/    top /'
    {
        echo "[$(date '+%H:%M:%S')] avail=$((AV/1024))Mo free=$((FR/1024))Mo cached=$((CA/1024))Mo swap_used=$(((ST-SF)/1024))Mo uptime=${UP}s"
    } >> "$OUT"
}

delta()
{
    D=$(( (AV_PREV - SNAP_AV) / 1024 ))
    if [ "$D" -gt 0 ]; then
        echo "    GAIN vs etape precedente : +$D Mo disponibles"
    elif [ "$D" -lt 0 ]; then
        echo "    COUT vs etape precedente : $((-D)) Mo disponibles"
    else
        echo "    stable vs etape precedente"
    fi
    echo "[$(date '+%H:%M:%S')] delta_prev=$D Mo label=$LAST_LABEL" >> "$OUT"
    AV_PREV="$SNAP_AV"
}

observe()
{
    echo ""
    echo "--- observation ${PAUSE}s (laisser le systeme se stabiliser)... ---"
    i=0
    while [ "$i" -lt "$PAUSE" ]; do
        sleep 1
        i=$((i+1))
        [ $((i % 10)) -eq 0 ] && echo "    ...${i}s"
    done
}

run_step()
{
    LAST_LABEL="$1"
    shift
    echo ""
    echo "==============================================="
    echo "  ETAPE : $LAST_LABEL"
    echo "==============================================="
    OUT_="$(sh "$@" 2>&1)"
    RC=$?
    printf '%s\n' "$OUT_" | tail -n 6 | sed 's/^/    | /'
    echo "    (rc=$RC)"
    observe
    snap
    delta
    return "$RC"
}

help_show()
{
    sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
}

# ---------------------------------------------------------------- sequence

if [ "$1" = "HELP" ] || [ "$1" = "-h" ]; then help_show ; exit 0 ; fi

if [ "$1" = "ONE" ]; then
    LBL="$2"; shift 2
    init_out
    snap > /dev/null; AV_PREV="$SNAP_AV"
    echo "=== RAMSTEP unitaire : $LBL ===" | tee -a "$OUT"
    run_step "$LBL" "$@"
    exit $?
fi

init_out

echo ""
echo "=== RAMSTEP - deploiement instrumente ==="
echo "pause d'observation entre etapes : ${PAUSE}s"
echo "chronologie : $OUT"

snap > /dev/null
AV_PREV="$SNAP_AV"
echo "" >> "$OUT"; echo "== DEPART ($(date '+%H:%M:%S')) ==" >> "$OUT"
snap

run_step "mem_tune OPTIMIZE"      "$BASE/mem_tune.sh" OPTIMIZE
run_step "thermal ECO"            "$BASE/thermal.sh" ECO
run_step "cut_services CUT"       "$BASE/cut_services.sh" CUT
run_step "reseau + horloge"       sh -c 'sh "'"$BASE"'/set_network.sh" >/dev/null 2>&1; sh "'"$BASE"'/set_time.sh" AUTO' 
run_step "PILE WEB (STOP+EXPOSE)" sh -c 'sh "'"$BASE"'/deploy.sh" STOP >/dev/null 2>&1; sh "'"$BASE"'/deploy.sh" EXPOSE'

echo ""
echo "=== RESUME RAMSTEP ==="
echo "  detail complet : $OUT"
echo "  chaque ligne delta_prev indique le benefice isolé de l'etape."
echo ""

exit 0
