#!/system/bin/sh
# front_led - personnalisation de l'afficheur frontal :
# leds sysfs (green/red), triggers, clignotement,
# et arret du daemon FD655_Demo (horloge 7 segments).
#
# Usage: front_led.sh <STATUS|LED|TRIGGER|BLINK|ON|OFF|DEMO>

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" "$(dirname "$0")/.." /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

LED_BASE="/sys/class/leds"

known_led()
{
    [ -d "$LED_BASE/$1/brightness" ] || [ -f "$LED_BASE/$1/brightness" ]
}

led_max()
{
    M="$(cat "$LED_BASE/$1/max_brightness" 2>/dev/null | tr -dc '0-9')"
    echo "${M:-255}"
}

active_trigger()
{
    sed -n 's/.*\[\([^]]*\)\].*/\1/p' "$LED_BASE/$1/trigger" 2>/dev/null
}

has_trigger()
{
    grep -qw "$2" "$LED_BASE/$1/trigger" 2>/dev/null
}

set_bright()
{
    L="$1"
    V="$2"
    MAX="$(led_max "$L")"
    case "$V" in ''|*[!0-9]*) echo "[ERREUR] valeur '$V' non numerique"; return 1 ;; esac
    if [ "$V" -gt "$MAX" ]; then V="$MAX"; fi
    echo "$V" > "$LED_BASE/$L/brightness" 2>/dev/null || { echo "[ERREUR] ecriture brightness $L"; return 1; }
    GOT="$(cat "$LED_BASE/$L/brightness" 2>/dev/null | tr -dc '0-9')"
    echo "[ OK ] $L brightness = ${GOT:-?}/$MAX"
}

fd655_info()
{
    FOUND=0
    for P in /dev/fd6*; do
        [ -e "$P" ] || continue
        PERM="$(ls -l "$P" 2>/dev/null | sed 's/ .*//')"
        echo "  Noeud       : $P ($PERM)"
        FOUND=1
    done
    [ "$FOUND" -eq 0 ] && echo "  Noeud       : aucun (/dev/fd6*)"
}

demo_pids()
{
    ps 2>/dev/null | grep -i '[F]D655' | tr -s ' ' | cut -d' ' -f2
}

