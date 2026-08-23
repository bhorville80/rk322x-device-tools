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

for B in "$(dirname "$0")" "$(dirname "$0")/.." /data/scripts; do
    if [ -f "$B/core/config.sh" ]; then
        . "$B/core/config.sh"
        break
    fi
done

IFACE="$(config_get INTERFACE eth0)"
IP="$(config_get IP 192.168.50.20)"
PREFIX="$(config_get PREFIX 24)"
GATEWAY="$(config_get GATEWAY 192.168.50.1)"
DNS="$(config_get DNS 192.168.50.1)"

main()
{
    echo ""
    echo "=== RK322X NETWORK CONFIG ==="
    if ! require_root; then
        return 1
    fi

    echo "[1] Interface: $IFACE"

    ip link set "$IFACE" up

    # adresse courante : si elle est deja conforme, ON NE TOUCHE PAS aux
    # adresses (un flush couperait l'acces reseau / adb reseau en plein vol)
    CUR_IP="$(ip -4 addr show "$IFACE" 2>/dev/null | sed -n 's/.*inet \([0-9.]*\).*/\1/p' | head -n 1)"
    [ -z "$CUR_IP" ] && CUR_IP="$(ifconfig "$IFACE" 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1p')"

    if [ "$CUR_IP" = "$IP" ]; then
        echo "[2] Adresse deja conforme ($IP) -> aucune modification d'adresse"
    else
        echo "[2] Bascule d'adresse SANS COUPURE ($CUR_IP -> $IP)..."
        # on AJOUTE d'abord la nouvelle ; l'ancienne n'est retiree qu'apres
        if ip addr add "$IP/$PREFIX" dev "$IFACE" 2>/dev/null; then
            [ -n "$CUR_IP" ] && ip addr del "$CUR_IP" dev "$IFACE" 2>/dev/null
            echo "    [ OK ] $IP active"
        else
            echo "    [WARN] ajout de $IP refuse - adresse actuelle ($CUR_IP) CONSERVEE"
        fi
    fi

    echo "[3] Route par defaut..."

    ip route del default 2>/dev/null
    if ip route add default via "$GATEWAY" dev "$IFACE" 2>/dev/null; then
        echo "    [ OK ] via $GATEWAY"
    else
        echo "    [WARN] route par defaut non posee (gateway joignable ?)"
    fi

    echo "[4] DNS..."

    setprop net.dns1 "$DNS"
    setprop net.dns2 "8.8.8.8"

    echo
    echo "=== CONFIGURATION ==="

    ip addr show "$IFACE"

    echo
    echo "=== CONFIGURATION ==="

    ip addr show "$IFACE"

    echo
    echo "=== ROUTES ==="

    ip route

    echo
    echo "=== DNS ==="

    getprop | grep -E 'net.dns'

    echo
    echo "NETWORK READY"
    echo "IP      : $IP"
    echo "MASK    : /$PREFIX"
    echo "GATEWAY : $GATEWAY"
    echo "DNS     : $DNS"

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
