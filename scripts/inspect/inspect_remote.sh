#!/system/bin/sh
# inspect_remote - telecommande IR
# inventaire en lecture seule : recepteur, devices input, layouts .kl,
# et moyens de remap possibles.

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" "$(dirname "$0")/.." /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

main()
{

echo ""
echo "=== INSPECTION TELECOMMANDE ==="

echo ""
echo "[1] Peripheriques input (/proc/bus/input/devices)"
IN_OUT="$(cat /proc/bus/input/devices 2>/dev/null)"
if [ -n "$IN_OUT" ]; then
    echo "$IN_OUT" | grep -E '^(I|N|H):' | sed 's/^/      /'
else
    echo "      [ -- ] /proc/bus/input/devices illisible"
fi

echo ""
echo "[2] Recepteur IR detecte"
IR_LINE="$(echo "$IN_OUT" | grep -iE 'Name=.*(remote|ir|rk29)' )"
if [ -n "$IR_LINE" ]; then
    echo "      $IR_LINE"
else
    echo "      [ -- ] aucun nom explicite, verifier liste ci-dessus"
fi

echo ""
echo "[3] Keylayouts presents (.kl)"
FOUND=0
for DIR in /system/usr/keylayout /vendor/usr/keylayout /system/etc; do
    if ls -1 "$DIR"/*.kl > /dev/null 2>&1; then
        for F in "$DIR"/*.kl; do
            SZ="$(du -h "$F" 2>/dev/null | cut -f1)"
            printf '      %-52s %s\n' "$F" "$SZ"
            FOUND=1
        done
    fi
done
[ "$FOUND" -eq 0 ] && echo "      [ -- ] aucun .kl trouve"

echo ""
echo "[4] Contenu des layouts candidats (scancode -> keycode)"
for F in \
    /system/usr/keylayout/rk29-keypad.kl \
    /system/usr/keylayout/Vendor_0001_Product_0001.kl \
    /system/usr/keylayout/Generic.kl ; do
    [ -f "$F" ] || continue
    echo "      --- $F ---"
    grep -v '^#' "$F" 2>/dev/null | grep -v '^[[:space:]]*$' | head -n 30 | sed 's/^/        /'
done

echo ""
echo "[5] Correspondance device -> layout attendu"
echo "      Vendor_XXXX_Product_XXXX.kl construit depuis les IDs [1] :"
echo "$IN_OUT" | grep '^I:' | while IFS=' ' read -r _F _BUS VEND PROD _REST; do
    V="$(printf '%s' "$VEND" | cut -d= -f2 | tr '[:lower:]' '[:upper:]')"
    P="$(printf '%s' "$PROD" | cut -d= -f2 | tr '[:lower:]' '[:upper:]')"
    [ -n "$V" ] && [ -n "$P" ] && printf '      Vendor_%s_Product_%s.kl\n' "$V" "$P"
done

echo ""
echo "[6] Droits de modification"
RW="non"
if mount 2>/dev/null | grep -q ' /system '; then
    mount 2>/dev/null | grep ' /system ' | sed 's/^/      /'
    case "$(mount 2>/dev/null | grep ' /system ')" in
        *rw*) RW="oui (/system deja rw)" ;;
        *)    RW="apres mount -o remount,rw /system" ;;
    esac
else
    RW="indetermine (pas de montage /system visible)"
fi
echo "      Modification .kl possible : $RW"

echo ""
echo "[7] Synthese remap telecommande"
echo "      1. reperer le device eventX du recepteur IR ([1])"
echo "      2. getevent /dev/input/eventX puis presser les touches"
echo "         pour obtenir les scancodes bruts"
echo "      3. editer le .kl correspondant ([3]/[4]/[5])"
echo "         format : key <scancode>   <KEYCODE>"
echo "      4. remount rw /system, cp, chmod 644, restorecon si SELinux"
echo "      5. reboot ou restart du service d'input pour recharger"

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
