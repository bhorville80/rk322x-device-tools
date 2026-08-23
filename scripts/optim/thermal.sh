#!/system/bin/sh
# thermal - temperatures et profils CPU (eco / perf) pour fonctionnement 24/7
#
# Usage: thermal.sh [STATUS|ECO|PERF|help]
#
#   STATUS   lecture seule : governor, frequences, temperatures
#   ECO      governor powersave/conservative + bridage de la frequence max
#            (chauffe moins, silencieux, suffisant pour serveur de fichiers)
#   PERF     governor performance + frequence max native
#
# NOTE : sans persistance au boot, le profil retombe sur le defaut apres reboot.

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" "$(dirname "$0")/.." /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

for B in "$(dirname "$0")" "$(dirname "$0")/core" "$(dirname "$0")/../core" /data/scripts /data/scripts/core; do
    if [ -f "$B/config.sh" ]; then
        . "$B/core/config.sh"
        break
    fi
done

CPU_BASE="/sys/devices/system/cpu"

usage()
{
    echo ""
    echo "Usage: thermal.sh <STATUS|ECO|PERF>"
    echo ""
    echo "  STATUS  temperatures + governor/frequences (lecture seule)"
    echo "  ECO     bride la frequence max (24/7, chauffe reduite)"
    echo "  PERF    frequence max native + governor performance"
    echo ""
}

cpu_list()
{
    ls -1d "$CPU_BASE"/cpu[0-9]* 2>/dev/null | sort
}

read_avail_freqs()
{
    cat "$1/cpufreq/scaling_available_frequencies" 2>/dev/null | tr ' ' '\n' | sed '/^$/d' | sort -n
}

show_temp()
{
    for Z in /sys/class/thermal/thermal_zone*; do
        [ -d "$Z" ] || continue
        T="$(cat "$Z/temp" 2>/dev/null | tr -dc '0-9')"
        N="$(cat "$Z/type" 2>/dev/null)"
        case "$T" in ''|*[!0-9]*) continue ;; esac
        C=$((T / 1000))
        FLAG=""
        [ "$C" -ge 75 ] && FLAG="  <-- ELEVEE"
        printf '      %-22s %3s C%s\n' "${N:-zone}" "$C" "$FLAG"
    done
}

do_status()
{
    echo ""
    echo "=== THERMAL STATUS ==="
    echo ""
    echo "--- Temperatures ---"
    TZ="$(show_temp)"
    if [ -n "$TZ" ]; then
        echo "$TZ"
    else
        echo "      aucune zone thermique lisible"
    fi

    echo ""
    echo "--- CPU ---"
    SHOWN=0
    for C in $(cpu_list); do
        D="$C/cpufreq"
        [ -d "$D" ] || continue
        [ "$SHOWN" -eq 1 ] && continue
        SHOWN=1
        GOV="$(cat "$D/scaling_governor" 2>/dev/null)"
        CUR="$(cat "$D/scaling_cur_freq" 2>/dev/null)"
        MIN="$(cat "$D/scaling_min_freq" 2>/dev/null)"
        MAX="$(cat "$D/scaling_max_freq" 2>/dev/null)"
        AVAIL_GOV="$(cat "$D/scaling_available_governors" 2>/dev/null)"
        printf '      %-12s %s\n' "governor" "$GOV${AVAIL_GOV:+  (dispo: $AVAIL_GOV)}"
        [ -n "$CUR" ] && printf '      %-12s %s MHz\n' "frequence" "$((CUR / 1000))"
        [ -n "$MIN" ] && [ -n "$MAX" ] && \
            printf '      %-12s %s - %s MHz\n' "plage" "$((MIN / 1000))" "$((MAX / 1000))"
        FREQS="$(read_avail_freqs "$D")"
        [ -n "$FREQS" ] && printf '      %-12s %s MHz\n' "paliers" \
            "$(printf '%s\n' "$FREQS" | while read -r F; do
                case "$F" in ''|*[!0-9]*) continue ;; esac
                printf '%s ' "$((F / 1000))"
              done)"
    done
    [ "$SHOWN" -eq 0 ] && echo "      cpufreq non expose par ce noyau"
    echo ""
    return 0
}

apply_profile()
{
    MODE="$1"

    if ! require_root; then
        return 1
    fi

    echo ""
    echo "=== THERMAL $MODE ==="

    DONE=0
    for C in $(cpu_list); do
        D="$C/cpufreq"
        [ -d "$D" ] || continue

        FREQS="$(read_avail_freqs "$D")"
        GOVS="$(cat "$D/scaling_available_governors" 2>/dev/null)"

        case "$MODE" in
            PERF)
                NEW_MAX="$(printf '%s\n' "$FREQS" | tail -n 1)"
                NEW_GOV="performance"
                ;;
            ECO)
                # 2e palier le plus bas (garde un peu de marge)
                NEW_MAX="$(printf '%s\n' "$FREQS" | sed -n '2p')"
                NEW_GOV="powersave"
                case "$GOVS" in *powersave*) ;; *) NEW_GOV="conservative" ;; esac
                case "$GOVS" in *"$NEW_GOV"*) ;; *) NEW_GOV="" ;; esac
                ;;
        esac

        [ -z "$NEW_MAX" ] && NEW_MAX="$(cat "$D/scaling_max_freq" 2>/dev/null)"

        if [ -n "$NEW_GOV" ]; then
            echo "$NEW_GOV" > "$D/scaling_governor" 2>/dev/null && DONE=1
        fi
        if [ -n "$NEW_MAX" ]; then
            echo "$NEW_MAX" > "$D/scaling_max_freq" 2>/dev/null && DONE=1
        fi
    done

    [ "$DONE" -eq 0 ] && { echo "[ERREUR] aucun reglage applique (droits ou sysfs absent)"; return 1; }

    echo "[ OK ] profil $MODE applique"
    do_status
    return 0
}

case "$1" in
    ""|STATUS|status) do_status ;;
    ECO|eco)          apply_profile ECO ;;
    PERF|perf)        apply_profile PERF ;;
    HELP|help|-h|--help) usage ;;
    *)                usage; exit 1 ;;
esac

exit "$?"
