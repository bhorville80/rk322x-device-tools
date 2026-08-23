#!/system/bin/sh
# inspect_dev - capacites d'EXECUTION EMBARQUEE : peut-on heberger sur la
# box de petits processus codes maison pour prendre en charge / alleger
# des taches ? Audit factuel + micro-benchmark du cout d'un mini-daemon.
#
# Lecture seule SAUF le bench : il cree un process sommeil temporaire,
# le mesure puis le tue (auto-nettoyage garanti par trap).
#
# Sections :
#   [1] runtimes disponibles (mksh/busybox/toybox, applets utiles)
#   [2] architecture/ABI (binaires statiques armeabi executables ?)
#   [3] ecriture + execution (/data noexec ?, espace, system rw)
#   [4] primitives de service (hook boot, tcpsvd, fifo, horloge, cron ?)
#   [5] micro-benchmark cout d'un mini-daemon shell (RSS reel mesure)
#   [6] verdicts par strategie avec recommandations
#
# Usage:
#   inspect_dev               audit complet + bench (defaut)
#   inspect_dev AUDIT         sans bench (lecture seule stricte)
#   inspect_dev BENCH         uniquement le micro-benchmark
#   inspect_dev HELP          cette aide (sans root)

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" "$(dirname "$0")/.." /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

for B in "$(dirname "$0")/core" "$(dirname "$0")/../core" /data/scripts/core; do
    [ -f "$B/config.sh" ] && { . "$B/config.sh"; break; }
done

sec()   { echo ""; echo "--- [$1] $2 ---"; }
row()   { printf '  %-22s %s\n' "$1" "$2"; }
none()  { echo "  [ -- ] $1"; }
ok_ko() { printf '  [%s] %s\n' "$1" "$2"; }

have() { command -v "$1" > /dev/null 2>&1 && return 0 ; return 1 ; }

# ------------------------------------------------------------------ [1] runtimes
sec 1 "RUNTIMES"
SH_BIN="$(printf '%s' "$SHELL")"
row sh "$(getprop ro.build.shell 2>/dev/null)${SH_BIN:+ ($SH_BIN)}"
if have busybox; then
    BBV="$(busybox 2>&1 | head -n 1)"
    NA="$(busybox --list 2>/dev/null | wc -l)"
    row busybox "${BBV:-present} (${NA:-?} applets)"
elif have toybox; then
    row toybox "$(toybox 2>&1 | head -n 1)"
else
    none "ni busybox ni toybox exposes (toolbox seul ?)"
fi
MISS=""
for A_ in nc dd wget tar mkfifo sed awk sort tr cut; do
    have "$A_" || MISS="$MISS $A_"
done
[ -n "$MISS" ] && row "applets manquantes" "$MISS" || row "applets cles" "toutes presentes"

# ------------------------------------------------------------------ [2] abi
sec 2 "ARCHITECTURE / ABI"
ABI="$(getprop ro.product.cpu.abi 2>/dev/null)"
ABIL="$(getprop ro.product.cpu.abi_list 2>/dev/null)"
HW="$(sed -n 's/^Hardware[ \t]*:[ \t]*//p' /proc/cpuinfo 2>/dev/null | head -n 1)"
row abi "${ABI:-inconnue} ($(printf '%s' "$ABIL"))"
row soc "${HW:-inconnu}"
case "$ABI" in
    armeabi-v7a|arm64-v8a) ok_ko OK "binaires statiques ARM (cross-compile NDK) executables sur ce socle" ;;
    *)                     ok_ko !! "ABI inhabituelle : valider avant tout deploiement binaire" ;;
esac

# ------------------------------------------------------------------ [3] exec/montages
sec 3 "ECRITURE + EXECUTION"
DATA_M="$(mount 2>/dev/null | grep ' /data ' | head -n 1)"
case "$DATA_M" in
    *noexec*) ok_ko KO "/data montee noexec -> binaires custom interdits sous /data (scripts shell OK)" ;;
    "")       none "montage /data illisible (root requis pour ce verdict)" ;;
    *)        ok_ko OK "/data executable -> binaires statiques admis (/data/local/tmp)" ;;
