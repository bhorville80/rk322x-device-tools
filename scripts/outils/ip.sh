#!/system/bin/sh
# ip - etat IP de la box : adresse, interface, masque, route, MAC,
# etat du lien. Version courte et directe de net_diag pour la vue
# "quelle IP ?" demandee par docs/AGENTS.md (question centrale).
#
# Usage: ip [STATUS] : synthesis reseau (defaut)
#        ip MAC      : adresses MAC des interfaces
#        ip help

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
    if [ -f "$B/core/config.sh" ]; then
        . "$B/core/config.sh"
        break
    fi
done

IFACE="$(config_get INTERFACE eth0)"
EXPECT_IP="$(config_get IP 192.168.50.20)"

ip_of()
{
    ip addr show "$1" 2>/dev/null \
        | sed -n 's/.* inet \([0-9.]*\)\/.*/\1/p' | head -n 1 | tr -d '\r'
}

prefix_of()
{
    ip addr show "$1" 2>/dev/null \
        | sed -n 's/.* inet \([0-9.]*\)\/\([0-9][0-9]*\).*/\2/p' | head -n 1 | tr -d '\r'
}

prefix_to_mask()
{
    case "$1" in
        8)  echo "255.0.0.0" ;;
        16) echo "255.255.0.0" ;;
        24) echo "255.255.255.0" ;;
        32) echo "255.255.255.255" ;;
        *)  echo "" ;;
    esac
}

mac_of()
{
    cat "/sys/class/net/$1/address" 2>/dev/null | tr -d '\r'
}

state_of()
{
    case "$(ip link show "$1" 2>/dev/null | tr -d '\r')" in
        *"state UP"*)      echo "UP" ;;
        *"state UNKNOWN"*) echo "UP (unknown)" ;;
        "")                echo "absente" ;;
        *)                 echo "DOWN" ;;
    esac
}

main()
{
    case "$1" in
        ""|STATUS|status)  main_status ;;
        MAC|mac)           list_macs ;;
        HELP|help|-h|--help) usage ;;
        *)                 usage ; return 1 ;;
    esac
}

main_status()
{
    echo ""
    echo "=== IP ($IFACE, attendu $EXPECT_IP) ==="

    ST="$(state_of "$IFACE")"
    printf '  %-14s %s (%s)\n' "Interface" "$IFACE" "$ST"

    CUR="$(ip_of "$IFACE")"
    if [ -n "$CUR" ]; then
        printf '  %-14s %s\n' "Adresse IP" "$CUR"

        P_="$(prefix_of "$IFACE")"
        case "$P_" in
            ''|*[!0-9]*) ;;
            *)  M_="$(prefix_to_mask "$P_")"
                [ -n "$M_" ] || M_="?"
                printf '  %-14s %s (/%s)\n' "Masque" "$M_" "$P_"
                ;;
        esac

        MAC_="$(mac_of "$IFACE")"
        [ -n "$MAC_" ] && printf '  %-14s %s\n' "MAC" "$MAC_"
    else
        printf '  %-14s %s\n' "Adresse IP" "aucune (remede : set_network)"
    fi

    RGW="$(ip route 2>/dev/null | tr -d '\r' | sed -n 's/^default via \([0-9.]*\).*/\1/p' | head -n 1)"
    printf '  %-14s %s\n' "Route defaut" "${RGW:-absente}"

    echo ""
    if [ -n "$CUR" ]; then
        if [ "$CUR" = "$EXPECT_IP" ]; then
            echo "[ OK ] IP conforme a la config ($EXPECT_IP)"
            return 0
        fi
        echo "[WARN] IP ($CUR) differente de la config ($EXPECT_IP)"
        return 0
    fi
    echo "[ERREUR] aucune adresse sur $IFACE (remede : set_network)"
    return 1
}

list_macs()
{
    echo ""
    echo "=== ADRESSES MAC ==="
    FOUND=0
    for D in /sys/class/net/*; do
        N="$(basename "$D")"
        M="$(mac_of "$N")"
        [ -n "$M" ] || continue
        printf '  %-10s %s\n' "$N" "$M"
        FOUND=$((FOUND+1))
    done
    [ "$FOUND" -eq 0 ] && echo "  (aucune interface visible)"
    echo ""
    return 0
}

usage()
{
    echo ""
    echo "Usage: ip [STATUS|MAC|HELP]"
    echo ""
    echo "  STATUS   adresse, masque, route, etat (defaut)"
    echo "  MAC      adresses MAC des interfaces"
    echo ""
    return 0
}

if [ "$RUNLOG_LOADED" -eq 1 ] && runlog_start "$SCRIPT_ID"; then
    main "$@" >> "$RUNLOG_FILE" 2>&1 ; RC=$?
    runlog_end "$RC" ; cat "$RUNLOG_FILE"
else
    main "$@" ; RC=$?
fi
exit "$RC"