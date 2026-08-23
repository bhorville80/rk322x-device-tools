#!/system/bin/sh
# front_digit - contenu personnalise de l'afficheur 4 digits (FD655).
#
# Le driver expose /dev/fd655_dev ; le daemon usine (FD655_Demo) y dessine
# l'horloge. Ce tool arrete le daemon et ecrit ses propres trames de
# segments 7-segments. Le format exact de trame depend du firmware :
#
#   raw   4 octets segments, sans en-tete          (le plus courant)
#   hdr   0xC0 + 4 octets segments                 (style TM1637)
#   full  0xC0 + 4 segments + 1 octet luminosite
#
#   front_digit STATUS              node, format configure, daemons actifs
#   front_digit PROBE               teste les 3 formats ("8888" attendu),
#                                   memorise celui qui marche dans device.conf
#   front_digit SHOW "12.34"        affiche un texte 7-seg (0-9 - . espace
#                                   et lettres H E L P A b C d E F U t o n r S I)
#   front_digit RAW 3f 06 5b 4f     ecrit les octets segments bruts
#   front_digit CLOCK               horloge HH.MM (rafraichie chaque minute)
#   front_digit ROTATE [s] [items]  rotation toutes les s secondes (defaut 5)
#                                   items : TIME IP RAM UP (defaut TIME IP)
#   front_digit STOP                arrete nos daemons (+ FD655_Demo si actif)
#
# NOTE : la box demarre souvent a l'heure 1970 -> lancer set_time ou
# sync_usb pour une horloge juste. Config : FD_FORMAT, FD_ROTATE_SEC,
# FD_ROTATE_ITEMS, BOOT_FRONT_CLOCK (cf. boot).

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

for B in "$(dirname "$0")" "$(dirname "$0")/../scripts" /data/scripts; do
    if [ -f "$B/core/config.sh" ]; then
        . "$B/core/config.sh"
        break
    fi
done

command -v config_get >/dev/null 2>&1 || config_get() { echo "$2"; }
command -v is_root >/dev/null 2>&1 || is_root() { case "$(id -u 2>/dev/null)" in 0) return 0 ;; esac; case "$(id 2>/dev/null)" in "uid=0("*) return 0 ;; esac; return 1; }

DEV="/dev/fd655_dev"
PIDFILE="/data/local/tmp/front_digit.pid"
CONF="/data/scripts/config/device.conf"

# ---- police 7 segments (bits gfedcba ; +0x80 = point decimal) ----

seg_for_char()
{
    case "$1" in
        0) echo 3F ;; 1) echo 06 ;; 2) echo 5B ;; 3) echo 4F ;;
        4) echo 66 ;; 5) echo 6D ;; 6) echo 7D ;; 7) echo 07 ;;
        8) echo 7F ;; 9) echo 6F ;;
        -) echo 40 ;; " ") echo 00 ;;
        A) echo 77 ;; b) echo 7C ;; C) echo 39 ;; d) echo 5E ;;
        E) echo 79 ;; F) echo 71 ;; G) echo 3D ;; H) echo 76 ;;
        I) echo 06 ;; J) echo 1E ;; L) echo 38 ;; n) echo 54 ;;
        o) echo 5C ;; P) echo 73 ;; r) echo 50 ;; S) echo 6D ;;
        t) echo 78 ;; U) echo 3E ;; Y) echo 6E ;;
        *) echo 00 ;;
    esac
}