do_status()
{
    echo ""
    echo "=== AFFICHEUR FRONTAL ==="

    echo ""
    echo "--- Leds sysfs ---"
    ANY=0
    for D in "$LED_BASE"/*; do
        [ -d "$D" ] || continue
        N="$(basename "$D")"
        case "$N" in *green*|*red*|*blue*|*led*) ;;
            *) continue ;;
        esac
        ANY=1
        B="$(cat "$D/brightness" 2>/dev/null)"
        M="$(cat "$D/max_brightness" 2>/dev/null)"
        T="$(active_trigger "$N")"
        printf '  %-10s bright=%-4s max=%-4s trigger=[%s]\n' "$N" "${B:-?}" "${M:-?}" "${T:-none}"
    done
    [ "$ANY" -eq 0 ] && echo "  aucune led verte/rouge exposee"

    echo ""
    echo "--- Driver FD655 ---"
    fd655_info
    DP="$(demo_pids | head -n 1)"
    if [ -n "$DP" ]; then
        echo "  Daemon      : FD655_Demo actif (PID $(printf '%s' "$DP" | head -n 1))"
        echo "                -> pilote l'afficheur (horloge) et peut ecraser vos reglages"
        echo "                -> arreter : front_led DEMO STOP (reboot le relance)"
    else
        echo "  Daemon      : FD655_Demo absent/arrete"
    fi

    echo ""
    echo "Commandes : LED <nom> <0-max> | TRIGGER <nom> <t> | BLINK <nom> <on> <off>"
    echo "            ON | OFF | DEMO STOP"
    echo ""
    return 0
}

do_led()
{
    N="$1"
    V="$2"
    known_led "$N" || { echo "[ERREUR] led '$N' inconnue (voir STATUS)"; return 1; }
    set_bright "$N" "$V"
}

do_trigger()
{
    N="$1"
    T="$2"
    known_led "$N" || { echo "[ERREUR] led '$N' inconnue"; return 1; }
    has_trigger "$N" "$T" || { echo "[ERREUR] trigger '$T' indisponible sur $N"; return 1; }
    echo "$T" > "$LED_BASE/$N/trigger" 2>/dev/null && \
        echo "[ OK ] $N trigger = $T" || echo "[ERREUR] ecriture trigger $N"
}

do_blink()
{
    N="$1"
    ON="$2"
    OFF="$3"
    case "$ON$OFF" in ''|*[!0-9]*) echo "[ERREUR] durees non numeriques"; return 1 ;; esac
    do_trigger "$N" "timer" || return 1
    echo "$ON"  > "$LED_BASE/$N/delay_on"  2>/dev/null
    echo "$OFF" > "$LED_BASE/$N/delay_off" 2>/dev/null
    echo "[ OK ] $N blink ${ON}ms/${OFF}ms"
}

each_known_led()
{
    CMD="$1"
    for N in green:red blue:white led; do
        L="${N%%:*}"
        known_led "$L" && eval "$CMD $L"
    done
}

do_all()
{
    V="$1"
    for L in $(ls -1 "$LED_BASE" 2>/dev/null); do
        case "$L" in *green*|*red*|*blue*|*led*) set_bright "$L" "$V" ;; esac
    done
}

do_demo_on()
{
    BIN=""
    for C in /system/bin/FD655_Demo /system/xbin/FD655_Demo \
             "$(dirname "$0")/FD655_Demo" ; do
        [ -x "$C" ] && { BIN="$C"; break; }
    done
    if [ -z "$BIN" ]; then
        echo "[ERREUR] binaire FD655_Demo introuvable (reboot pour relancer l'horloge)"
        return 1
    fi

    for PID in $(demo_pids); do
        echo "[ -- ] deja actif (PID $PID)"
        return 0
    done

    "$BIN" > /dev/null 2>&1 &
    sleep 1
    NEW="$(demo_pids | head -n 1)"
    if [ -n "$NEW" ]; then
        echo "[ OK ] horloge FD655 relancee (PID $NEW)"
        return 0
    fi
    echo "[ ERREUR ] FD655_Demo ne reste pas actif"
    return 1
}

do_demo_stop()
{
    KILLED=0
    for PID in $(demo_pids); do
        if kill "$PID" 2>/dev/null; then
            echo "[ OK ] FD655_Demo arrete (PID $PID)"
            KILLED=$((KILLED+1))
        fi
    done
    [ "$KILLED" -eq 0 ] && echo "[ -- ] aucun daemon FD655 actif"

    SVC="$(getprop 2>/dev/null | sed -n 's/\[init\.svc\.\([^]]*\)\]: \[running\]/\1/p' \
        | grep -iE 'fd65|vfd|front|display_demo' | head -n 1)"
    if [ -n "$SVC" ]; then
        echo "[ INFO ] service init detecte : '$SVC'"
        echo "         pour un arret persistant :"
        echo "           SERVICES_CUT=$SVC (config/device.conf) puis cut_services CUT"
        echo "           ou SERVICES_STOP=$SVC pris en charge par field_mode OFF"
    else
        echo "[ INFO ] non persistant : un reboot relance le daemon"
    fi
    return 0
}

usage()
{
    echo ""
    echo "Usage: front_led <STATUS|LED|TRIGGER|BLINK|ON|OFF|DEMO>"
    echo ""
    echo "  STATUS              etat leds + driver FD655 + daemon horloge"
    echo "  LED <nom> <val>     luminosite (front_led LED green 128)"
    echo "  TRIGGER <nom> <t>   none|heartbeat|timer|default-on..."
    echo "  BLINK <nom> <on> <off>  clignotement ms (timer)"
    echo "  ON | OFF            toutes les leds au max / a zero"
    echo "  DEMO STOP           arrete l'horloge FD655_Demo (reboot la relance)"
    echo "  DEMO ON             relance l'horloge FD655_Demo"
    echo ""
    return 1
}

case "$1" in
    ""|STATUS|status) do_status ;;
    LED|led)          shift; do_led "$@" ;;
    TRIGGER|trigger)  shift; do_trigger "$@" ;;
    BLINK|blink)      shift; do_blink "$@" ;;
    ON|on)            do_all 255 ;;
    OFF|off)          do_all 0 ;;
    DEMO|demo)        shift; case "${1:-}" in
                          STOP|stop) do_demo_stop ;;
                          ON|on|START|start) do_demo_on ;;
                          *) usage ;;
                      esac ;;
    HELP|help|-h|--help) usage ;;
    *)                usage ;;
esac
