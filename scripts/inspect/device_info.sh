#!/system/bin/sh
# device_info - inventaire dynamique des puces et du materiel,
# trie par fonctionnalite (SOC/CPU, RAM, GPU, stockage, reseau,
# wireless, USB, audio, affichage, entrees/IR, alim/RTC, thermique),
# avec services init rattaches a chaque fonction.
# Lecture seule : sysfs / procfs / getprop / dmesg.

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" "$(dirname "$0")/.." /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

sec()  { echo ""; echo "--- [$1] $2 ---"; }
row()  { printf '  %-20s %s\n' "$1" "$2"; }
none() { echo "  [ -- ] $1"; }

is_num()
{
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *)           return 0 ;;
    esac
}

main()
{

echo ""
echo "=== DEVICE INFO - $(getprop ro.product.model 2>/dev/null) ($(getprop ro.product.device 2>/dev/null)) ==="
echo "Android $(getprop ro.build.version.release 2>/dev/null) (SDK $(getprop ro.build.version.sdk 2>/dev/null)), patch securite : $(getprop ro.build.version.security_patch 2>/dev/null)"
echo "fingerprint : $(getprop ro.build.fingerprint 2>/dev/null)"

CHIPS=""

# ---------------------------------------------------------------- SOC / CPU
sec 1 "SOC / CPU"
row platform "$(getprop ro.board.platform 2>/dev/null) ($(getprop ro.hardware 2>/dev/null))"
HW="$(sed -n 's/^Hardware[ \t]*:[ \t]*//p' /proc/cpuinfo 2>/dev/null | head -n 1)"
CORES="$(grep -c '^processor' /proc/cpuinfo 2>/dev/null)"
is_num "$CORES" && row soc "${HW:-inconnu}, ${CORES} coeur(s)"
F="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null)"
G="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)"
if is_num "$F"; then
    row cpu0 "$((F / 1000)) MHz${G:+ ($G)}"
fi
CHIP_ID="$(dmesg 2>/dev/null | grep -ioE 'rk32[0-9]{2}' | head -n 1)"
[ -n "$CHIP_ID" ] && CHIPS="$CHIPS SOC:$CHIP_ID"

# ---------------------------------------------------------------- RAM / DDR
sec 2 "RAM / DDR"
MT="$(sed -n 's/^MemTotal: *\([0-9]*\) kB/\1/p' /proc/meminfo 2>/dev/null | head -n 1)"
MF="$(sed -n 's/^MemFree: *\([0-9]*\) kB/\1/p' /proc/meminfo 2>/dev/null | head -n 1)"
if is_num "$MT"; then
    row total "$((MT / 1024)) Mo (libre : $(is_num "$MF" && echo $((MF / 1024))) Mo)"
fi
DMC="/sys/class/devfreq/dmc/cur_freq"
if [ -f "$DMC" ]; then
    DF="$(cat "$DMC" 2>/dev/null)"
    is_num "$DF" && row "ddr freq" "$((DF / 1000000)) MHz"
fi
if [ -e /dev/zram0 ]; then
    ZS="$(cat /sys/block/zram0/disksize 2>/dev/null)"
    row zram "present${ZS:+ ($((ZS / 1048576)) Mo compresses)}"
else
    row zram "absent"
fi

# ---------------------------------------------------------------- GPU
sec 3 "GPU"
if [ -e /dev/mali ]; then
    row gpu "Mali (/dev/mali)"
    CHIPS="$CHIPS GPU:Mali-400"
elif [ -e /proc/galcore ]; then
    row gpu "Vivante (/proc/galcore)"
else
    none "GPU dedie non detecte"
fi
OGLES="$(getprop ro.opengles.version 2>/dev/null)"
case "$OGLES" in
    ''|*[!0-9]*) ;;
    *) row opengles "v$((OGLES >> 16)).$((OGLES & 0xFFFF))" ;;
esac