hex_or()
{
    # OU logique de deux octets hexadecimaux (point decimal sur segment)
    printf '%02X' $(( (16#$1) | (16#$2) ))
}

render_text()
{
    # $1 texte <=4 chars visibles ('.' colle au char precedent)
    # sortie : "seg1 seg2 seg3 seg4" aligne a droite
    SEGS="" ; DOT=0
    TXT="$(printf '%s' "$1" | tr -d '\r\n')"
    LEN="${#TXT}" 2>/dev/null || LEN="$(printf '%s' "$TXT" | wc -c | tr -dc '0-9')"

    CHARS=""
    I=1
    while [ "$I" -le "$LEN" ]; do
        CH="$(printf '%s' "$TXT" | cut -c"$I")"
        case "$CH" in
            .)
                # point decimal : colle au caractere precedent
                case "$CHARS" in
                    *"|") CHARS="${CHARS%|*}*|" ;;
                esac
                ;;
            *) CHARS="$CHARS$CH|" ;;
        esac
        I=$((I+1))
    done

    OUT=""
    TMP="$CHARS"
    while [ -n "$TMP" ]; do
        T="${TMP%%|*}"
        case "$TMP" in
            *|*) TMP="${TMP#*|}" ;;
            *)   TMP="" ;;
        esac
        case "$T" in
            *\*) B="${T%\*}"; H="$(hex_or "$(seg_for_char "${B:- }")" "80")" ;;
            "")  H="00" ;;
            *)   H="$(seg_for_char "$T")" ;;
        esac
        OUT="$OUT $H"
    done

    NB=0
    for H in $OUT; do NB=$((NB+1)); done
    while [ "$NB" -lt 4 ]; do
        OUT=" 00$OUT"
        NB=$((NB+1))
    done

    # garde les 4 derniers champs (tronque a gauche si trop long)
    printf '%s\n' "$OUT" | while read -r A B C D E REST; do
        if [ -n "${E:-}" ]; then
            printf '%s %s %s %s\n' "${B:-00}" "${C:-00}" "${D:-00}" "${E:-00}"
        else
            printf '%s %s %s %s\n' "${A:-00}" "${B:-00}" "${C:-00}" "${D:-00}"
        fi
    done
}

hex_to_octal_esc()
{
    # busybox printf : support garanti de %03o (builtin mksh incertain)
    DEC=$((16#$1))
    if command -v busybox > /dev/null 2>&1; then
        busybox printf '\\%03o' "$DEC"
    else
        printf '\\%03o' "$DEC"
    fi
}

write_frame()
{
    # $1 format, $2..$5 segments hexadecimaux (2 digits chacun)
    FMT="$1"; shift
    S1="${1:-00}" ; S2="${2:-00}" ; S3="${3:-00}" ; S4="${4:-00}"
    case "$FMT" in
        hdr)  SEQ="$(hex_to_octal_esc C0)" ;;
        full) SEQ="$(hex_to_octal_esc C0)" ;;
        *)    SEQ="" ;;
    esac
    SEQ="$SEQ$(hex_to_octal_esc "$S1")$(hex_to_octal_esc "$S2")$(hex_to_octal_esc "$S3")$(hex_to_octal_esc "$S4")"
    case "$FMT" in
        full) SEQ="$SEQ$(hex_to_octal_esc 8F)" ;;   # luminosite max
    esac
    printf "$SEQ" > "$DEV" 2>/dev/null
}

demo_running()
{
    ps 2>/dev/null | grep '[F]D655_Demo' > /dev/null 2>&1
}

stop_demo()
{
    demo_running || return 0
    for PID in $(ps 2>/dev/null | grep '[F]D655_Demo' | sed 's/^ *//' | cut -d' ' -f2); do
        kill "$PID" 2>/dev/null
    done
    echo "[ OK ] FD655_Demo arrete (il reviendrait au reboot)"
}

our_daemon_pids()
{
    [ -f "$PIDFILE" ] || return 0
    for PID in $(cat "$PIDFILE" 2>/dev/null); do
        kill -0 "$PID" 2>/dev/null && echo "$PID"
    done
}

do_stop()
{
    N=0
    for PID in $(our_daemon_pids); do
        kill "$PID" 2>/dev/null && N=$((N+1))
    done
    rm -f "$PIDFILE" 2>/dev/null
    if [ "$N" -gt 0 ]; then
        echo "[ OK ] $N daemon(s) front_digit arrete(s)"
    else
        echo "[ -- ] aucun daemon front_digit actif"
    fi
    stop_demo
    return 0
}

item_value()
{
    # $1 item -> texte affichable (<=4 chars)
    case "$1" in
        TIME)
            date '+%H.%M'
            ;;
        IP)
            IPOK=""
            for IF_ in eth0 wlan0; do
                IP_="$(ifconfig "$IF_" 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p')"
                [ -n "$IP_" ] && { IPOK="$IP_"; break; }
            done
            [ -n "$IPOK" ] || { echo "--"; return; }
            echo "${IPOK##*.}"
            ;;
        RAM)
            MA="$(sed -n 's/^MemAvailable: *\([0-9]*\) kB/\1/p' /proc/meminfo 2>/dev/null | head -n 1)"
            case "$MA" in
                ''|*[!0-9]*) echo "--" ;;
                *) echo $((MA / 1024)) ;;
            esac
            ;;
        UP)
            UP_S="$(cut -d' ' -f1 /proc/uptime 2>/dev/null | cut -d. -f1)"
            case "$UP_S" in
                ''|*[!0-9]*) echo "--" ;;
                *) echo "$((UP_S / 60))" ;;
            esac
            ;;
    esac
}

