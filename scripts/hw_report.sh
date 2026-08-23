#!/system/bin/sh
# hw_report - rapport materiel complet pour recherche des puces sur le net.
#
# Compose tout ce qui permet d'identifier chaque composant et ses
# possibilites (datasheets, ROM alternatives, drivers) :
#   [1] inventaire complet   : device_info (puces par fonctionnalite)
#   [2] proprietes systeme   : getprop filtre (produit/build/wifi/bt/eth)
#   [3] noyau                : version, modules charges, extraits dmesg
#   [4] bus                  : i2c/spi detectes, peripheriques input
#
# Usage:
#   hw_report               rapport sur stdout (rediriger vers un fichier)
#   hw_report SAVE          ecrit log/hardware_<TS>.txt + hardware_latest.txt
#                           sur la cle (servi en HTTP par le panneau :8000)
#   hw_report HELP          cette aide
#
# Lecture seule ; root conseille (dmesg/partitions sinon tronques).

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

for B in "$(dirname "$0")" "$(dirname "$0")/../scripts" /data/scripts; do
    if [ -f "$B/core/config.sh" ]; then
        . "$B/core/config.sh"
        break
    fi
done
command -v config_get >/dev/null 2>&1 || config_get() { echo "$2"; }

BASE="$(cd "$(dirname "$0")" && pwd)"

KEY=""
for d in /mnt/media_rw/*; do
    [ -f "$d/deploy.sh" ] && { KEY="$d"; break; }
done

sec()
{
    echo ""
    echo "============================================================"
    echo "  $1"
    echo "============================================================"
}

report()
{
    echo "=== RAPPORT MATERIEL COMPLET ==="
    echo "genere  : $(date '+%Y-%m-%d %H:%M:%S')"
    echo "box     : $(getprop ro.product.device 2>/dev/null) / Android $(getprop ro.build.version.release 2>/dev/null)"
    echo "ip      : $(config_get IP '?')"
    echo ""
    echo "note    : les references de puces ci-dessous se pretent a une"
    echo "          recherche web (datasheet, possibilites ROM/drivers) ;"
    echo "          la synthese est en fin de section [1]."

    sec "[1] INVENTAIRE COMPLET (device_info)"
    if [ -f "$BASE/device_info.sh" ]; then
        sh "$BASE/device_info.sh" 2>/dev/null
    elif [ -f /data/scripts/device_info.sh ]; then
        sh /data/scripts/device_info.sh 2>/dev/null
    else
        echo "(device_info introuvable)"
    fi

    sec "[2] PROPRIETES SYSTEME (getprop filtre)"
    getprop 2>/dev/null | grep -iE \
        'ro\.product|ro\.build\.(version|display|date|fingerprint)|ro\.hardware|ro\.board|\
ro\.soc|persist\.(wireless|bt)|net\.(dns|eth)|wlan|bluetooth|bluetooth\.hci|\
brcm|rtl|r8188|r8192|realtek|rockchip|rk30|rk32|ethernet|dhcp' \
        | sed 's/^/  /'

    sec "[3] NOYAU"
    echo "-- version"
    cat /proc/version 2>/dev/null | sed 's/^/  /'
    echo "-- modules charges (/proc/modules)"
    if [ -s /proc/modules ]; then
        head -60 /proc/modules 2>/dev/null | awk '{printf "  %-24s %s %s\n", $1, $2, $3}'
    else
        echo "  (aucun module charge ou lecture impossible)"
    fi
    echo "-- extraits dmesg materiels (filtre, 80 lignes max)"
    if command -v dmesg > /dev/null 2>&1; then
        dmesg 2>/dev/null | grep -iE 'chip|phy|sensor|codec|rtc|i2c|spi|uart|\
mmc|emmc|sdio|wifi|wlan|brcm|rtl|eth|gmac|hdmi|audio|vpu|gpu|mali|remote|pwm' \
            | tail -n 80 | sed 's/^/  /'
    else
        echo "  (dmesg indisponible)"
    fi

    sec "[4] BUS ET PERIPHERIQUES"
    echo "-- i2c detectes"
    for D in /dev/i2c-*; do
        [ -e "$D" ] && echo "  $D"
    done 2>/dev/null
    echo "-- spi"
    for D in /dev/spidev*; do
        [ -e "$D" ] && echo "  $D"
    done 2>/dev/null
    echo "-- input (claviers/telecommandes)"
    if [ -d /sys/class/input ]; then
        for IN in /sys/class/input/input*; do
            [ -f "$IN/name" ] && printf '  %-14s %s\n' \
                "$(basename "$IN")" "$(cat "$IN/name" 2>/dev/null)"
        done
    fi
    echo "-- partitions blocs (reperage eMMC/SD)"
    for B_ in /sys/block/mmcblk*; do
        [ -d "$B_" ] && printf '  %-12s taille %s secteurs\n' \
            "$(basename "$B_")" "$(cat "$B_/size" 2>/dev/null)"
    done 2>/dev/null
}

save_report()
{
    DEST_DIR="${KEY:-/data/local/tmp}/log"
    mkdir -p "$DEST_DIR" 2>/dev/null || return 1
    TS="$(date '+%Y%m%d-%H%M%S')"
    FULL="$DEST_DIR/hardware_$TS.txt"
    LAST="$DEST_DIR/hardware_latest.txt"

    report > "$FULL" 2>&1 || return 1
    cp -f "$FULL" "$LAST" 2>/dev/null

    echo "[ OK ] rapport -> ${KEY:+(cle) }log/hardware_$TS.txt"
    echo "       telechargeable via le panneau : http://<ip-box>:8000/log/hardware_latest.txt"
}

case "$1" in
    HELP|-h|--help)
        echo ""
        echo "Usage: hw_report [SAVE|HELP]"
        echo ""
        echo "  hw_report         rapport complet sur stdout"
        echo "  hw_report SAVE    ecrit log/hardware_<TS>.txt + _latest.txt sur la cle"
        echo "                    (telechargeable : http://<ip>:8000/log/hardware_latest.txt)"
        echo ""
        return 0
        ;;
    SAVE|save)
        if [ "$RUNLOG_LOADED" -eq 1 ] && runlog_start "$SCRIPT_ID"; then
            save_report >> "$RUNLOG_FILE" 2>&1
            RC=$?
            runlog_end "$RC"
            cat "$RUNLOG_FILE"
        else
            save_report
            RC=$?
        fi
        exit "$RC"
        ;;
esac

if [ "$RUNLOG_LOADED" -eq 1 ] && runlog_start "$SCRIPT_ID"; then
    report >> "$RUNLOG_FILE" 2>&1
    RC=$?
    runlog_end "$RC"
    cat "$RUNLOG_FILE"
else
    report
    RC=$?
fi
exit "$RC"
