#!/bin/sh
# vitals_history.sh - un passage de collecte des signes vitaux, toutes les boxes
#
# Pour chaque box joignable : `vitals CSV` via adb -> append dans
# history/vitals/<ip>.csv (en-tete ecrit a la creation du fichier).
# A planifier cote PC :
#   cron Linux   : */10 * * * *  /chemin/admin/linux/vitals_history.sh
#   Task Sch. Win: idem via le .ps1 jumeau
#
# Usage:
#   admin/linux/vitals_history.sh                 # cibles = config/fleet.txt
#   admin/linux/vitals_history.sh 192.168.50.20   # ou liste en arguments
#
# Format fleet.txt : une IP:port (ou IP seule) par ligne, # = commentaire.

REPO="$(cd "$(dirname "$0")/../.." && pwd)"

die() { echo "[ERREUR vitals-h] $*" >&2; exit 1; }

OUT_DIR="$REPO/history/vitals"

TARGETS=""
if [ $# -gt 0 ]; then
    TARGETS="$*"
else
    FLEET="$REPO/config/fleet.txt"
    if [ -f "$FLEET" ]; then
        TARGETS="$(grep -vE '^\s*(#|$)' "$FLEET" | tr '\n' ' ')"
    fi
    if [ -z "$TARGETS" ]; then
        CONF="$REPO/config/device.conf"
        [ -f "$CONF" ] || die "ni config/fleet.txt ni config/device.conf"
        IP="$(sed -n 's/^IP=//p' "$CONF" | head -n 1 | tr -d '\r')"
        [ -n "$IP" ] || die "IP illisible"
        TARGETS="$IP:5555"
    fi
fi

command -v adb >/dev/null 2>&1 || die "adb introuvable dans le PATH"
mkdir -p "$OUT_DIR" || die "history/vitals inaccessible"

CSV_HEADER="epoch,tmax_c,tmax_zone,cpu_mhz,governor,load1,ram_pct,uptime_min"

for T in $TARGETS; do
    case "$T" in
        *:*) TGT="$T" ;;
        *)   TGT="$T:5555" ;;
    esac
    IP="${TGT%%:*}"

    adb connect "$TGT" > /dev/null 2>&1
    V="$(adb -s "$TGT" shell 'su -c "sh /data/scripts/vitals.sh CSV"' 2>/dev/null | tr -d '\r')"
    case "$V" in
        [0-9]*,*)
            CSV="$OUT_DIR/$IP.csv"
            if [ ! -s "$CSV" ]; then
                printf '%s\n' "$CSV_HEADER" > "$CSV"
            fi
            printf '%s\n' "$V" >> "$CSV"
            echo "[ OK ] $IP -> $(basename "$CSV") : $V"
            ;;
        "")
            echo "[ KO ] $IP injoignable ou toolkit absent"
            ;;
        *)
            echo "[ ?? ] $IP reponse inattendue : $V"
            ;;
    esac
done

exit 0
