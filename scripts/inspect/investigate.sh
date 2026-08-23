#!/system/bin/sh
# investigate - enquetes techniques ciblees sur la box.
#
# Complement des inspect_* : ici on cherche QUI ecrit quoi et OU,
# pour ouvrir la customisation quand le protocole est inconnu.
#
#   investigate               aide
#   investigate DISPLAY       afficheur frontal FD655 :
#                               - processus tenant /dev/fd655_dev ouvert
#                                 (scan /proc/*/fd)
#                               - lecture brute du node (etat segments)
#                               - capture strace du daemon usine si present
#                               - traces kernel/init/logcat, binaire, sysfs
#   investigate REMOTE        telecommande IR : devices/layouts, modules et
#                             parametres noyau IR, snapshot getevent -l
#   investigate ALL           les deux, rapport complet sauvegarde sur cle
#
# Sortie detaillee : log/investigate_<ts>.txt (+ pieces dans log/investigate/)

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" "$(dirname "$0")/.." /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

DEV_FD="/dev/fd655_dev"

key_dir()
{
    for d in /mnt/media_rw/*; do
        [ -f "$d/deploy.sh" ] && { printf '%s' "$d"; return 0; }
    done
    return 1
}

sec()  { echo ""; echo "--- [$1] $2 ---"; }
row()  { printf '  %-26s %s\n' "$1" "$2"; }

procs_holding()
{
    TARGET="$1"
    for PD in /proc/[0-9]*; do
        [ -d "$PD/fd" ] || continue
        PID="${PD#/proc/}"
        for FD_ in "$PD"/fd/*; do
            LINK="$(readlink "$FD_" 2>/dev/null)"
            if [ "$LINK" = "$TARGET" ]; then
                CMD="$(tr '\0' ' ' < "$PD/cmdline" 2>/dev/null | cut -c1-60)"
                printf '%s %s [%s]\n' "$PID" "${FD_##*/}" "${CMD:-?}"
                break
            fi
        done
    done
}

demo_pid()
{
    for PID in $(ps 2>/dev/null | grep '[F]D655_Demo' | sed 's/^ *//' | cut -d' ' -f2); do
        printf '%s' "$PID"
        return 0
    done
    return 1
}

out_dir()
{
    KEY_="$(key_dir)"
    if [ -n "$KEY_" ]; then
        mkdir -p "$KEY_/log/investigate" 2>/dev/null
        printf '%s/log/investigate' "$KEY_"
    else
        mkdir -p /data/local/tmp/investigate 2>/dev/null
        printf '%s' "/data/local/tmp/investigate"
    fi
}

topic_display()
{
    echo ""
    echo "=== INVESTIGATE DISPLAY (FD655) ==="

    sec 1 "Node"
    if [ ! -e "$DEV_FD" ]; then
        row node "absent ($DEV_FD)"
        row piste "ls -1 /dev | grep -iE 'fd6|vfd|led' pour le nom reel"
    else
        row node "$(ls -l "$DEV_FD" 2>/dev/null | tr -s ' ' | cut -d' ' -f1,3,4,5,10)"
    fi

    sec 2 "Processus tenant le node ouvert"
    if ! command -v readlink > /dev/null 2>&1; then
        row outil "readlink absent"
    else
        NB_="$(procs_holding "$DEV_FD" 2>/dev/null | grep -c . )"
        if [ "${NB_:-0}" -eq 0 ]; then
            row resultat "personne ne le garde ouvert en continu"
            row piste "le driver est peut-etre pilote par ioctl ponctuels"
        else
            procs_holding "$DEV_FD" 2>/dev/null | \
                while IFS=' ' read -r PID FDNUM CMD; do
                    [ -n "$PID" ] || continue
                    printf '  pid %-7s fd=%-4s %s\n' "$PID" "$FDNUM" "$CMD"
                done
        fi
    fi

    sec 3 "Lecture brute de l etat courant"
    if [ -e "$DEV_FD" ]; then
        HEXD="$(dd if="$DEV_FD" bs=8 count=1 2>/dev/null | od -A n -t x1 2>/dev/null | tr -s '\n ' '  ')"
        case "${HEXD}" in
            *[0-9a-f]*) row "dd bs=8" "$HEXD"
                        row piste "relancer pendant que l horloge change : les octets bougent ?" ;;
            *)          row "dd bs=8" "lecture refusee (driver write-only ?)" ;;
        esac
    fi

    sec 4 "Capture strace du daemon usine"
    STRACE_BIN="$(command -v strace 2>/dev/null)"
    DPID="$(demo_pid)"
    if [ -z "$DPID" ]; then
        row daemon "FD655_Demo inactif (front_led DEMO ON puis relancer)"
    elif [ -z "$STRACE_BIN" ]; then
        row strace "absent sur ce firmware"
        row piste "deposer un strace statique arm32 sur la cle (PATH ou /data/local/tmp)"
    else
        OD_="$(out_dir)"
        CAP="$OD_/strace_fd655.txt"
        echo "  [*] capture 8 s des appels write/ioctl du pid $DPID..."
        timeout 8 "$STRACE_BIN" -p "$DPID" -e trace=write,ioctl -s 48 -o "$CAP" 2>/dev/null
        if [ -s "$CAP" ]; then
            NBL="$(grep -c . "$CAP" 2>/dev/null)"
            row capture "$(basename "$CAP") ($NBL lignes)"
            grep -E '(write|ioctl)\(' "$CAP" 2>/dev/null | head -n 12 | sed 's/^/      /'
            row piste "les write() vers le fd du node = trames brutes a reproduire"
        else
            row strace "capture vide (ptrace bloque par le kernel ?)"
        fi
    fi

    sec 5 "Traces kernel / init / logcat"
    DM="$(dmesg 2>/dev/null | grep -iE 'fd65' | tail -n 5)"
    if [ -n "$DM" ]; then printf '%s\n' "$DM" | sed 's/^/    /'; else row dmesg "(rien)"; fi
    INIRC="$(grep -riE 'fd655_demo|fd655' /init* /system/etc/init/*.rc 2>/dev/null | head -n 5)"
    if [ -n "$INIRC" ]; then printf '%s\n' "$INIRC" | sed 's/^/    /' | cut -c1-100; else row init.rc "(aucune reference service)"; fi

    sec 6 "Binaire daemon"
    for C in /system/bin/FD655_Demo /system/xbin/FD655_Demo /system/bin/fd655_demo; do
        if [ -f "$C" ]; then
            SZ="$(wc -c < "$C" 2>/dev/null | tr -dc '0-9')"
            SUM="$(md5sum "$C" 2>/dev/null | cut -d' ' -f1)"
            MAGIC="$(head -c 4 "$C" 2>/dev/null | od -A n -t x1 2>/dev/null | tr -d ' \n')"
            row "$C" "size=$SZ md5=${SUM:-?} magic=$MAGIC"
        fi
    done

    sec 7 "Noeuds sysfs candidats"
    find /sys -maxdepth 4 \( -iname '*fd65*' -o -iname '*vfd*' \) 2>/dev/null | head -n 8 | sed 's/^/    /'
    echo ""
    return 0
}

