#!/system/bin/sh
# disable_wireless - coupe/remet Wi-Fi + Bluetooth, avec verification.
#
#   disable_wireless            OFF (defaut) : coupure + verif (2 essais)
#   disable_wireless STATUS     etat complet des radios/interfaces
#   disable_wireless ON         remise en route (reboot conseille apres)
#
# Persistance : wifi_on/bluetooth_on forces a 0 -> restent coupes au reboot.
# Option : WIRELESS_AIRPLANE=1 dans device.conf -> active aussi le mode avion.

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" "$(dirname "$0")/.." /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

for B in "$(dirname "$0")" "$(dirname "$0")/core" "$(dirname "$0")/../scripts/core" /data/scripts /data/scripts/core; do
    if [ -f "$B/config.sh" ]; then
        . "$B/core/config.sh"
        break
    fi
done

# garde-fou si config.sh introuvable
command -v require_root > /dev/null 2>&1 || require_root() { case "$(id -u 2>/dev/null)" in 0) return 0 ;; esac; case "$(id 2>/dev/null)" in "uid=0("*) return 0 ;; esac; return 1; }
command -v config_get   > /dev/null 2>&1 || config_get() { echo "$2"; }

WIFI_IFS="wlan0 p2p0"

prop_get()
{
    getprop "$1" 2>/dev/null | tr -d '\r'
}

iface_down()
{
    # $1 interface -> 0 si absente ou DOWN
    ST="$(ip link show "$1" 2>/dev/null | tr -d '\r')"
    case "$ST" in
        "") return 0 ;;
        *"state UP"*|*"state UNKNOWN"*) return 1 ;;
        *) return 0 ;;
    esac
}

kill_radio_services()
{
    # arrete les services init dont le nom evoque une radio
    getprop 2>/dev/null | tr -d '\r' \
        | sed -n 's/^\[init\.svc\.\([^]]*\)\]: \[running\]/\1/p' \
        | grep -iE 'wifi|wlan|wpa|softap|bluetooth|^bt|hci' \
        | while read -r S; do
            stop "$S" > /dev/null 2>&1 && echo "    [ OK ] service $S arrete"
        done
    return 0
}

rfkill_all()
{
    MODE="$1"
    if command -v rfkill > /dev/null 2>&1; then
        rfkill "$MODE" all > /dev/null 2>&1 && return 0
    fi
    if busybox 2>&1 | grep -qw rfkill; then
        busybox rfkill "$MODE" all > /dev/null 2>&1 && return 0
    fi
    return 1
}

set_airplane()
{
    V="$1"
    settings put global airplane_mode_on "$V" > /dev/null 2>&1
    am broadcast -a android.intent.action.AIRPLANE_MODE --ez state true > /dev/null 2>&1
    case "$V" in 1) echo "[*] mode avion active" ;; *) echo "[*] mode avion desactive" ;; esac
}

do_off()
{
    if ! require_root; then
        return 1
    fi

    echo ""
    echo "=== DISABLE WIRELESS ==="

    echo "[1] Services radio..."
    svc wifi disable > /dev/null 2>&1 && echo "    [ OK ] svc wifi disable"
    svc bluetooth disable > /dev/null 2>&1 && echo "    [ OK ] svc bluetooth disable"

    echo "[2] Reglages persistants..."
    settings put global wifi_on 0 > /dev/null 2>&1 && echo "    [ OK ] wifi_on=0 (persiste au reboot)"
    settings put global bluetooth_on 0 > /dev/null 2>&1 && echo "    [ OK ] bluetooth_on=0"

    echo "[3] Services residuels..."
    kill_radio_services

    echo "[4] Interfaces..."
    for IF in $WIFI_IFS; do
        TRY=0
        while [ "$TRY" -lt 2 ]; do
            iface_down "$IF" && break
            ip link set "$IF" down > /dev/null 2>&1
            sleep 1
            TRY=$((TRY+1))
        done
        if iface_down "$IF"; then
            echo "    [ OK ] $IF coupee (ou absente)"
        else
            echo "    [WARN] $IF encore UP apres 2 essais"
        fi
    done

    echo "[5] rfkill..."
    if rfkill_all block; then
        echo "    [ OK ] bloque"
    else
        echo "    [ -- ] rfkill indisponible (sans importance ici)"
    fi

    case "$(config_get WIRELESS_AIRPLANE 0)" in
        1) set_airplane 1 ;;
    esac

    echo ""
    verify_off
    return $?
}

