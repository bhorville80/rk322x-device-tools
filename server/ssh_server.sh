#!/system/bin/sh
# ssh_server - serveur SSH (dropbear) pour acces shell distant complet,
# alternative confortable a "adb shell + su". Le binaire dropbear n'est
# PAS fourni dans le depot : le deposer sur la cle ou la box, voir STATUS.
#
# Usage: ssh_server.sh <START|STOP|STATUS>

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" "$(dirname "$0")/../scripts" /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

for B in "$(dirname "$0")/../scripts/core" "$(dirname "$0")" \
         /data/scripts /data/scripts/core; do
    if [ -f "$B/config.sh" ]; then
        . "$B/config.sh"
        break
    fi
done

PORT="$(config_get SSH_PORT 2222)"
SSH_BIN_CFG="$(config_get SSH_BIN "")"
SSH_MODE="$(config_get SSH_MODE keys)"

find_usb_dir()
{
    for d in /mnt/media_rw/*; do
        [ -f "$d/deploy.sh" ] || continue
        USB="$d"
        return 0
    done
    return 1
}

find_dropbear()
{
    for C in \
        "$SSH_BIN_CFG" \
        "$(dirname "$0")/dropbear" \
        /data/local/tmp/dropbear \
        /data/scripts/server/dropbear \
        /system/xbin/dropbear \
        /system/bin/dropbear ; do
        [ -n "$C" ] || continue
        if [ -x "$C" ]; then
            echo "$C"
            return 0
        fi
    done
    return 1
}

pid_alive()
{
    [ -n "$1" ] && kill -0 "$1" 2>/dev/null
}

do_stop()
{
    PF=""
    [ -n "$USB" ] && PF="$USB/server/ssh.pid"
    [ -z "$PF" ] && PF="/data/local/tmp/ssh.pid"

    if [ -f "$PF" ]; then
        PID="$(cat "$PF" 2>/dev/null)"
        if pid_alive "$PID"; then
            kill "$PID" 2>/dev/null && { echo "[ OK ] ssh arrete (PID $PID)"; rm -f "$PF"; return 0; }
        fi
        rm -f "$PF"
    fi

    # secours : tout dropbear residuel
    FOUND=0
    for P in $(ps 2>/dev/null | grep '[d]ropbear' | sed 's/^ *//' | cut -d' ' -f2); do
        kill "$P" 2>/dev/null && FOUND=$((FOUND+1))
    done
    if [ "$FOUND" -gt 0 ]; then
        echo "[ OK ] $FOUND processus dropbear arrete(s)"
        return 0
    fi

    echo "[ -- ] aucun serveur ssh actif"
    return 0
}

auth_flags()
{
    case "$SSH_MODE" in
        password) echo "" ;;
        any)      echo "" ;;
        *)        echo "-s" ;;
    esac
}

do_start()
{
    if ! require_root; then
        return 1
    fi

    find_usb_dir || USB=""

    BIN="$(find_dropbear)"
    if [ -z "$BIN" ]; then
        echo "[ERREUR] binaire dropbear introuvable"
        echo "         installer ainsi (depuis le PC) :"
        echo "           adb push dropbear /data/local/tmp/dropbear"
        echo "           adb shell chmod 755 /data/local/tmp/dropbear"
        echo "         ou poser 'dropbear' (arm 32 bits) dans server/ sur la cle."
        return 1
    fi
    echo "[*] binaire : $BIN"

    if [ -n "$USB" ] && netstat -tln 2>/dev/null | grep -q ":$PORT "; then
        echo "[WARN] port $PORT deja en ecoute (deja lance ? voir STATUS)"
    fi

    KEYDIR="/data/misc/dropbear"
    mkdir -p "$KEYDIR" 2>/dev/null

    LOG="$USB/log/ssh_server.log"
    [ -z "$USB" ] && LOG="/data/local/tmp/ssh_server.log"
    [ -n "$USB" ] && mkdir -p "$USB/log" "$USB/server"

    PF="$USB/server/ssh.pid"
    [ -z "$USB" ] && PF="/data/local/tmp/ssh.pid"

    FLAGS="$(auth_flags)"

    case "$SSH_MODE" in
        password)
            PW="$(config_get SSH_PASSWORD "")"
            if [ -n "$PW" ] && busybox chpasswd > /dev/null 2>&1 << INP