topic_remote()
{
    echo ""
    echo "=== INVESTIGATE REMOTE (IR) ==="

    sec 1 "Devices input + layouts"
    sh "$(dirname "$0")/remote_map.sh" DEVICES 2>/dev/null || \
        sh "$(dirname "$0")/../frontal/remote_map.sh" DEVICES 2>/dev/null || \
        sh /data/scripts/remote_map.sh DEVICES 2>/dev/null || \
        row remote_map "indisponible (deploy INSTALL ?)"

    sec 2 "Modules / parametres noyau IR"
    MODS="$(grep -iE 'ir|rc_core|gpio[_-]remo' /proc/modules 2>/dev/null | head -n 5)"
    if [ -n "$MODS" ]; then printf '%s\n' "$MODS" | sed 's/^/    /'; else row modules "(built-in ou aucun)"; fi
    for P in /sys/module/*/parameters/*; do
        case "$P" in
            *ir*|*rc_*|*remo*) [ -f "$P" ] && printf '    %s = %s\n' "$P" "$(cat "$P" 2>/dev/null | head -n 1)" ;;
        esac
    done 2>/dev/null | head -n 10

    sec 3 "Snapshot materiel getevent"
    if command -v getevent > /dev/null 2>&1; then
        getevent -lp 2>/dev/null | sed -n '/add device/,/INPUT_PROP/p' | head -n 30
    else
        row getevent "absent"
    fi

    sec 4 "Layouts modifies ?"
    KL_DIR="/system/usr/keylayout"
    BK_DIR=""
    for d in /mnt/media_rw/*; do
        [ -f "$d/deploy.sh" ] && [ -d "$d/backup/keylayout" ] && BK_DIR="$d/backup/keylayout"
    done
    [ -z "$BK_DIR" ] && [ -d /data/backup/keylayout ] && BK_DIR="/data/backup/keylayout"
    if [ -n "$BK_DIR" ]; then
        ls -l "$BK_DIR" 2>/dev/null | tail -n +2 | sed 's/^/    /'
    else
        row backups "aucun (remote_map MAP pas encore utilise)"
    fi
    echo ""
    return 0
}

do_all()
{
    OD_="$(out_dir)"
    KEY_="$(key_dir)"
    TS="$(date '+%Y%m%d-%H%M%S')"
    if [ -n "$KEY_" ]; then
        REPORT="$KEY_/log/investigate_${TS}.txt"
    else
        REPORT="/data/local/tmp/investigate_${TS}.txt"
    fi
    {
        topic_display
        topic_remote
    } > "$REPORT" 2>&1
    cat "$REPORT"
    echo ""
    echo "[ OK ] rapport : $REPORT"
    return 0
}

usage()
{
    echo ""
    echo "Usage: investigate <DISPLAY|REMOTE|ALL>"
    echo ""
    echo "  DISPLAY   enquete afficheur FD655 : qui ecrit quoi sur $DEV_FD"
    echo "            (scan /proc, lecture brute, strace si dispo, traces)"
    echo "  REMOTE    enquete telecommande IR : layouts, noyau, getevent"
    echo "  ALL       tout + rapport sauvegarde sur la cle"
    echo ""
    return 0
}

run_topic()
{
    case "$1" in
        DISPLAY|display) topic_display ;;
        REMOTE|remote)   topic_remote ;;
        ALL|all)         do_all ;;
        HELP|help|-h|--help|"") usage ;;
        *)               usage ;;
    esac
}

if [ "$RUNLOG_LOADED" -eq 1 ] && runlog_start "$SCRIPT_ID"; then
    run_topic "$@" >> "$RUNLOG_FILE" 2>&1
    RC=$?
    runlog_end "$RC"
    cat "$RUNLOG_FILE"
else
    run_topic "$@"
    RC=$?
fi
exit "$RC"