esac
DF_="$(df /data/local/tmp 2>/dev/null | tail -n 1 | awk '{print $4}')"
case "$DF_" in ''|*[!0-9]*) none "espace /data/local/tmp illisible" ;;
             *)             row "espace /data/local/tmp" "$(($DF_ / 1024)) Mo libres" ;; esac
SYSRW="$(sh "$(dirname "$0")/../outils/system_rw.sh" STATUS 2>/dev/null \
         || sh "$(dirname "$0")/../../outils/system_rw.sh" STATUS 2>/dev/null \
         || sh /data/scripts/system_rw.sh STATUS 2>/dev/null \
         || echo "[ -- ] system_rw indisponible")"
row "system rw" "$(printf '%s' "$SYSRW" | head -n 2 | tr '\n' ' ')"

# ------------------------------------------------------------------ [4] primitives
sec 4 "PRIMITIVES DE SERVICE"
if [ -x /data/scripts/boot.sh ] || [ -f /data/scripts/boot.sh ]; then
    BS="$(sh /data/scripts/boot.sh STATUS 2>/dev/null | tail -n 3 | tr '\n' ' ')"
    row "hook boot" "${BS:-present (STATUS illisible)}"
else
    row "hook boot" "[ -- ] non installe (deploy INSTALL) -> pas de lancement au boot hors adb"
fi
have tcpsvd && ok_ko OK "tcpsvd : fabrique de daemons reseau multi-connexions (pattern control_server)" \
              || none "tcpsvd absent -> repli mono-slot FIFO eprouve"
have mkfifo && ok_ko OK "mkfifo : files de messages inter-process (pattern incoming/)" \
             || none "mkfifo absent"
CRON=""; have crond && CRON=crond ; have cron && CRON="$CRON cron"
[ -n "$CRON" ] && row cron "$CRON present" \
               || row cron "absent -> remplacer par hook BOOT_* + boucle 'while :; do sleep N; done'"
row "horloge" "$(date '+%Y-%m-%d %H:%M:%S') (source : $(getprop persist.sys.timezone 2>/dev/null))"
have logger && ok_ko OK "logger : trace vers logd depuis un daemon" || none "logger absent -> logs par fichiers"

# ------------------------------------------------------------------ [5] bench
BENCH()
{
    sec 5 "MICRO-BENCHMARK : cout d'un mini-daemon shell"
    MA1="$(awk '/MemAvailable/{print $2}' /proc/meminfo 2>/dev/null)"
    ( while : ; do sleep 30 ; done ) &
    BPID=$!
    trap 'kill "$BPID" 2>/dev/null' EXIT INT TERM
    sleep 1
    RES="$(awk '{print $2}' "/proc/$BPID/statm" 2>/dev/null)"
    case "$RES" in ''|*[!0-9]*) RES="" ;; esac
    ST="$(awk '{print $3}' "/proc/$BPID/stat" 2>/dev/null)"
    kill "$BPID" 2>/dev/null
    wait "$BPID" 2>/dev/null
    trap - EXIT INT TERM
    MA2="$(awk '/MemAvailable/{print $2}' /proc/meminfo 2>/dev/null)"
    if [ -n "$RES" ]; then
        row "RSS du daemon" "$((RES * 4)) ko (~$((RES * 4 / 1024)) Mo) - boucle sleep 30"
    else
        none "measure impossible (/proc/<pid> masque ?)"
    fi
    if [ -n "$MA1" ] && [ -n "$MA2" ]; then
        row "delta MemAvailable" "$(( (MA1 - MA2) )) ko au pic (process + enfants)"
    fi
    row "etat apres nettoyage" "process de test tue, rien ne subsiste"
}

# ------------------------------------------------------------------ [6] verdicts
# ------------------------------------------------- [4b] ksm + io scheduler

