#!/system/bin/sh
# stress_ram - test de provocation memoire avec surveillance des reactions.
#
# Principe : un fichier pose sur /dev (tmpfs) consomme de la RAM physique.
# Remplissage par pas de 32 Mo avec surveillance MemAvailable, tenue de
# charge, relachement, puis observation des reactions : kills lmkd /
# lowmemorykiller (logcat + dmesg), recuperation memoire, processus.
#
#   stress_ram                  profil defaut : 256 Mo, tenue 30 s
#   stress_ram <mo> [tenue_s]   ex : stress_ram 384 60
#   stress_ram STATUS           memoire courante + residus de run interrompu
#   stress_ram CLEAN            supprime les fichiers de provocation restants
#
# Securites :
#   plafond souple MemAvailable 150 Mo -> le remplissage s'arrete ;
#   seuil critique 100 Mo -> arret immediat ; maximum dur 768 Mo.
# Rapport : log/stress_ram_<ts>.txt sur la cle + resume console.
#
# NOTE : lmkd peut tuer des apps visibles (launcher...) ; le noyau du
# systeme n'est pas vise. Test volatile : rien ne survit au reboot.

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" "$(dirname "$0")/.." /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

command -v is_root >/dev/null 2>&1 || is_root() { case "$(id -u 2>/dev/null)" in 0) return 0 ;; esac; case "$(id 2>/dev/null)" in "uid=0("*) return 0 ;; esac; return 1; }

CHUNK_MO=32
FLOOR_MO=150
CRIT_MO=100
MAX_HARD_MO=768

