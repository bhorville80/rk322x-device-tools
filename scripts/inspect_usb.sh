#!/system/bin/sh
# inspect_usb - cle USB disponible pour adb ? (visibilite, droits, adbd)
#
# Verifications :
#   1. cle montee ? chemin/type/fs/espace libre/options ro-rw
#   2. ecriture reelle (probe dans log/)
#   3. acces pour l'utilisateur adb (uid 2000) : lecture du point de montage
#   4. adb : config USB (sys.usb.config), tcpip (service.adb.tcp.port),
#      port 5555 en ecoute
#
# Usage: inspect_usb [HELP]

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

ok() { printf '  [ OK ] %s\n' "$1"; }
ko() { printf '  [ KO ] %s\n' "$1"; }
inf() { printf '  [ -- ] %s\n' "$1"; }

port_listening()
{
    P_="$1"
    if command -v netstat > /dev/null 2>&1; then
        netstat -tln 2>/dev/null | grep -q ":$P_ " && return 0
    fi
    PH="$(printf '%04X' "$P_" 2>/dev/null)"
    [ -n "$PH" ] || return 1
    grep -qi ":$PH .* 0A " /proc/net/tcp 2>/dev/null && return 0
    grep -qi ":$PH .* 0A " /proc/net/tcp6 2>/dev/null && return 0
    return 1
}

main()
{
    echo ""
    echo "=== INSPECT USB <-> ADB ==="

    # --- 1. cle montee ---
    KEY=""
    for d in /mnt/media_rw/*; do
        [ -d "$d" ] || continue
        KEY="$d"
        break
    done

    if [ -z "$KEY" ]; then
        ko "aucune cle montee dans /mnt/media_rw/"
        inf "brancher la cle, attendre l'enumeration, relancer"
        exit 1
    fi
    ok "cle montee : $KEY"

    ML="$(grep -F " $KEY " /proc/mounts 2>/dev/null | head -n 1)"
    if [ -n "$ML" ]; then
        FST="$(printf '%s' "$ML" | awk '{print $3}')"
        OPTS="$(printf '%s' "$ML" | awk '{print $4}')"
        inf "fs=$FST opts=$(printf '%s' "$OPTS" | cut -d, -f1-4)"
    fi

    DF_="$(df -h "$KEY" 2>/dev/null | sed -n 2p | awk '{print $4}')"
    [ -n "$DF_" ] && inf "espace libre : $DF_"

    # --- 2. ecriture reelle ---
    PROBE="$KEY/.ins_usb_probe_$$"
    if touch "$PROBE" 2>/dev/null; then
        rm -f "$PROBE"
        ok "ecriture possible sur la cle"
        WR=1
    else
        ko "cle en lecture seule (ou pleine)"
        WR=0
    fi

    # --- 3. acces uid 2000 (utilisateur adb shell) ---
    MP_PERM="$(ls -ld "$KEY" 2>/dev/null | awk '{print $1}')"
    case "$MP_PERM" in
        d?????rwx*|d?????r-x*) ok "montage lisible par tous (uid 2000 OK si fs le permet)" ;;
        *) inf "perms montage : ${MP_PERM:-?} (l'acces uid 2000 depend du firmware)" ;;
    esac
    if command -v su > /dev/null 2>&1; then
        inf "adb shell sans root : tester 'ls /mnt/media_rw/' ; si permission denied -> passer par su"
    fi

    # --- 4. etat adb ---
    USB_CFG="$(getprop sys.usb.config 2>/dev/null)"
    case "$USB_CFG" in
        *adb*) ok "adbd USB actif dans sys.usb.config ($USB_CFG)" ;;
        "")    inf "sys.usb.config illisible" ;;
        *)     inf "sys.usb.config = $USB_CFG (sans adb)" ;;
    esac

    TCP_PORT="$(getprop service.adb.tcp.port 2>/dev/null)"
    PERS="$(getprop persist.adb.tcp.port 2>/dev/null)"
    if port_listening 5555; then
        ok "adbd en ecoute reseau sur 5555"
    else
        inf "port 5555 absent (adb reseau inactif ; 'adb tcpip 5555' depuis le PC)"
    fi
    [ -n "$PERS" ] && inf "persist.adb.tcp.port = $PERS"
    [ -n "$TCP_PORT" ] && inf "service.adb.tcp.port = $TCP_PORT"

    # --- synthese ---
    echo ""
    echo "--- SYNTHESE ---"
    echo "  KEY_VISIBLE   : oui ($KEY, ecriture=$((WR ? 1 : 0)))"
    echo "  ADB_USB       : $(case "$USB_CFG" in *adb*) echo oui ;; *) echo non/inconnu ;; esac)"
    echo "  ADB_RESEAU    : $(port_listening 5555 && echo oui || echo non)"
    echo ""
    echo "Recette croatee : PC 'adb devices' doit lister la box ;"
    echo "puis 'adb shell ls /mnt/media_rw/' valide l'acces cote utilisateur."
}

case "$1" in
    HELP|-h|--help)
        sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
        ;;
    *)
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
        ;;
esac
