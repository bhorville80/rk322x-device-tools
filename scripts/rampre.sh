#!/system/bin/sh
# rampre - empreinte memoire AVANT installation du toolkit (box vierge).
#
# Echantillonne /proc/meminfo pendant une duree donnee et produit un
# rapport autonome (aucune dependance au toolkit) :
#   - courbe MemAvailable / MemFree / Cached / Swap
#   - resume min/moyenne/max + pressions lowmemorykiller detectees
#   - top processus PSS au debut et a la fin (dumpsys si disponible)
#
# Usage:
#   rampre [duree_s] [intervalle_s]     defauts : 120 s / 5 s
#   rampre HELP
#
# Le rapport est ecrit dans le premier repertoire accessible parmi :
# cle USB (/mnt/media_rw/*) puis /sdcard puis /data/local/tmp.
# Lancer de preference en root (su) pour les evenements lmkd/dmesg.

SCRIPT_ID="$(basename "$0" .sh)"

DUREE="${1:-120}"
INTER="${2:-5}"

case "$DUREE" in ''|*[!0-9]*) DUREE=120 ;; esac
case "$INTER" in ''|*[!0-9]*) INTER=5 ;; esac
[ "$INTER" -lt 2 ] && INTER=2

MIN_EPOCH=1577836800

memfield()
{
    sed -n "s/^$1: *\([0-9]*\) kB/\1/p" /proc/meminfo 2>/dev/null | head -n 1
}

out_dir()
{
    for d in /mnt/media_rw/*; do
        [ -d "$d" ] && { echo "$d" ; return 0 ; }
    done
    [ -d /sdcard ] && { echo /sdcard ; return 0 ; }
    echo /data/local/tmp
    return 0
}

top_mem()
{
    # instantane des plus gros consommateurs (PSS si dumpsys, sinon RSS)
    if command -v dumpsys > /dev/null 2>&1; then
        dumpsys meminfo 2>/dev/null | sed -n '/Total PSS by OOM/,/^$/p' | head -n 18
        dumpsys meminfo 2>/dev/null | grep -E '^Total PSS' | head -n 4
    fi
    ps 2>/dev/null | head -n 1
    ps 2>/dev/null | while IFS=' ' read -r U PID PPID VSIZE RSS NAME_REST; do : ; done
    # RSS trié sans options exotiques : extraction colonne-wise portable
    ps 2>/dev/null | awk '
        NR==1 { next }
        {
            rss=$6; name=""
            for (i=9;i<=NF;i++) name=name (name?" ":"") $i
            if (rss+0>0) printf "%10d kB  %s\n", rss*4, name
        }' | sort -rn | head -n 12 | sed 's/^/  /'
}

lmk_events()
{
    N=0
    if command -v logcat > /dev/null 2>&1; then
        K="$(logcat -d -b events 2>/dev/null | grep -ciE 'lmkd|lowmemorykiller|am_kill')"
        case "$K" in ''|*[!0-9]*) K=0 ;; esac
        N="$K"
    fi
    if [ "$N" -eq 0 ] && [ -r /proc/kmsg ] || command -v dmesg > /dev/null 2>&1; then
        D="$(dmesg 2>/dev/null | grep -ciE 'lowmemory|oom_kill|kill.*background')"
        case "$D" in ''|*[!0-9]*) D=0 ;; esac
        [ "$D" -gt "$N" ] && N="$D"
    fi
    echo "$N"
}

main()
{
    TS="$(date '+%Y%m%d-%H%M%S')"
    DEST="$(out_dir)"
    OUT="$DEST/rampre_$TS.txt"

    TOTAL_0="$(memfield MemTotal)"

    {
        echo "=== RAMPRE - empreinte memoire AVANT installation ==="
        echo "genere   : $(date '+%Y-%m-%d %H:%M:%S') (epoch $(date +%s 2>/dev/null))"
        echo "duree    : ${DUREE}s (echantillons toutes les ${INTER}s)"
        echo "device   : $(getprop ro.product.device 2>/dev/null) / Android $(getprop ro.build.version.release 2>/dev/null)"
        echo "uid      : $(id -u 2>/dev/null || id)"
        echo ""
        echo "--- [debut] top memoire ---"
        top_mem
        echo ""
        echo "--- echantillons (kB) ---"
        echo "epoch;uptime_s;MemTotal;MemAvailable;MemFree;Cached;SwapTotal;SwapFree"
    } > "$OUT"

    ELAPSED=0
    while [ "$ELAPSED" -le "$DUREE" ]; do
        UP="$(cut -d. -f1 /proc/uptime 2>/dev/null | tr -dc '0-9')"
        LINE="$(date +%s 2>/dev/null);$UP;$(memfield MemTotal);$(memfield MemAvailable);$(memfield MemFree);$(memfield Cached);$(memfield SwapTotal);$(memfield SwapFree)"
        echo "$LINE" >> "$OUT"
        sleep "$INTER"
        ELAPSED=$((ELAPSED + INTER))
    done

    {
        echo ""
        echo "--- [fin] top memoire ---"
        top_mem
        echo ""
        echo "--- resume ---"
        awk -F';' '
            NR>1 && $3!="" {
                n++
                avail=$4+0
                if (!n0 || avail<minv) {minv=avail; n0=n}
                if (avail>maxv) maxv=avail
                sum+=avail
            }
            END {
                if (n>0)
                    printf "  MemAvailable : moy %d Mo | min %d Mo | max %d Mo (%d echantillons)\n", sum/n/1024, minv/1024, maxv/1024, n
            }' "$OUT"
        KILLS="$(lmk_events)"
        echo "  pressions lmk/oom detectees dans les logs : $KILLS"
        echo "  RAM totale : $((TOTAL_0 / 1024)) Mo"
        echo "=== FIN RAMPRE ==="
    } >> "$OUT"

    echo "[ OK ] rapport -> $OUT"
    echo "       renvoyer ce fichier pour comparaison avant/apres installation."
    return 0
}

case "$1" in
    HELP|help|-h|--help)
        sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
        ;;
    *)
        main
        ;;
esac