key_dir()
{
    for d in /mnt/media_rw/*; do
        [ -f "$d/deploy.sh" ] && { printf '%s' "$d"; return 0; }
    done
    return 1
}

stress_files() { ls -1 /dev/.stress_[0-9]* 2>/dev/null; }

meminfo_val()
{
    sed -n "s/^$1: *\([0-9]*\) kB/\1/p" /proc/meminfo 2>/dev/null | head -n 1
}

mem_mo()
{
    V="$(meminfo_val "$1")"
    case "$V" in ''|*[!0-9]*) echo 0 ;; *) echo $((V / 1024)) ;; esac
}

avail_mo()
{
    A="$(meminfo_val MemAvailable)"
    case "$A" in
        ''|*[!0-9]*)
            F="$(meminfo_val MemFree)"
            C="$(meminfo_val Cached)"
            case "$F" in ''|*[!0-9]*) F=0 ;; esac
            case "$C" in ''|*[!0-9]*) C=0 ;; esac
            A=$((F + C))
            ;;
    esac
    echo $((A / 1024))
}

load_line() { cut -d' ' -f1-3 /proc/loadavg 2>/dev/null; }
proc_count() { ls -1d /proc/[0-9]* 2>/dev/null | wc -l | tr -dc '0-9'; }

lmk_events()
{
    # evenements kills memoire : logcat (lmkd) + dmesg (lowmemorykiller/oom)
    {
        logcat -d -t 500 2>/dev/null | grep -iE 'lmkd|lowmemorykiller' 
        dmesg 2>/dev/null | grep -iE 'lowmemorykiller: killing|out of memory'
    } 2>/dev/null | sort -u
}

sample()
{
    printf '%s av=%-5s free=%-6s load=%-18s procs=%s\n' \
        "$(date '+%H:%M:%S')" "$(avail_mo)" \
        "$(mem_mo MemFree)" \
        "$(load_line)" "$(proc_count)"
}

do_status()
{
    echo ""
    echo "=== STRESS RAM STATUS ==="
    echo "  MemTotal     : $(mem_mo MemTotal) Mo"
    echo "  Disponible   : $(avail_mo) Mo"
    residus="$(stress_files)"
    if [ -n "$residus" ]; then
        NB_="$(printf '%s\n' "$residus" | grep -c .)"
        SUM_=0
        for V in $(du -sk /dev/.stress_* 2>/dev/null | cut -f1); do
            SUM_=$((SUM_ + V))
        done
        echo "  Residus      : $NB_ fichier(s) (~$((SUM_ / 1024)) Mo) -> stress_ram CLEAN"
    else
        echo "  Residus      : aucun"
    fi
    echo ""
    return 0
}

do_clean()
{
    N=0
    for F in $(stress_files); do
        rm -f "$F" && N=$((N+1))
    done
    sync 2>/dev/null
    echo "[ OK ] $N fichier(s) de provocation supprime(s)"
    return 0
}

write_chunk()
{
    dd if=/dev/zero of="/dev/.stress_$1" bs=1048576 count=$CHUNK_MO 2>/dev/null
}

do_stress()
{
    TARGET="${1:-256}"
    HOLD="${2:-30}"
    case "$TARGET" in ''|*[!0-9]*) TARGET=256 ;; esac
    case "$HOLD"   in ''|*[!0-9]*) HOLD=30 ;; esac
    [ "$TARGET" -gt "$MAX_HARD_MO" ] && TARGET=$MAX_HARD_MO

    if ! is_root; then
        echo "[ERREUR] privileges root requis : su -c \"sh $0 $TARGET $HOLD\""
        return 1
    fi

    KEY_="$(key_dir)"
    TS="$(date '+%Y%m%d-%H%M%S')"
    if [ -n "$KEY_" ]; then
        mkdir -p "$KEY_/log" 2>/dev/null
        REPORT="$KEY_/log/stress_ram_${TS}.txt"
    else
        REPORT="/data/local/tmp/stress_ram_${TS}.txt"
    fi
    stress_body "$TARGET" "$HOLD" | tee -a "$REPORT"
    echo "[ OK ] rapport : $REPORT"
}

stress_body()
{
    TARGET="$1"
    HOLD="$2"

    echo ""
    echo "=== STRESS RAM - cible ${TARGET} Mo, tenue ${HOLD}s ==="

    AV0="$(avail_mo)"
    LMK0="$(lmk_events | md5sum 2>/dev/null | cut -d' ' -f1)"
    echo "[base] disponible = ${AV0} Mo"
    sample

    FILLED=0
    STEP=0
    STOP_WHY=""
    while [ "$FILLED" -lt "$TARGET" ]; do
        write_chunk "$STEP" || { STOP_WHY="ecriture tmpfs refusee"; break; }
        FILLED=$((FILLED + CHUNK_MO))
        AV="$(avail_mo)"
        sample
        if [ "$AV" -le "$CRIT_MO" ]; then
            STOP_WHY="seuil critique atteint (${AV} Mo)"
            break
        fi
        if [ "$AV" -le "$FLOOR_MO" ]; then
            STOP_WHY="plafond souple atteint (${AV} Mo)"
            break
        fi
        STEP=$((STEP + 1))
    done
    [ -z "$STOP_WHY" ] && STOP_WHY="cible ${TARGET} Mo remplie"
    echo "[rempli] $FILLED Mo - arret : $STOP_WHY"

    echo "[tenue] ${HOLD}s sous pression..."
    H=0
    while [ "$H" -lt "$HOLD" ]; do
        sleep 5
        H=$((H + 5))
        sample
    done

    echo "[relache] suppression des fichiers..."
    do_clean > /dev/null 2>&1
    R=0
    while [ "$R" -lt 4 ]; do
        sleep 3
        R=$((R + 3))
        sample
    done

    LMK_NOW="$(lmk_events)"
    echo ""
    echo "=== RESUME ==="
    echo "  rempli            : $FILLED Mo ($STOP_WHY)"
    echo "  dispo avant/apres : ${AV0} / $(avail_mo) Mo"
    if [ -n "$LMK_NOW" ]; then
        echo "  reactions memoire :"
        printf '%s\n' "$LMK_NOW" | head -n 8 | sed 's/^/      /'
    else
        echo "  reactions memoire : aucun kill detecte (box a tenu)"
    fi
    echo ""
    return 0
}

case "$1" in
    STATUS|status)        do_status ;;
    CLEAN|clean)          do_clean ;;
    HELP|help|-h|--help)
        echo ""
        echo "Usage: stress_ram [<mo> [tenue_s]|STATUS|CLEAN]"
        echo ""
        echo "  stress_ram          provoque une pression RAM (defaut 256 Mo, tenue 30 s)"
        echo "  stress_ram 384 60   profil personnalise"
        echo "  STATUS              memoire + residus"
        echo "  CLEAN               purge des fichiers de provocation"
        echo ""
        echo "Securites : arret si MemAvailable <= 150 Mo (critique 100), max 768 Mo."
        echo ""
        ;;
    ""|*)
        run_wrapped="$1"; shift
        if [ "$RUNLOG_LOADED" -eq 1 ] && runlog_start "$SCRIPT_ID"; then
            do_stress "$run_wrapped" "$@" >> "$RUNLOG_FILE" 2>&1
            RC=$?
            runlog_end "$RC"
            cat "$RUNLOG_FILE"
        else
            do_stress "$run_wrapped" "$@"
            RC=$?
        fi
        ;;
esac