# ---------------------------------------------------------------- STOCKAGE
sec 4 "STOCKAGE (eMMC / flash)"
for BK in /sys/block/mmcblk*; do
    [ -d "$BK" ] || continue
    N="$(basename "$BK")"
    case "$N" in *boot*|*rpmb*) continue ;; esac
    NM="$(cat "$BK/device/name" 2>/dev/null)"
    SZ="$(cat "$BK/size" 2>/dev/null)"
    CID="$(cat "$BK/device/cid" 2>/dev/null)"
    DESC="${NM:-?}"
    is_num "$SZ" && DESC="$DESC, $((SZ / 2048)) Mo"
    [ -n "$CID" ] && DESC="$DESC (cid $CID)"
    row "$N" "$DESC"
    [ -n "$NM" ] && CHIPS="$CHIPS eMMC:$NM"
done
[ -s /proc/mtd ] && { echo "  mtd :"; sed -n '2,$p' /proc/mtd 2>/dev/null | sed 's/^/    /'; }
grep -E 'mmcblk[0-9]p[0-9]+' /proc/partitions 2>/dev/null \
    | awk '{printf "  %-14s %5d Mo\n", $4, $3 / 1024}'

# ---------------------------------------------------------------- RESEAU
sec 5 "RESEAU FILAIRE"
if [ -d /sys/class/net/eth0 ]; then
    DRV="$(basename "$(readlink /sys/class/net/eth0/device/driver 2>/dev/null)" 2>/dev/null)"
    SP="$(cat /sys/class/net/eth0/speed 2>/dev/null)"
    IP_="$(ifconfig eth0 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p')"
    row eth0 "driver ${DRV:-?}${SP:+, ${SP} Mb/s}${IP:+, ip $IP_}"
    [ -n "$DRV" ] && CHIPS="$CHIPS ETH:$DRV"
else
    none "pas d'interface eth0"
fi