KSM_SCHED()
{
    sec 4b "DEDUPLICATION KSM + SCHEDULER I/O"
    if [ -d /sys/kernel/mm/ksm ]; then
        KR="$(cat /sys/kernel/mm/ksm/run 2>/dev/null)"
        KP="$(cat /sys/kernel/mm/ksm/pages_to_scan 2>/dev/null)"
        KS="$(cat /sys/kernel/mm/ksm/pages_shared 2>/dev/null)"
        case "$KR" in
            1) row ksm "ACTIF (pages_to_scan=${KP:-?}, shared=${KS:-0})" ;;
            *) row ksm "DISPONIBLE mais inactif -> 'echo 1 > .../ksm/run' au boot :" ;
               echo "         gain potentiel sur pages identiques (daemons busybox)" ;;
        esac
    else
        row ksm "non expose par ce kernel"
    fi
    for D_ in /sys/block/mmcblk0 /sys/block/mmcblk1; do
        [ -d "$D_/queue" ] || continue
        B_="${D_#/sys/block/}"
        CUR_="$(cat "$D_/queue/scheduler" 2>/dev/null | tr ',' ' ')"
        DEF_=""
        for S_ in $CUR_; do
            case "$S_" in \[*\]) DEF_="$S_" ;; esac
        done
        row "sched $B_" "${CUR_:-illisible} (actuel : ${DEF_:-?})"
        case "$DEF_" in
            *cfq*) echo "         cfq penalise les petits daemons ; tester : echo deadline > $D_/queue/scheduler" ;;
        esac
    done
}

VERDICTS()
{
    sec 6 "VERDICTS PAR STRATEGIE"
    ok_ko OK "daemon shell boucle sleep : VIABLE (cf. bench ci-dessus, ~1-2 Mo/piece)"
    if have tcpsvd; then
        ok_ko OK "service reseau tcpsvd : VIABLE (fabrique eprouvee du kit)"
    else
        ok_ko !! "service reseau : FIFO mono-slot seulement (pas de tcpsvd)"
    fi
    case "$(mount 2>/dev/null | grep ' /data ' | head -n 1)" in
        *noexec*"")
            ;;
        *noexec*)
            ok_ko !! "binaire C statique : BLOQUE par noexec /data -> rester en shell/busybox" ;;
        *)
            ok_ko OK "binaire C statique (NDK armeabi) : ADMIS si ABI conforme + root pour poser" ;;
    esac
    [ -f /data/scripts/boot.sh ] \
        && ok_ko OK "lancement persistant : VIABLE (hook boot actif, BOOT_* device.conf)" \
        || ok_ko !! "lancement persistant : installer d'abord le toolkit ([I1])"
    echo ""
    echo "  Recommandation : petites taches recurrentes = script sh dans"
    echo "  /data/scripts + entree BOOT_* (device.conf) + boucle sleep long ;"
    echo "  service ponctuel = tcpsvd ; eviter tout daemon Java/app_process"
    echo "  (cochet RAM 10-50x superieure)."
}

case "$1" in
    HELP|-h|--help)
        sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
        exit 0 ;;
esac

main()
{
    case "$1" in
        ""|FULL)     VERDICT_MAIN="1" ;;
        AUDIT)       VERDICT_MAIN="0" ;;
        BENCH)       BENCH ; return 0 ;;
        *)           echo "option inconnue : $1 (voir inspect_dev HELP)" ; return 1 ;;
    esac
    echo ""
    echo "=== INSPECT DEV - capacites d'execution embarquee ==="
    KSM_SCHED
    [ "${VERDICT_MAIN}" = "1" ] && BENCH
    VERDICTS
    echo ""
    echo "=== FIN INSPECT DEV ==="
}

if [ "$RUNLOG_LOADED" -eq 1 ] && runlog_start "$SCRIPT_ID"; then
    main "$@" >> "$RUNLOG_FILE" 2>&1 ; RC=$?
    runlog_end "$RC" ; cat "$RUNLOG_FILE"
else
    main "$@" ; RC=$?
fi
exit "$RC"
