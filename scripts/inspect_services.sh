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

echo ""
echo "=== INSPECTION SERVICES ==="

echo ""
echo "[1] Services init (etat running/stopped)"
SVC_OUT="$(getprop 2>/dev/null | grep '^\[init.svc')"
if [ -n "$SVC_OUT" ]; then
    echo "$SVC_OUT" | sed 's/^/      /'
else
    echo "      [ -- ] aucun init.svc remonte"
fi

RUNNING="$(echo "$SVC_OUT" | grep -c ': \[running\]')"
STOPPED="$(echo "$SVC_OUT" | grep -c ': \[stopped\]')"
printf '\n      %-14s : %s\n' "Running" "${RUNNING:-0}"
printf '      %-14s : %s\n' "Stopped" "${STOPPED:-0}"

echo ""
echo "[2] Packages"
PKG_SYS="$(pm list packages -s 2>/dev/null | wc -l)"
PKG_3RD="$(pm list packages -3 2>/dev/null | wc -l)"
PKG_DIS="$(pm list packages -d 2>/dev/null | wc -l)"
printf '      %-14s : %s\n' "Systeme" "$PKG_SYS"
printf '      %-14s : %s\n' "Tiers" "$PKG_3RD"
printf '      %-14s : %s\n' "Desactives" "$PKG_DIS"

echo ""
echo "[3] Packages tiers installes"
THIRD_OUT="$(pm list packages -3 2>/dev/null)"
if [ -n "$THIRD_OUT" ]; then
    echo "$THIRD_OUT" | sed 's/^/      /'
else
    echo "      [ -- ] aucun package tiers"
fi

echo ""
echo "[4] Top RAM par processus"
DUMP_OUT="$(dumpsys meminfo 2>/dev/null | sed -n '/Total PSS by process/,/Total PSS:/p')"
if [ -n "$DUMP_OUT" ]; then
    echo "$DUMP_OUT" | head -n 20 | sed 's/^/      /'
else
    echo "      [ -- ] dumpsys indisponible"
fi

echo ""
echo "[5] SurfaceFlinger (cout interface graphique)"
SF_INFO="$(dumpsys meminfo surfaceflinger 2>/dev/null | grep TOTAL)"
if [ -n "$SF_INFO" ]; then
    echo "$SF_INFO" | sed 's/^/      /'
else
    echo "      [ -- ] surfaceflinger non mesureable"
fi

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

