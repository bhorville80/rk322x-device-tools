#!/system/bin/sh

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

for B in "$(dirname "$0")" "$(dirname "$0")/.." "$(dirname "$0")/../.." /data/scripts; do
    if [ -f "$B/core/config.sh" ]; then
        . "$B/core/config.sh"
        break
    fi
done

EXPECTED_IP="$(config_get IP 192.168.50.20)"
IFACE="$(config_get INTERFACE eth0)"
DEVICE_NAME="$(config_get DEVICE_NAME boitier)"

PASS=0
FAIL=0
WARN=0

ok()   { printf '  [ OK ] %-18s %s\n' "$1" "$2"; PASS=$((PASS+1)); }
ko()   { printf '  [ KO ] %-18s %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }
warn() { printf '  [WARN] %-18s %s\n' "$1" "$2"; WARN=$((WARN+1)); }
info() { printf '  [ -- ] %-18s %s\n' "$1" "$2"; }

main()
{
    echo ""
    echo "=== VERIFICATION ETAT ==="
    echo ""
    echo "--- BOITIER ---"
    info "Boitier" "$DEVICE_NAME"

    echo ""
    echo "--- RESEAU / IP ---"

    ETH_OUT="$(ip link show "$IFACE" 2>/dev/null)"
    if [ -z "$ETH_OUT" ]; then
        ko "Interface $IFACE" "absente"
    else
        case "$ETH_OUT" in
            *"state UP"*)       ok "Interface $IFACE" "UP" ;;
            *"state UNKNOWN"*)  ok "Interface $IFACE" "UP (unknown)" ;;
            *)                  warn "Interface $IFACE" "DOWN" ;;
        esac
    fi

    IP_CUR="$(ip addr show "$IFACE" 2>/dev/null | sed -n 's/.*inet \([0-9.]*\).*/\1/p' | head -n 1)"
    if [ -n "$IP_CUR" ]; then
        if [ "$IP_CUR" = "$EXPECTED_IP" ]; then
            ok "Adresse IP" "$IP_CUR"
        else
            warn "Adresse IP" "$IP_CUR (attendu : $EXPECTED_IP)"
        fi
    else
        ko "Adresse IP" "aucune adresse sur $IFACE"
    fi

    GW="$(ip route 2>/dev/null | sed -n 's/^default via \([0-9.]*\).*/\1/p')"
    if [ -n "$GW" ]; then
        ok "Passerelle" "$GW"
        if ping -c 1 -W 2 "$GW" >/dev/null 2>&1; then
            ok "Ping passerelle" "reponse OK"
        else
            warn "Ping passerelle" "pas de reponse de $GW"
        fi
    else
        warn "Passerelle" "absente"
    fi

    DNS1="$(getprop net.dns1 2>/dev/null)"
    if [ -n "$DNS1" ]; then
        ok "DNS" "$DNS1 ($(getprop net.dns2 2>/dev/null))"
    else
        warn "DNS" "net.dns1 non defini"
    fi

    echo ""
    echo "--- WIRELESS / BLUETOOTH ---"

    WIFI_ON="$(settings get global wifi_on 2>/dev/null)"
    case "$WIFI_ON" in
        0)  ok "Wi-Fi" "desactive" ;;
        1)  warn "Wi-Fi" "ACTIF (desactivation possible : disable_wireless)" ;;
        *)  info "Wi-Fi" "etat inconnu ($WIFI_ON)" ;;
    esac

    for WLAN_IF in wlan0 p2p0; do
        I_OUT="$(ip link show "$WLAN_IF" 2>/dev/null)"
        if [ -z "$I_OUT" ]; then
            ok "$WLAN_IF" "absente"
        else
            case "$I_OUT" in
                *"state UP"*)   warn "$WLAN_IF" "UP" ;;
                *)              ok "$WLAN_IF" "presente mais DOWN" ;;
            esac
        fi
    done

    BT_ON="$(settings get global bluetooth_on 2>/dev/null)"
    case "$BT_ON" in
        0)  ok "Bluetooth" "desactive" ;;
        1)  warn "Bluetooth" "ACTIF (desactivation possible : disable_wireless)" ;;
        *)  info "Bluetooth" "etat inconnu ($BT_ON)" ;;
    esac

    if [ -e "/sys/class/bluetooth/hci0" ]; then
        HCI_UP="$(cat /sys/class/bluetooth/hci0/address 2>/dev/null)"
        warn "hci0" "present${HCI_UP:+ (adr $HCI_UP)}"
    else
        ok "hci0" "absent"
    fi

    echo ""
    echo "--- HDMI / AFFICHAGE ---"

    BLANK="$(cat /sys/class/graphics/fb0/blank 2>/dev/null)"
    case "$BLANK" in
        1)   ok "Framebuffer" "blank (ecran eteint)" ;;
        0)   info "Framebuffer" "actif" ;;
        "")  info "Framebuffer" "noeud fb0/blank absent" ;;
        *)   info "Framebuffer" "etat : $BLANK" ;;
    esac

    HDMI_FOUND=0
    for F in /sys/class/display/HDMI /sys/class/display/display0.HDMI; do
        [ -e "$F" ] || continue
        HDMI_FOUND=1
        V="$(cat "$F" 2>/dev/null | tr '\n' ' ' | cut -c1-40)"
        case "$V" in
            *disable*)  ok "HDMI sysfs" "$F = $V" ;;
            *enable*)   info "HDMI sysfs" "$F = $V" ;;
            "")         info "HDMI sysfs" "$F (vide)" ;;
            *)          info "HDMI sysfs" "$F = $V" ;;
        esac
    done
    [ "$HDMI_FOUND" -eq 0 ] && info "HDMI sysfs" "aucun noeud /sys/class/display/HDMI"

    WM_SIZE="$(wm size 2>/dev/null | sed 's/.*: //')"
    if [ -n "$WM_SIZE" ]; then
        info "Resolution" "$WM_SIZE"
    else
        info "Resolution" "wm indisponible"
    fi

    echo ""
    echo "--- SYSTEME ---"

    UP_S="$(cut -d. -f1 /proc/uptime 2>/dev/null)"
    if [ -n "$UP_S" ]; then
        info "Uptime" "$((UP_S / 3600))h$(((UP_S % 3600) / 60))m"
    fi

    MEM_AVAIL="$(sed -n 's/MemAvailable: *\([0-9]*\) kB/\1/p' /proc/meminfo 2>/dev/null)"
    MEM_TOTAL="$(sed -n 's/MemTotal: *\([0-9]*\) kB/\1/p' /proc/meminfo 2>/dev/null)"
    if [ -n "$MEM_TOTAL" ]; then
        if [ -n "$MEM_AVAIL" ]; then
            info "RAM" "${MEM_AVAIL} Mo dispo / ${MEM_TOTAL} Mo"
        else
            info "RAM" "total ${MEM_TOTAL} Mo"
        fi
    fi

    TEMP="$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | tr -dc '0-9')"
    ZTYPE="$(cat /sys/class/thermal/thermal_zone0/type 2>/dev/null)"
    case "$TEMP" in
        ''|*[!0-9]*) ;;
        *)
            C=$((TEMP / 1000))
            if [ "$C" -ge 75 ]; then
                warn "Temperature" "${ZTYPE:-cpu} ${C}C (elevee, voir thermal)"
            else
                ok "Temperature" "${ZTYPE:-cpu} ${C}C"
            fi
            ;;
    esac

    GOV="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null | tr -d '\r')"
    CURF="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null | tr -dc '0-9')"
    if [ -n "$GOV" ]; then
        FREQ_S=""
        case "$CURF" in
            ''|*[!0-9]*) ;;
            *) FREQ_S=" $((CURF / 1000))MHz" ;;
        esac
        info "CPU" "$GOV$FREQ_S"
    fi

    echo ""
    echo "=== RESUME ==="
    printf '  OK : %-4d KO : %-4d WARN : %d\n' "$PASS" "$FAIL" "$WARN"
    echo ""

    if [ "$FAIL" -eq 0 ]; then
        return 0
    fi
    return 1
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
