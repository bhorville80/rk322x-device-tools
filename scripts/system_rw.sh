#!/system/bin/sh
# system_rw - bascule lecture-seule / lecture-ecriture de /system
# Necessaire pour modifier /system (keylayouts .kl, bootanimation...).
# NOTE : le remount retombe en ro au reboot (comportement voulu, plus sur).
#
# Usage: system_rw.sh <STATUS|RW|RO>

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
        . "$B/core/config.sh"
        break
    fi
done

TARGET="/system"

mount_line()
{
    grep " $TARGET " /proc/mounts 2>/dev/null | head -n 1
}

line_dev()  { printf '%s\n' "$1" | cut -d' ' -f1; }
line_type() { printf '%s\n' "$1" | cut -d' ' -f3; }
line_opts() { printf '%s\n' "$1" | cut -d' ' -f4; }

mode_of()
{
    OPTS="$(line_opts "$1")"
    case "$OPTS" in
        ro,*|*,ro,*|*,ro) echo "ro" ;;
        *)                echo "rw" ;;
    esac
}

try_remount()
{
    # $1 = rw|ro : plusieurs formes selon toolbox/toybox/busybox
    M="$1"
    L="$(mount_line)"
    DEV="$(line_dev "$L")"
    FSTYPE="$(line_type "$L")"

    mount -o "remount,$M" "$TARGET" > /dev/null 2>&1 && return 0
    mount -o "$M,remount" "$TARGET" > /dev/null 2>&1 && return 0
    [ -n "$DEV" ] && mount -o "remount,$M" -t "$FSTYPE" "$DEV" "$TARGET" > /dev/null 2>&1 && return 0
    [ -n "$DEV" ] && mount -o "remount,$M" "$DEV" "$TARGET" > /dev/null 2>&1 && return 0

    return 1
}

write_probe()
{
    F="$TARGET/.rw_probe_$$"
    if touch "$F" 2>/dev/null; then
        rm -f "$F" 2>/dev/null
        return 0
    fi
    return 1
}

do_status()
{
    echo ""
    echo "=== SYSTEM RW STATUS ($TARGET) ==="

    L="$(mount_line)"
    if [ -z "$L" ]; then
        echo "  [ ERREUR ] $TARGET absent de /proc/mounts"
        return 1
    fi

    MODE="$(mode_of "$L")"
    echo "  Device   : $(line_dev "$L")"
    echo "  Type     : $(line_type "$L")"
    echo "  Options  : $(line_opts "$L")"
    echo "  Etat     : $MODE"

    DF="$(df -h "$TARGET" 2>/dev/null | sed -n '2p')"
    [ -n "$DF" ] && echo "  Espace   : $(printf '%s' "$DF" | tr -s ' ' | cut -d' ' -f4-) "

    echo ""
    case "$MODE" in
        ro) echo "  Passer en ecriture : system_rw RW" ;;
        rw) echo "  Repasser en lecture-seule : system_rw RO (ou reboot)" ;;
    esac
    echo ""
    return 0
}

do_switch()
{
    M="$1"

    if ! require_root; then
        return 1
    fi

    L="$(mount_line)"
    if [ -z "$L" ]; then
        echo "[ERREUR] $TARGET absent de /proc/mounts"
        return 1
    fi

    CUR="$(mode_of "$L")"
    WANT="$M"
    [ "$M" = "RW" ] && WANT="rw"
    [ "$M" = "RO" ] && WANT="ro"

    echo ""
    echo "=== SYSTEM RW -> $WANT ==="

    if [ "$CUR" = "$WANT" ]; then
        echo "[ -- ] deja en $WANT"
    else
        if try_remount "$WANT"; then
            NL="$(mount_line)"
            NM="$(mode_of "$NL")"
            if [ "$NM" != "$WANT" ]; then
                echo "[ERREUR] remount accepte mais etat reste '$NM'"
                return 1
            fi
            echo "[ OK ] $TARGET remonte en $NM ($(line_dev "$NL"))"
        else
            echo "[ERREUR] remount $WANT refuse"
            echo "         verifier uid root, puis essayer manuellement :"
            echo "           mount -o remount,$WANT $(line_dev "$L") $TARGET"
            return 1
        fi
    fi

    if [ "$WANT" = "rw" ]; then
        if write_probe; then
            echo "[ OK ] ecriture verifiee (probe creee puis supprimee)"
        else
            echo "[ WARN ] mount rw mais ecriture reelle impossible (droits/fs ?)"
        fi
    fi

    echo ""
    return 0
}

usage()
{
    echo ""
    echo "Usage: system_rw <STATUS|RW|RO>"
    echo ""
    echo "  STATUS  etat du montage $TARGET (device/type/options)"
    echo "  RW      repasse $TARGET en lecture-ecriture (probe d'ecriture incluse)"
    echo "  RO      revient en lecture-seule (defaut au reboot)"
    echo ""
    echo "Cas d'usage : edition keylayout .kl (inspect_remote), bootanimation,"
    echo "fichiers systeme. Toujours revenir en RO apres modification."
    echo ""
    return 1
}

case "$1" in
    ""|STATUS|status)  do_status ;;
    RW|rw)             do_switch RW ;;
    RO|ro)             do_switch RO ;;
    HELP|help|-h|--help) usage ;;
    *)                 usage ;;
esac
