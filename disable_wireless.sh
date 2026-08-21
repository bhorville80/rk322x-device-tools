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
    echo "=== DISABLE WIRELESS ==="

    echo "[1] Wi-Fi (svc)..."
    if svc wifi disable 2>/dev/null; then
        echo "    [ OK ]"
    else
        echo "    [ ERREUR ]"
    fi

    echo "[2] Bluetooth (settings)..."
    if settings put global bluetooth_on 0 2>/dev/null; then
        echo "    [ OK ]"
    else
        echo "    [ ERREUR ]"
    fi

    echo "[3] Arret services bluetooth..."
    stop bluetooth 2>/dev/null
    stop com.android.bluetooth 2>/dev/null
    echo "    [ OK ]"

    echo "[4] Interfaces reseau..."
    if ifconfig wlan0 down 2>/dev/null; then
        echo "    wlan0 : [ OK ]"
    else
        echo "    wlan0 : [ -- ] absent"
    fi
    if ifconfig p2p0 down 2>/dev/null; then
        echo "    p2p0  : [ OK ]"
    else
        echo "    p2p0  : [ -- ] absent"
    fi
    if hciconfig hci0 down 2>/dev/null; then
        echo "    hci0  : [ OK ]"
    else
        echo "    hci0  : [ -- ] absent"
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
