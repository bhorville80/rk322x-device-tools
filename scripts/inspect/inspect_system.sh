#!/system/bin/sh

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" "$(dirname "$0")/.." /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

main()
{

echo ""
echo "=== INSPECTION SYSTEME ==="

echo ""
echo "[1] Memoire"
sed -n '1p;2p;3p' /proc/meminfo | sed 's/^/      /'
SWAP="$(grep SwapTotal /proc/meminfo 2>/dev/null | sed 's/^/      /')"
[ -n "$SWAP" ] && echo "$SWAP"
ZRAM="$(ls -1d /sys/block/zram* 2>/dev/null | head -n 1)"
if [ -n "$ZRAM" ]; then
    ZS="$(cat "$ZRAM/disksize" 2>/dev/null | tr -dc '0-9')"
    printf '      %-14s : %s%s\n' "zRAM" "$(basename "$ZRAM")" "${ZS:+ (disksize $((ZS / 1048576)) Mo)}"
else
    echo "      zRAM          : absent"
fi

echo ""
echo "[2] CPU"
N_CPU="$(grep -c '^processor' /proc/cpuinfo 2>/dev/null)"
printf '      %-14s : %s\n' "Coeurs" "${N_CPU:-?}"
for C in /sys/devices/system/cpu/cpu[0-9]*; do
    [ -d "$C/cpufreq" ] || continue
    ID="${C##*cpu}"
    CUR="$(cat "$C/cpufreq/scaling_cur_freq" 2>/dev/null)"
    MAX="$(cat "$C/cpufreq/scaling_max_freq" 2>/dev/null)"
    GOV="$(cat "$C/cpufreq/scaling_governor" 2>/dev/null)"
    printf '      cpu%-10s cur=%-9s max=%-9s gov=%s\n' "$ID" "$CUR" "$MAX" "$GOV"
done

echo ""
echo "[3] GPU (Mali)"
GPU_FREQ="/sys/class/misc/mali0/device/devfreq/mali/cur_freq"
GPU_GOV="/sys/class/misc/mali0/device/devfreq/mali/governor"
if [ -f "$GPU_FREQ" ]; then
    printf '      %-14s : %s Hz\n' "Frequence" "$(cat "$GPU_FREQ" 2>/dev/null)"
else
    echo "      [ -- ] devfreq mali introuvable"
fi
[ -f "$GPU_GOV" ] && printf '      %-14s : %s\n' "Governor" "$(cat "$GPU_GOV" 2>/dev/null)"

echo ""
echo "[4] Temperature"
FOUND_T=0
for Z in /sys/class/thermal/thermal_zone*; do
    [ -d "$Z" ] || continue
    T_TYPE="$(cat "$Z/type" 2>/dev/null)"
    T_TEMP="$(cat "$Z/temp" 2>/dev/null)"
    if [ -n "$T_TEMP" ]; then
        FOUND_T=1
        printf '      %-16s : %s\n' "$T_TYPE" "$T_TEMP"
    fi
done
[ "$FOUND_T" -eq 0 ] && echo "      [ -- ] aucune zone thermale lisible"

echo ""
echo "[5] Stockage"
df -h 2>/dev/null | sed -n '1p;/^\/dev/p;/ \/data\b/p;/ \/storage\b/p;/ \/system\b/p' | sed 's/^/      /'
for LT in /sys/class/mmc_host/mmc*/mmc*:0001/device/life_time /sys/class/mmc_host/mmc*/mmc*:0001/life_time; do
    [ -f "$LT" ] || continue
    V="$(tr '\n' ' ' < "$LT" 2>/dev/null | tr -s ' ')"
    [ -n "$V" ] && printf '      %-14s : %s (usure eMMC type A/B)\n' "eMMC life_time" "$V"
    break
done

echo ""
echo "[6] Affichage / HDMI"
WM_SIZE="$(wm size 2>/dev/null)"
WM_DENS="$(wm density 2>/dev/null)"
[ -n "$WM_SIZE" ] && echo "$WM_SIZE" | sed 's/^/      /'
[ -n "$WM_DENS" ] && echo "$WM_DENS" | sed 's/^/      /'
for F in /sys/class/display/HDMI /sys/class/display/display0.HDMI /sys/class/graphics/fb0/blank /sys/class/graphics/fb0/mode; do
    [ -e "$F" ] || continue
    V="$(cat "$F" 2>/dev/null | tr '\n' ' ' | cut -c1-40)"
    [ -z "$V" ] && V="(vide)"
    printf '      %-42s : %s\n' "$F" "$V"
done

echo ""
echo "[7] Charge / uptime"
printf '      %-14s : %s\n' "Loadavg" "$(cat /proc/loadavg 2>/dev/null)"
UP_S="$(cut -d. -f1 /proc/uptime 2>/dev/null)"
if [ -n "$UP_S" ]; then
    UP_H=$((UP_S / 3600))
    UP_M=$(((UP_S % 3600) / 60))
    case "$UP_M" in ?) UP_M="0$UP_M" ;; esac
    printf '      %-14s : %sh%sm\n' "Uptime" "$UP_H" "$UP_M"
fi
ENT="$(cat /proc/sys/kernel/random/entropy_avail 2>/dev/null | tr -dc '0-9')"
[ -n "$ENT" ] && printf '      %-14s : %s\n' "Entropie" "$ENT"

echo ""
echo "[8] Top RAM (applications)"
DUMP_OUT="$(dumpsys meminfo 2>/dev/null | sed -n '/Total PSS by process/,/Total PSS:/p')"
if [ -n "$DUMP_OUT" ]; then
    echo "$DUMP_OUT" | head -n 22 | sed 's/^/      /'
else
    echo "      [ -- ] dumpsys indisponible"
fi

echo ""
return 0
}

if [ "$RUNLOG_LOADED" -eq 1 ] && runlog_start "$SCRIPT_ID"; then
    main >> "$RUNLOG_FILE" 2>&1
    RC=$?
    runlog_end "$RC"
    cat "$RUNLOG_FILE"
else
    main
    RC=$?
fi

exit "$RC"

