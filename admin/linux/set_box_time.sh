#!/bin/sh
# set_box_time.sh - force la mise a l'heure de la box depuis le PC (Linux, via adb)
#
# Pousse l'heure UTC du PC vers la box :
#   - chemin privilegie : set_time SET (toolkit installe sur /data/scripts)
#   - fallback          : date -u -s directe (toolkit absent)
#
# Usage:
#   admin/linux/set_box_time.sh                 # cible par defaut IP:5555 de device.conf
#   admin/linux/set_box_time.sh -t 192.168.50.20:5555
#   DPK_TARGET=192.168.50.20:5555 admin/linux/set_box_time.sh
#
# Prerequis : adb dans le PATH + acces root sur la box (su).

REPO="$(cd "$(dirname "$0")/../.." && pwd)"

die() { echo "[ERREUR heure] $*" >&2; exit 1; }

usage()
{
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
}

TARGET=""
while [ $# -gt 0 ]; do
    case "$1" in
        -t|--target) TARGET="$2"; shift 2 ;;
        -h|--help)   usage; exit 0 ;;
        *)           die "option inconnue : $1 (-h pour l'aide)" ;;
    esac
done

command -v adb >/dev/null 2>&1 || die "adb introuvable dans le PATH"

if [ -z "$TARGET" ]; then
    TARGET="${DPK_TARGET:-}"
fi

if [ -z "$TARGET" ]; then
    CONF="$REPO/config/device.conf"
    [ -f "$CONF" ] || die "config/device.conf introuvable (et pas de -t)"
    IP="$(sed -n 's/^IP=//p' "$CONF" | head -n 1 | tr -d '\r')"
    [ -n "$IP" ] || die "IP illisible dans config/device.conf"
    PORT="$(sed -n 's/^ADB_PORT=//p' "$CONF" | head -n 1 | tr -d '\r')"
    [ -n "$PORT" ] || PORT="5555"
    TARGET="$IP:$PORT"
fi

case "$TARGET" in
    *:*) adb connect "$TARGET" > /dev/null 2>&1 ;;
esac

adb_run() { adb -s "$TARGET" "$@"; }

rget() { adb_run shell "$1" 2>/dev/null | tr -d '\r'; }
rrun() { adb_run shell "su -c '$1'" > /dev/null 2>&1; }

adb_run get-prop ro.product.device > /dev/null 2>&1 || \
    adb_run echo ok > /dev/null 2>&1 || die "box injoignable : $TARGET"

NOW="$(date -u '+%Y%m%d.%H%M%S')"
echo "[..] heure PC (UTC) : $NOW -> $TARGET"

if [ "$(rget 'test -f /data/scripts/set_time.sh && echo ok')" = "ok" ]; then
    MODE="set_time SET"
    rrun "sh /data/scripts/set_time.sh SET $NOW"
else
    MODE="date -u -s (toolkit absent)"
    rrun "date -u -s $NOW"
fi

sleep 1
BOX_DATE="$(rget "date '+%Y-%m-%d %H:%M:%S'")"
echo "[ OK ] regle via : $MODE"
echo "       box       : ${BOX_DATE:-illisible}"
echo "       PC (UTC)  : $(date -u '+%Y-%m-%d %H:%M:%S')"

[ -n "$BOX_DATE" ] || exit 1
exit 0
