#!/system/bin/sh
# field_mode - preparation exploitation sans ecran :
# coupe wireless + HDMI + serveurs + services listes dans la config.
# Restauration partielle possible (ON), reboot recommande sinon.

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

for B in "$(dirname "$0")" "$(dirname "$0")/core" /data/scripts /data/scripts/core; do
    if [ -f "$B/config.sh" ]; then
        . "$B/config.sh"
        break
    fi
done

svc_list()
{
    config_get SERVICES_STOP ""
}

stop_servers()
{
    FOUND=0
    for P in /mnt/media_rw/*/server/*.pid; do
        [ -f "$P" ] || continue
        PID="$(cat "$P" 2>/dev/null)"
        if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
            if kill "$PID" 2>/dev/null; then
                echo "    [ OK ] $(basename "$P") arrete (PID $PID)"
                FOUND=1
            else
                echo "    [ ERREUR ] PID $PID ($(basename "$P"))"
            fi
        fi
        rm -f "$P"
    done
    [ "$FOUND" -eq 0 ] && echo "    [ -- ] aucun serveur actif"
    return 0
}

do_off()
{
    if ! require_root; then
        return 1
    fi

    echo ""
    echo "=== FIELD MODE ON (coupe) ==="

    echo "[1] Wireless..."
    if sh "$(dirname "$0")/disable_wireless.sh"; then
        echo "    [ OK ]"
    else
        echo "    [ ERREUR ]"
        RC=1
    fi

    echo "[2] HDMI..."
    if sh "$(dirname "$0")/hdmi.sh" OFF; then
        echo "    [ OK ]"
    else
        echo "    [ ERREUR ]"
        RC=1
    fi

    echo "[3] Serveurs..."
    stop_servers

    LIST="$(svc_list)"
    echo "[4] Services${LIST:+ : $LIST}..."
    for S in $LIST; do
        stop "$S" > /dev/null 2>&1
        ST="$(getprop init.svc."$S" 2>/dev/null | tr -d '\r')"
        case "$ST" in
            stopped) echo "    [ OK ] $S -> stopped" ;;
            "")      echo "    [ -- ] $S inconnu d'init" ;;
            *)       echo "    [ WARN ] $S reste '$ST'" ;;
        esac
    done

    echo ""
    echo "[ INFO ] eth0 conserve, retour box : adb ou http (si serveur relance)"
    return 0
}

do_on()
{
    if ! require_root; then
        return 1
    fi

    echo ""
    echo "=== FIELD MODE OFF (retour) ==="

    echo "[1] HDMI..."
    if sh "$(dirname "$0")/hdmi.sh" ON; then
        echo "    [ OK ]"
    else
        echo "    [ ERREUR ]"
        RC=1
    fi

    LIST="$(svc_list)"
    echo "[2] Services..."
    for S in $LIST; do
        start "$S" > /dev/null 2>&1
        ST="$(getprop init.svc."$S" 2>/dev/null | tr -d '\r')"
        case "$ST" in
            running) echo "    [ OK ] $S -> running" ;;
            stopped) echo "    [ ERREUR ] $S toujours stopped" ;;
            *)       echo "    [ WARN ] $S etat '$ST'" ;;
        esac
    done

    echo ""
    echo "[ INFO ] wireless non reactive ici : reboot ou disable_wireless inverse"
    return 0
}

do_status()
{
    echo ""
    echo "=== FIELD MODE STATUS ==="

    echo "HDMI :"
    B="$(cat /sys/class/graphics/fb0/blank 2>/dev/null | tr -d '\r\n')"
    case "$B" in
        1) echo "  fb0 blank   : 1 (ecran coupe)" ;;
        0) echo "  fb0 blank   : 0 (ecran actif)" ;;
        "") echo "  fb0         : illisible" ;;
        *) echo "  fb0 blank   : $B" ;;
    esac

    W="$(getprop wifi_on 2>/dev/null | tr -d '\r')"
    BT="$(getprop bluetooth_on 2>/dev/null | tr -d '\r')"
    echo "Wireless :"
    echo "  wifi_on     : ${W:-?}"
    echo "  bluetooth_on: ${BT:-?}"

    LIST="$(svc_list)"
    echo "Services${LIST:+ surveilles} :"
    if [ -n "$LIST" ]; then
        for S in $LIST; do
            printf '  %-24s : %s\n' "$S" \
                "$(getprop init.svc."$S" 2>/dev/null | tr -d '\r')"
        done
    else
        NB_STOP="$(getprop 2>/dev/null | grep '^\[init.svc' | grep -c ': \[stopped\]')"
        echo "  (liste vide, init stopped : ${NB_STOP:-?})"
    fi
    echo ""
    return 0
}

main()
{
    RC=0
    case "$ACTION" in
        OFF)    do_off ;;
        ON)     do_on ;;
        STATUS) do_status ;;
        *)
            echo ""
            echo "Usage: field_mode.sh <OFF|ON|STATUS>"
            echo ""
            echo "  OFF     Coupe wireless + HDMI + serveurs + SERVICES_STOP (config)"
            echo "  ON      Retour ecran + redemarre SERVICES_STOP"
            echo "  STATUS  Etat HDMI / wireless / services surveilles"
            echo ""
            echo "Liste des services : SERVICES_STOP dans config/device.conf"
            echo "(noms init.rc, separes par espaces. Ex : bootanim)"
            echo ""
            return 1
            ;;
    esac
    return $RC
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