# ---------------------------------------------------------------- WIRELESS
sec 6 "WIRELESS (WiFi / BT)"
FOUND_W=0
for D in /sys/bus/sdio/devices/*; do
    [ -d "$D" ] || continue
    DRV="$(basename "$(readlink "$D/driver" 2>/dev/null)" 2>/dev/null)"
    MA="$(cat "$D/modalias" 2>/dev/null)"
    row "$(basename "$D")" "sdio ${DRV:-non-lie}${MA:+ [$MA]}"
    if [ -n "$DRV" ]; then
        CHIPS="$CHIPS SDIO:$DRV"
        FOUND_W=1
    fi
done
[ "$FOUND_W" -eq 0 ] && none "aucun peripherique sdio"
for R in /sys/class/rfkill/*; do
    [ -d "$R" ] || continue
    row "$(cat "$R/name" 2>/dev/null)" "type $(cat "$R/type" 2>/dev/null), etat $(cat "$R/state" 2>/dev/null)"
done

# ---------------------------------------------------------------- USB
sec 7 "USB"
FOUND_U=0
for D in /sys/bus/usb/devices/*; do
    [ -f "$D/product" ] || continue
    PR="$(cat "$D/product" 2>/dev/null)"
    MF_="$(cat "$D/manufacturer" 2>/dev/null)"
    if [ -n "$PR" ]; then
        row "$(basename "$D")" "${MF_:+$MF_ }$PR"
        FOUND_U=1
    fi
done
[ "$FOUND_U" -eq 0 ] && none "rien sur les bus usb"

# ---------------------------------------------------------------- AUDIO
sec 8 "AUDIO"
if [ -s /proc/asound/cards ]; then
    sed -n '2,$p' /proc/asound/cards | sed 's/^/  /'
    CS="$(sed -n '2p' /proc/asound/cards | awk '{print $2}')"
    [ -n "$CS" ] && CHIPS="$CHIPS AUDIO:$CS"
else
    none "/proc/asound absent"
fi

# ---------------------------------------------------------------- AFFICHAGE
sec 9 "AFFICHAGE / HDMI"
FBV="$(cat /sys/class/graphics/fb0/virtual_size 2>/dev/null)"
BLANK="$(cat /sys/class/graphics/fb0/blank 2>/dev/null)"
row fb0 "${FBV:-resolution inconnue}${BLANK:+, blank=$BLANK}"
HDM="/sys/class/display/HDMI"
if [ -d "$HDM" ]; then
    row hdmi "enable=$(cat "$HDM/enable" 2>/dev/null), mode=$(cat "$HDM/mode" 2>/dev/null)"
fi

# ---------------------------------------------------------------- ENTREES / IR
sec 10 "ENTREES (claviers / telecommande IR)"
grep '^N: ' /proc/bus/input/devices 2>/dev/null \
    | sed 's/^N: Name="//;s/"$//;s/^/  - /'
[ -d /sys/class/rc ] && ls -1 /sys/class/rc 2>/dev/null | sed 's/^/  rc: /'
IR_DM="$(dmesg 2>/dev/null | grep -iE 'remotectl|gpio-ir|rc_core|ir-receiver' | tail -n 3)"
[ -n "$IR_DM" ] && { echo "  dmesg :"; echo "$IR_DM" | sed 's/^/    /'; }

# ---------------------------------------------------------------- ALIM / RTC
sec 11 "ALIM / RTC"
RT="/sys/class/rtc/rtc0"
if [ -d "$RT" ]; then
    RTN="$(cat "$RT/name" 2>/dev/null)"
    row rtc "$RTN ($(cat "$RT/date" 2>/dev/null) $(cat "$RT/time" 2>/dev/null))"
    [ -n "$RTN" ] && CHIPS="$CHIPS RTC:$RTN"
else
    none "pas de rtc expose"
fi
{
    for RG in /sys/class/regulator/regulator.[0-9]*; do
        [ -d "$RG" ] || continue
        MV="$(cat "$RG/microvolts" 2>/dev/null)"
        V=""
        is_num "$MV" && V=", $((MV / 1000000)).$(((MV / 100000) % 10)) V"
        row "$(cat "$RG/name" 2>/dev/null)" "$(cat "$RG/state" 2>/dev/null)$V"
    done
} | sed -n '1,14p'
ls -1 /sys/class/power_supply 2>/dev/null | sed 's/^/  power_supply: /'

# ---------------------------------------------------------------- THERMIQUE
sec 12 "THERMIQUE"
FOUND_T=0
for TZ in /sys/class/thermal/thermal_zone*; do
    [ -d "$TZ" ] || continue
    TT="$(cat "$TZ/temp" 2>/dev/null)"
    if is_num "$TT"; then
        row "$(cat "$TZ/type" 2>/dev/null)" "$((TT / 1000)).$(((TT / 100) % 10)) C"
        FOUND_T=1
    fi
done
[ "$FOUND_T" -eq 0 ] && none "aucune zone thermique exposee"

# ---------------------------------------------------------------- SERVICES PAR FONCTION
sec 13 "SERVICES PAR FONCTIONNALITE"
SVCS="$(getprop 2>/dev/null \
    | sed -n 's/^\[init\.svc\.\([^]]*\)\]: *\[\([^]]*\)\]/\1|\2/p')"

show_group()
{
    OUT="$(printf '%s\n' "$SVCS" | grep -E "(^|\|)(${1})" | sed 's/|/ : /;s/^/  /')"
    if [ -n "$OUT" ]; then
        echo "  $2 :"
        echo "$OUT"
    fi
}
show_group 'surfaceflinger|bootanim'            "AFFICHAGE"
show_group 'audioserver'                        "AUDIO"
show_group 'media|drm'                          "MEDIA / DRM"
show_group 'netd|dhcpcd|mdnsd|mtpd|racoon|ppp'  "RESEAU"
show_group 'wpa|hostapd|bluetooth'              "WIRELESS"
show_group 'vold|installd|uncrypt'              "STOCKAGE"
show_group 'adbd|servicemanager|console|debuggerd|lmkd' "SYSTEME / DEBUG"
show_group 'camera'                             "CAMERA"

OTH="$(printf '%s\n' "$SVCS" \
    | grep -vE '(^|\|)(surfaceflinger|bootanim|audioserver|media|drm|netd|dhcpcd|mdnsd|mtpd|racoon|ppp|wpa|hostapd|bluetooth|vold|installd|uncrypt|adbd|servicemanager|console|debuggerd|lmkd|camera)' \
    | sed 's/|/ : /;s/^/  /')"
if [ -n "$OTH" ]; then
    echo "  AUTRES :"
    echo "$OTH"
fi

# ---------------------------------------------------------------- SYNTHESE
sec 14 "SYNTHESE PUCES DETECTEES"
if [ -n "$CHIPS" ]; then
    printf '%s\n' "$CHIPS" | tr ' ' '\n' | grep -v '^$' | sort -u | sed 's/^/  - /'
else
    none "aucune puce identifiee (voir sections ci-dessus)"
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
exit 0
