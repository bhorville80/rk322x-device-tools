#!/system/bin/sh
# inspect_display - afficheur digital frontal (LED/VFD)
# inventaire en lecture seule : noeuds sysfs, drivers, daemons,
# et moyens de modification possibles.

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

echo ""
echo "=== INSPECTION AFFICHEUR DIGITAL ==="

echo ""
echo "[1] LED sysfs (/sys/class/leds)"
if ls -1 /sys/class/leds > /dev/null 2>&1 && [ -n "$(ls -1 /sys/class/leds 2>/dev/null)" ]; then
    for D in /sys/class/leds/*; do
        N="$(basename "$D")"
        CUR="$(cat "$D/brightness" 2>/dev/null)"
        MAX="$(cat "$D/max_brightness" 2>/dev/null)"
        TRG="$(sed -n 's/.*\[\([^]]*\)\].*/\1/p' "$D/trigger" 2>/dev/null)"
        printf '      %-24s bright=%-4s max=%-4s %s\n' "$N" "${CUR:-?}" "${MAX:-?}" "${TRG:+[$TRG]}"
        if [ -w "$D/brightness" ]; then
            echo "        -> brightness inscriptible : modification possible"
        else
            echo "        -> brightness non inscriptible (driver noyau ou droits)"
        fi
    done
else
    echo "      [ -- ] aucun noeud /sys/class/leds"
fi

echo ""
echo "[2] Noeuds /dev candidats afficheur"
FOUND=0
for P in /dev/vfd* /dev/led* /dev/seg* /dev/fd6* /dev/tm1* /dev/display* /dev/rtc*; do
    [ -e "$P" ] || continue
    printf '      %-16s %s\n' "$(basename "$P")" "$(ls -l "$P" 2>/dev/null | awk '{print $1, $5}')"
    FOUND=1
done
[ "$FOUND" -eq 0 ] && echo "      [ -- ] aucun noeud vfd/led/seg detecte"

echo ""
echo "[3] Drivers noyau (/proc/modules + dmesg)"
MOD_OUT="$(grep -iE 'fd6|tm16|vfd|seg|gpio.*led|leds' /proc/modules 2>/dev/null)"
if [ -n "$MOD_OUT" ]; then
    echo "$MOD_OUT" | awk '{printf "      %-20s %s\n", $1, $3}' 
else
    echo "      [ -- ] aucun module led charge (peut-etre built-in)"
fi

DM_OUT="$(dmesg 2>/dev/null | grep -iE 'fd65|tm16|vfd|front.*display|segment|gpio-led' | tail -n 10)"
if [ -n "$DM_OUT" ]; then
    echo "      dmesg :"
    echo "$DM_OUT" | sed 's/^/        /'
fi

echo ""
echo "[4] Daemons / services lies afficheur"
SVC_OUT="$(getprop 2>/dev/null | grep '^\[init.svc' | grep -iE 'vfd|led|display|panel|clock')"
PS_OUT="$(ps 2>/dev/null | grep -iE 'vfd|ledserv|display_daemon|clock' | grep -v grep)"
if [ -n "$SVC_OUT" ] || [ -n "$PS_OUT" ]; then
    echo "$SVC_OUT" | sed 's/^/      /'
    echo "$PS_OUT" | sed 's/^/      /'
else
    echo "      [ -- ] aucun daemon dedie detecte"
fi

echo ""
echo "[5] Device tree (noeuds leds/vfd)"
DT="/proc/device-tree"
for D in "$DT/leds" "$DT/gpio-leds" "$DT/vfd" "$DT/rk_led"; do
    if [ -d "$D" ]; then
        echo "      $D :"
        ls -1 "$D" 2>/dev/null | sed 's/^/        /'
        COMPAT="$(cat "$D/compatible" 2>/dev/null | tr '\0' ' ')"
        [ -n "$COMPAT" ] && echo "        compatible : $COMPAT"
    fi
done

echo ""
echo "[6] Synthese modification"
echo "      - sysfs leds inscriptible : echo <val> > .../brightness"
echo "        triggers : echo none|heartbeat|timer > .../trigger"
echo "      - driver dedie (fd65x/tm16x) : pilotage via /dev ou daemon"
echo "        -> verifier le binaire/service qui ecrit sur ce noeud"
echo "      - rien trouve = pas d'afficheur digital sur cette box"

echo ""
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