save_format()
{
    F="$1"
    if [ -f "$CONF" ] && grep -q '^FD_FORMAT=' "$CONF" 2>/dev/null; then
        sed "s/^FD_FORMAT=.*/FD_FORMAT=$F/" "$CONF" > "${CONF}.tmp" 2>/dev/null \
            && mv -f "${CONF}.tmp" "$CONF"
    elif [ -f "$CONF" ]; then
        cp -f "$CONF" "${CONF}.tmp" 2>/dev/null
        echo "FD_FORMAT=$F" >> "${CONF}.tmp" 2>/dev/null \
            && mv -f "${CONF}.tmp" "$CONF"
    fi
}

require_dev()
{
    [ -e "$DEV" ] || { echo "[ERREUR] $DEV absent sur cette box"; return 1; }
    if ! is_root; then
        echo "[ERREUR] privileges root requis : su -c \"sh $0 $ACTION\""
        return 1
    fi
    return 0
}

do_status()
{
    echo ""
    echo "=== FRONT DIGIT STATUS ==="
    echo "  Node driver   : $( [ -e "$DEV" ] && echo "$DEV" || echo 'absent (/dev/fd655_dev)')"
    echo "  Daemon usine  : $(demo_running && echo 'FD655_Demo actif (dessine l horloge)' || echo 'inactif')"
    OURS=""
    for PID in $(our_daemon_pids); do OURS="$OURS $PID"; done
    echo "  Nos daemons   : ${OURS:-aucun}"
    echo "  Format conf   : $(config_get FD_FORMAT "")"

    ROT=""
    for PID in $(our_daemon_pids); do
        ARGS="$(tr '\0' ' ' < "/proc/$PID/cmdline" 2>/dev/null)"
        ROT="$ROT [$ARGS]"
    done
    [ -n "$ROT" ] && printf '  Rotation      :%s\n' "$ROT"
    echo ""
    return 0
}

probe_one()
{
    # $1 format : ecrit 8888 puis efface ; retourne 0
    write_frame "$1" 7F 7F 7F 7F
    sleep 2
    write_frame "$1" 00 00 00 00
    sleep 1
}

do_probe()
{
    require_dev ACTION=PROBE || return 1
    echo ""
    echo "=== FRONT DIGIT PROBE ==="
    echo "Regarde l'afficheur : on cherche celui qui affiche 8888 pendant 2 s."
    echo ""

    for F in raw hdr full; do
        echo "[*] format '$F'..."
        probe_one "$F"
        printf '    quelque chose s est affiche ? (o/N) > '
        read -r ANS
        case "$ANS" in
            o|O|y|Y|oui|OUI)
                save_format "$F"
                echo "[ OK ] format '$F' retenu dans $CONF"
                echo "       test rendu : sh $0 SHOW \"12.34\""
                return 0
                ;;
        esac
    done
    echo "[ ERREUR ] aucun format n'a produit d'affichage :"
    echo "           driver non accessible en ecriture brute sur ce firmware."
    echo "           reste possible : front_led DEMO ON (horloge usine)."
    return 1
}

fmt_of()
{
    F="$(config_get FD_FORMAT "")"
    [ -n "$F" ] && { printf '%s' "$F"; return 0; }
    printf '%s' "raw"
}

check_len()
{
    # refuse plus de 4 digits visibles
    VISIBLES="$(printf '%s' "$1" | tr -d '.')"
    L="${#VISIBLES}" 2>/dev/null || L="$(printf '%s' "$VISIBLES" | wc -c | tr -dc '0-9')"
    [ "$L" -le 4 ]
}

do_show()
{
    require_dev ACTION=SHOW || return 1
    TXT="${1:?usage: front_digit SHOW \"12.34\"}"

    check_len "$TXT" || {
        echo "[ERREUR] maximum 4 caracteres affichables ('$TXT')"
        return 1
    }

    FRM="$(fmt_of)"
    SEGLINE="$(render_text "$TXT")"
    [ -n "$SEGLINE" ] || { echo "[ERREUR] rien a afficher"; return 1; }

    stop_demo
    our_daemons_conflict

    set -- $SEGLINE
    write_frame "$FRM" "${1:-00}" "${2:-00}" "${3:-00}" "${4:-00}"
    echo "[ OK ] '$TXT' envoye (format $FRM)"
    echo "       rien a l'ecran ? lancer PROBE pour identifier le bon format"
    return 0
}

