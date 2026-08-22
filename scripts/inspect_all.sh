#!/system/bin/sh
# inspect_all - rapport global : enchainne tous les outils de verification
# et d'inspection, avec synthese finale des resultats (rc par outil).
# Les outils ecrivent aussi chacun leur propre log dans log/exec/.

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

BASE="$(cd "$(dirname "$0")" && pwd)"
[ -d "$BASE/scripts" ] && BASE="$BASE/scripts"

SUMMARY=""
FAILS=0

run_section()
{
    TITLE="$1"; shift
    echo ""
    echo "============================================================"
    echo "  $TITLE"
    echo "============================================================"

    OUT="$(sh "$@" 2>&1)"
    RC=$?

    echo "$OUT"
    echo ""
    printf '>>> %-24s rc=%s\n' "$TITLE" "$RC"

    SUMMARY="$SUMMARY
$(printf '  %-26s rc=%s' "$TITLE" "$RC")"

    case "$RC" in
        0) ;;
        *) [ "$RC" -gt 1 ] && FAILS=$((FAILS+1)) ;;
    esac
}

main()
{
    START_S="$(cut -d. -f1 /proc/uptime 2>/dev/null | tr -dc '0-9')"

    echo ""
    echo "### INSPECT GLOBAL - $(getprop ro.product.device 2>/dev/null) - Android $(getprop ro.build.version.release 2>/dev/null)"

    run_section "check_state"      "$BASE/check_state.sh"
    run_section "inspect_system"   "$BASE/inspect_system.sh"
    run_section "inspect_services" "$BASE/inspect_services.sh"
    run_section "inspect_gui"      "$BASE/inspect_gui.sh" STATUS
    run_section "inspect_display"  "$BASE/inspect_display.sh"
    run_section "inspect_remote"   "$BASE/inspect_remote.sh"
    run_section "inspect_user"     "$BASE/inspect_user.sh"
    run_section "thermal"          "$BASE/thermal.sh" STATUS
    run_section "cut_services"     "$BASE/cut_services.sh" STATUS
    run_section "front_led"        "$BASE/front_led.sh" STATUS

    END_S="$(cut -d. -f1 /proc/uptime 2>/dev/null | tr -dc '0-9')"
    DUREE=""
    if [ -n "$START_S" ] && [ -n "$END_S" ]; then
        DUREE=" ($((END_S - START_S))s)"
    fi

    echo ""
    echo "============================================================"
    echo "  SYNTHESE$DUREE"
    echo "============================================================"
    echo "$SUMMARY"
    echo ""
    if [ "$FAILS" -gt 0 ]; then
        echo "  [WARN] $FAILS outil(s) en anomalie (rc>=2)"
    else
        echo "  [ OK ] tous les outils ont repondu"
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
