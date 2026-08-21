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

    echo "[2] Nettoyage ancienne configuration..."

    ip addr flush dev "$IFACE"

    echo "[3] Configuration IP..."

    ip addr add "$IP/$PREFIX" dev "$IFACE"

    echo "[4] Route par défaut..."

    ip route del default 2>/dev/null
    ip route add default via "$GATEWAY" dev "$IFACE"

    echo "[5] DNS..."

    setprop net.dns1 "$DNS"
    setprop net.dns2 "8.8.8.8"

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
