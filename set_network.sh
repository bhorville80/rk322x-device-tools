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

main()
{

IFACE="eth0"
IP="192.168.50.20"
PREFIX="24"
GATEWAY="192.168.50.1"
DNS="192.168.50.1"

echo "=== RK322X NETWORK CONFIG ==="

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