root:$PW
INP
            then
                echo "[ OK ] mot de passe root positionne (busybox chpasswd)"
            else
                echo "[WARN] pas de mot de passe posable automatiquement"
                echo "       connexion par mot de passe impossible sans /etc/passwd"
                echo "       -> privilégier SSH_MODE=keys"
                FLAGS="-s"
            fi
            ;;
    esac

    AK="/data/misc/dropbear/authorized_keys"
    case "$FLAGS" in
        *-s*)
            echo "[*] authentification : cles publiques ($AK)"
            if [ ! -s "$AK" ]; then
                echo "[WARN] aucune cle publique installee : personne ne pourra entrer"
                echo "       ajouter la cle du PC :"
                echo "         adb push ~/.ssh/id_ed25519.pub $AK.tmp"
                echo "         puis : mkdir -p $KEYDIR ; cat $AK.tmp >> $AK ; chmod 600 $AK"
            fi
            ;;
    esac

    echo "[*] lancement dropbear port $PORT (mode $SSH_MODE)..."
    "$BIN" -F -E -p 0.0.0.0:"$PORT" -P "$PF" $FLAGS >> "$LOG" 2>&1 &
    PID=$!
    sleep 1

    if ! pid_alive "$PID"; then
        echo "[ERREUR] dropbear n'a pas demarre (voir $(basename "$LOG"))"
        tail -n 5 "$LOG" 2>/dev/null | sed 's/^/         /'
        rm -f "$PF"
        return 1
    fi

    echo "[ OK ] SSH actif : ssh root@<ip-box> -p $PORT"
    echo "       pid $PID, log $(basename "$LOG")"
    return 0
}

do_status()
{
    echo ""
    echo "=== SSH SERVER STATUS ==="

    RC=0
    BIN="$(find_dropbear)"
    if [ -n "$BIN" ]; then
        echo "  Binaire     : $BIN"
    else
        echo "  Binaire     : absent (installer dropbear arm32, cf. START)"
        RC=1
    fi

    echo "  Port voulu  : $PORT (SSH_MODE=$SSH_MODE)"

    LISTEN=""
    netstat -tln 2>/dev/null | grep -q ":$PORT " && LISTEN="oui"
    echo "  Ecoute      : ${LISTEN:-non}"

    RUNNING="--"
    for P in $(ps 2>/dev/null | grep '[d]ropbear'); do
        RUNNING="oui ($(printf '%s' "$P" | tr -s ' ' | cut -d' ' -f2))"
        break
    done
    echo "  Processus   : $RUNNING"

    AK="/data/misc/dropbear/authorized_keys"
    if [ -s "$AK" ]; then
        NB="$(grep -c . "$AK")"
        echo "  Cles admises: $NB"
    else
        echo "  Cles admises: 0 ($AK absent/vide)"
    fi

    echo ""
    return "$RC"
}

usage()
{
    echo ""
    echo "Usage: ssh_server <START|STOP|STATUS>"
    echo ""
    echo "  START   lance dropbear (port SSH_PORT, defaut 2222)"
    echo "  STOP    arrete (aussi couvert par deploy STOP via server/ssh.pid)"
    echo "  STATUS  binaire / ecoute / cles installees"
    echo ""
    echo "Config (device.conf) : SSH_PORT, SSH_BIN, SSH_MODE=keys|password|any,"
    echo "SSH_PASSWORD (si busybox chpasswd disponible). Mode conseille : keys."
    echo ""
    return 1
}

case "$1" in
    ""|STATUS|status) do_status ;;
    START|start)      do_start ;;
    STOP|stop)        do_stop ;;
    HELP|help|-h|--help) usage ;;
    *)                usage ;;
esac