our_daemons_conflict()
{
    PIDS="$(our_daemon_pids)"
    [ -n "$PIDS" ] || return 0
    for PID in $PIDS; do kill "$PID" 2>/dev/null; done
    rm -f "$PIDFILE"
    echo "[WARN] daemon front_digit preexistant arrete (rotation/horloge)"
}

do_raw()
{
    require_dev ACTION=RAW || return 1
    B1="${1:-00}" ; B2="${2:-00}" ; B3="${3:-00}" ; B4="${4:-00}"
    stop_demo
    our_daemons_conflict
    write_frame "$(fmt_of)" "$B1" "$B2" "$B3" "$B4"
    echo "[ OK ] trame envoyee ($B1 $B2 $B3 $B4)"
    return 0
}

daemon_loop()
{
    # $1 intervalle, $2... items
    SEC="$1" ; shift
    ITEMS="$*"
    [ -n "$ITEMS" ] || ITEMS="TIME IP"

    (
        while true; do
            for IT in $ITEMS; do
                TXT="$(item_value "$IT")"
                SEGLINE="$(render_text "$TXT" 2>/dev/null)"
                [ -z "$SEGLINE" ] && continue
                set -- $SEGLINE
                write_frame "$(fmt_of)" "${1:-00}" "${2:-00}" "${3:-00}" "${4:-00}" 2>/dev/null
                sleep "$SEC"
            done
        done
    ) >/dev/null 2>&1 &
    DPID=$!
    echo "$DPID" > "$PIDFILE"
    printf '%s' "$DPID"
}

do_clock()
{
    require_dev ACTION=CLOCK || return 1
    stop_demo
    our_daemons_conflict
    PID="$(daemon_loop 30 "TIME")"
    echo "[ OK ] horloge frontale active (PID $PID, maj/min)"
    echo "       heure box fausse ? -> set_time ou sync_usb d'abord"
    return 0
}

do_rotate()
{
    require_dev ACTION=ROTATE || return 1
    SEC="${1:-$(config_get FD_ROTATE_SEC 5)}"
    case "$SEC" in ''|*[!0-9]*) SEC=5 ;; esac
    [ "$SEC" -ge 2 ] || SEC=2
    ITEMS="${2:-$(config_get FD_ROTATE_ITEMS "")}"
    [ -n "$ITEMS" ] || ITEMS="TIME IP"

    stop_demo
    our_daemons_conflict
    PID="$(daemon_loop "$SEC" $ITEMS)"
    echo "[ OK ] rotation active : items [$ITEMS] toutes les ${SEC}s (PID $PID)"
    return 0
}

usage()
{
    echo ""
    echo "Usage: front_digit <STATUS|PROBE|SHOW \"txt\"|RAW h h h h|CLOCK|ROTATE [s] [items]|STOP>"
    echo ""
    echo "  PROBE             identifie le format de trame qui marche (une fois)"
    echo "  SHOW \"12.34\"      affiche un texte 7-seg (0-9 - . lettres simples)"
    echo "  RAW 3f 06 5b 4f   octets segments bruts"
    echo "  CLOCK             horloge HH.MM (maj chaque minute)"
    echo "  ROTATE [s] [i]    rotation (defaut 5 s, items: TIME IP RAM UP)"
    echo "  STOP              arrete nos daemons + le daemon usine"
    echo ""
    echo "Config : FD_FORMAT (raw|hdr|full), FD_ROTATE_SEC, FD_ROTATE_ITEMS,"
    echo "BOOT_FRONT_CLOCK=1 pour l'horloge auto au reboot (via boot INSTALL)."
    echo ""
    return 0
}

case "$1" in
    ""|STATUS|status)     do_status ;;
    PROBE|probe)          do_probe ;;
    SHOW|show)            shift; do_show "$1" ;;
    RAW|raw)              shift; do_raw "$@" ;;
    CLOCK|clock)          do_clock ;;
    ROTATE|rotate)        shift; do_rotate "$@" ;;
    STOP|stop)            do_stop ;;
    HELP|help|-h|--help)  usage ;;
    *)                    usage ;;
esac