verify_off()
{
    echo "--- Verification ---"
    RC=0

    W="$(prop_get wifi_on)"
    B="$(prop_get bluetooth_on)"
    [ "$W" = "0" ] && echo "  [ OK ] wifi_on=0"     || { echo "  [WARN] wifi_on=$W"; }
    [ "$B" = "0" ] && echo "  [ OK ] bluetooth_on=0" || { echo "  [WARN] bluetooth_on=$B"; }

    for IF in $WIFI_IFS; do
        if iface_down "$IF"; then
            echo "  [ OK ] $IF absente/coupee"
        else
            echo "  [WARN] $IF toujours UP"
            RC=1
        fi
    done

    if [ -e "/sys/class/bluetooth/hci0" ]; then
        echo "  [WARN] hci0 encore present"
        RC=1
    else
        echo "  [ OK ] hci0 absent"
    fi

    echo ""
    return "$RC"
}

do_status()
{
    echo ""
    echo "=== WIRELESS STATUS ==="
    echo "  wifi_on       : $(prop_get wifi_on)"
    echo "  bluetooth_on  : $(prop_get bluetooth_on)"
    echo "  airplane      : $(prop_get airplane_mode_on)"

    for IF in $WIFI_IFS; do
        ST="$(ip link show "$IF" 2>/dev/null | tr -d '\r')"
        case "$ST" in
            "")                             echo "  $IF          : absente" ;;
            *"state UP"*)                   echo "  $IF          : UP" ;;
            *)                              echo "  $IF          : DOWN/presente" ;;
        esac
    done

    if [ -e "/sys/class/bluetooth/hci0" ]; then
        echo "  hci0         : present ($(cat /sys/class/bluetooth/hci0/address 2>/dev/null))"
    else
        echo "  hci0         : absent"
    fi
    echo ""
    return 0
}

do_on()
{
    if ! require_root; then
        return 1
    fi

    echo ""
    echo "=== RESTAURATION WIRELESS ==="
    rfkill_all unblock && echo "[ OK ] rfkill debloque"
    svc wifi enable > /dev/null 2>&1 && echo "[ OK ] svc wifi enable"
    svc bluetooth enable > /dev/null 2>&1 && echo "[ OK ] svc bluetooth enable"
    settings put global wifi_on 1 > /dev/null 2>&1 && echo "[ OK ] wifi_on=1"
    settings put global bluetooth_on 1 > /dev/null 2>&1 && echo "[ OK ] bluetooth_on=1"
    case "$(config_get WIRELESS_AIRPLANE 0)" in
        1) set_airplane 0 ;;
    esac

    echo ""
    echo "[ INFO ] interfaces recreees au reboot si besoin (wlan0/p2p0/hci0)"
    echo ""
    return 0
}

usage()
{
    echo ""
    echo "Usage: disable_wireless <OFF|STATUS|ON>"
    echo ""
    echo "  OFF      coupe Wi-Fi/BT + persiste + verifie (defaut)"
    echo "  STATUS   etat des radios et interfaces"
    echo "  ON       restaure (reboot conseille pour les interfaces)"
    echo ""
    return 1
}

case "$1" in
    ""|OFF|off)        do_off ;;
    STATUS|status)     do_status ;;
    ON|on)             do_on ;;
    HELP|help|-h|--help) usage ;;
    *)                 usage ;;
esac
