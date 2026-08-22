#!/system/bin/sh

HDMI_NODES="/sys/class/display/HDMI /sys/class/display/display0.HDMI"
BLANK_NODES="/sys/class/graphics/fb0/blank"

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

do_status()
{
    echo ""
    echo "=== HDMI STATUS ==="
    for F in $HDMI_NODES /sys/class/graphics/fb0/blank /sys/class/graphics/fb0/mode; do
        [ -e "$F" ] || continue
        V="$(cat "$F" 2>/dev/null | tr '\n' ' ' | cut -c1-50)"
        [ -z "$V" ] && V="(vide)"
        printf '  %-40s : %s\n' "$F" "$V"
    done
    WM_SIZE="$(wm size 2>/dev/null)"
    [ -n "$WM_SIZE" ] && echo "  $WM_SIZE"
    return 0
}

do_off()
{
    echo ""
    echo "=== HDMI OFF ==="

    OK=0

    for F in $HDMI_NODES; do
        [ -w "$F" ] || continue
        if echo disable > "$F" 2>/dev/null; then
            echo "[ OK ] $F <- disable"
            OK=1
        fi
    done

    for F in $BLANK_NODES; do
        [ -w "$F" ] || continue
        if echo 1 > "$F" 2>/dev/null; then
            echo "[ OK ] $F <- blank (ecran eteint, signal coupe selon noyau)"
            OK=1
        fi
    done

    if [ "$OK" -eq 0 ]; then
        echo "[ ERREUR ] aucun noeud sysfs exploitable sur ce noyau"
        echo "           lancer inspect_system.sh pour lister /sys/class/display"
        return 1
    fi

    echo ""
    echo "[ INFO ] reseau eth0 conserve, pilotage possible via adb/http"
    return 0
}

do_on()
{
    echo ""
    echo "=== HDMI ON ==="

    OK=0

    for F in $HDMI_NODES; do
        [ -w "$F" ] || continue
        if echo enable > "$F" 2>/dev/null; then
            echo "[ OK ] $F <- enable"
            OK=1
        fi
    done

    for F in $BLANK_NODES; do
        [ -w "$F" ] || continue
        if echo 0 > "$F" 2>/dev/null; then
            echo "[ OK ] $F <- unblank"
            OK=1
        fi
    done

    if [ "$OK" -eq 0 ]; then
        echo "[ ERREUR ] aucun noeud sysfs exploitable sur ce noyau"
        return 1
    fi
    return 0
}

main()
{
    case "$ACTION" in
        OFF)     do_off ;;
        ON)      do_on ;;
        STATUS)  do_status ;;
        *)
            echo ""
            echo "Usage: hdmi.sh <OFF|ON|STATUS>"
            echo ""
            echo "  OFF     Coupe la sortie HDMI + blank framebuffer"
            echo "  ON      Reactive la sortie HDMI"
            echo "  STATUS  Etat des noeuds sysfs display"
            echo ""
            return 1
            ;;
    esac
}

ACTION="$1"

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
