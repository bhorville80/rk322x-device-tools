#!/system/bin/sh
# reboot - redemarrage controle de la box.
#
#   reboot                 redemarre immediatement
#   reboot <secondes>      programme un reboot dans N secondes (annulable)
#   reboot CANCEL          annule le reboot programme
#   reboot STATUS          un reboot programme est-il en attente ?
#   reboot RECOVERY        redemarre en mode recovery
#   reboot BOOTLOADER      redemarre en mode bootloader (fastboot)
#   reboot HELP            cette aide
#
# NOTE : le processus meurt avec la box -> la trace ecrite avant l'action
# est le seul temoin (log/exec/reboot_*.log si une cle est montee).

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

command -v is_root >/dev/null 2>&1 || is_root() { case "$(id -u 2>/dev/null)" in 0) return 0 ;; esac; case "$(id 2>/dev/null)" in "uid=0("*) return 0 ;; esac; return 1; }

PIDFILE="/data/local/tmp/reboot_soon.pid"

is_num()
{
    case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac
}

trace()
{
    # trace legere avant une action qui tue le shell (pas de runlog_end apres)
    for d in /mnt/media_rw/*; do
        [ -f "$d/deploy.sh" ] || continue
        D="$d/log/exec"
        mkdir -p "$D" 2>/dev/null
        F="$D/${SCRIPT_ID}_$(date '+%Y%m%d-%H%M%S').log"
        {
            echo "=== RK322X EXEC ==="
            echo "script : $SCRIPT_ID"
            echo "debut  : $(date '+%Y-%m-%d %H:%M:%S')"
            echo "action : $*"
            echo "---"
        } > "$F" 2>/dev/null
        ls -1d "$D"/${SCRIPT_ID}_*.log 2>/dev/null | sort | tail -n +6 | \
        while read -r OLD; do rm -f "$OLD" 2>/dev/null; done
        break
    done
    return 0
}

power_exec()
{
    # $1 : ""|recovery|bootloader
    sync
    case "$1" in
        "")
            if command -v reboot > /dev/null 2>&1; then
                reboot
            else
                setprop sys.powerctl reboot
            fi
            ;;
        *)
            if command -v reboot > /dev/null 2>&1; then
                reboot "$1"
            else
                setprop sys.powerctl "reboot,$1"
            fi
            ;;
    esac
    # certains firmwares mettent du temps -> petit filet
    sleep 5
    power_exec_fallback "$1"
}

power_exec_fallback()
{
    case "$1" in
        "")          setprop sys.powerctl reboot ;;
        recovery)    setprop sys.powerctl reboot,recovery ;;
        bootloader)  setprop sys.powerctl reboot,bootloader ;;
    esac
    sleep 10
}

pid_alive()
{
    [ -n "$1" ] && kill -0 "$1" 2>/dev/null
}

pending_pid()
{
    [ -f "$PIDFILE" ] || return 1
    P="$(cat "$PIDFILE" 2>/dev/null)"
    pid_alive "$P" || { rm -f "$PIDFILE" 2>/dev/null; return 1; }
    printf '%s' "$P"
}

do_cancel()
{
    P="$(pending_pid)"
    if [ -n "$P" ]; then
        kill "$P" 2>/dev/null && { rm -f "$PIDFILE"; echo "[ OK ] reboot programme annule (PID $P)"; return 0; }
        echo "[ ERREUR ] impossible d'annuler (PID $P)"
        return 1
    fi
    echo "[ -- ] aucun reboot programme"
    return 0
}

do_status()
{
    echo ""
    echo "=== RK322X REBOOT STATUS ==="
    P="$(pending_pid)"
    if [ -n "$P" ]; then
        echo "  Reboot programme : OUI (PID $P) -> annuler : reboot CANCEL"
    else
        echo "  Reboot programme : non"
    fi
    echo ""
    return 0
}

do_schedule()
{
    N="$1"
    if ! is_root; then
        echo "[ERREUR] privileges root requis : su -c \"sh $0 $N\""
        return 1
    fi

    P="$(pending_pid)"
    [ -n "$P" ] && { echo "[WARN] un reboot etait deja programme (remplace)"; kill "$P" 2>/dev/null; rm -f "$PIDFILE"; }

    (
        sleep "$N"
        trace "reboot programme ($N s)"
        rm -f "$PIDFILE" 2>/dev/null
        power_exec ""
    ) &
    BP=$!
    echo "$BP" > "$PIDFILE"
    echo "[ OK ] reboot programme dans ${N}s (PID $BP)"
    echo "       annuler : reboot CANCEL"
    return 0
}

do_now()
{
    MODE="$1"
    if ! is_root; then
        echo "[ERREUR] privileges root requis : su -c \"sh $0 $MODE\""
        return 1
    fi
    case "$MODE" in
        "")         LBL="redemarrage" ;;
        recovery)   LBL="redemarrage en recovery" ;;
        bootloader) LBL="redemarrage en bootloader (fastboot)" ;;
    esac

    P="$(pending_pid)"
    [ -n "$P" ] && { kill "$P" 2>/dev/null; rm -f "$PIDFILE"; }

    echo "[*] $LBL..."
    trace "$LBL"
    exec_sh_power "$MODE"
}

# wrapper pour rester testable : power_exec en sous-shell volontairement
# non retourne (la box s'eteint de toute facon)
exec_sh_power()
{
    power_exec "$1" > /dev/null 2>&1 &
    BP=$!
    echo "[ OK ] commande envoyee (PID $BP)"
    echo "       la box coupe dans les secondes qui viennent"
    return 0
}

usage()
{
    echo ""
    echo "Usage: reboot [<secondes>|CANCEL|STATUS|RECOVERY|BOOTLOADER|HELP]"
    echo ""
    echo "  reboot             redemarre immediatement"
    echo "  reboot 30          programme un reboot dans 30 secondes (CANCEL pour annuler)"
    echo "  reboot CANCEL      annule le reboot programme"
    echo "  reboot STATUS      etat du reboot programme"
    echo "  reboot RECOVERY    redemarre en recovery"
    echo "  reboot BOOTLOADER  redemarre en bootloader (fastboot)"
    echo ""
    return 0
}

case "$1" in
    ""|HELP|help|-h|--help)
        [ -n "$1" ] || { do_now ""; exit $?; }
        usage
        ;;
    STATUS|status)   do_status ;;
    CANCEL|cancel)   do_cancel ;;
    RECOVERY|recovery)     do_now recovery ;;
    BOOTLOADER|bootloader|BOOT|boot) do_now bootloader ;;
    *)
        if is_num "$1"; then
            case "$1" in
                0) do_now "" ;;
                *) do_schedule "$1" ;;
            esac
        else
            usage
            exit 1
        fi
        ;;
esac
