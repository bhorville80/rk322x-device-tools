#!/system/bin/sh

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
