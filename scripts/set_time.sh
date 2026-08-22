#!/system/bin/sh
# set_time - remise a l'heure de la box (remplace setHEURE_FILE / setHEURE_INIT)
#
# Usage: set_time.sh [STATUS|AUTO|FILE|RTC|INIT|SET <v>|help]
#
#   STATUS      heure actuelle + sources disponibles (lecture seule)
#   AUTO        defaut, applique a chaque mise a jour / horloge perdue :
#               1) INIT  valeur codee (sort l'horloge de l'etat 1970)
#               2) FILE  SET_HEURE sur la cle (heure du PC au moment
#                        de la preparation de la cle)
#               3) adb   SET <v> pousse par le PC (provision --fix,
#                        panneau web) - etape externe finale, la plus precise
#   FILE        force la lecture du fichier SET_HEURE sur la cle
#   RTC         regle l'heure systeme depuis l'horloge materielle (manuel)
#   INIT        force la valeur codee ci-dessous
#   SET <v>     applique une valeur passee par un hote (adb / panneau web /
#               provision --fix) : YYYYMMDD.HHMMSS (UTC) ou MMDDhhmmCCYY.ss
#
# Le fichier SET_HEURE est depose par le PC avant branchement :
# admin/linux/write_set_heure.sh ou admin/windows/write_set_heure.ps1.
#
# Format du fichier SET_HEURE : une ligne, ex : 20260822.143000

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

# dernier recours : valeur codee (MMDDhhmmCCYY.ss) - ajuster avant un depot
FALLBACK_TIME="082220262000.00"

MIN_EPOCH=1577836800    # 2020-01-01

find_key()
{
    KEY=""
    for d in /mnt/media_rw/*; do
        [ -f "$d/deploy.sh" ] || continue
        KEY="$d"
        return 0
    done
    return 1
}

epoch_now()
{
    date +%s 2>/dev/null | tr -dc '0-9'
}

clock_ok()
{
    E="$(epoch_now)"
    case "$E" in ''|*[!0-9]*) return 1 ;; esac
    [ "$E" -ge "$MIN_EPOCH" ]
}

show_clock()
{
    echo "  actuelle : $(date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null)"
    UP="$(cut -d. -f1 /proc/uptime 2>/dev/null | tr -dc '0-9')"
    case "$UP" in ''|*[!0-9]*) ;; *) echo "  uptime   : $((UP / 3600))h$(((UP % 3600) / 60))m" ;; esac
}

apply_value()    # $1 = YYYYMMDD.HHMMSS (UTC) ou MMDDhhmm[[CC]YY].ss
{
    V="$(printf '%s' "$1" | tr -d '[:space:]')"
    case "$V" in
        [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9].[0-9][0-9][0-9][0-9][0-9][0-9])
            date -u -s "$V" > /dev/null 2>&1 || return 1
            ;;
        [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9].[0-9][0-9]|[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9].[0-9][0-9])
            date "$V" > /dev/null 2>&1 || return 1
            ;;
        *)
            echo "[ERREUR] format invalide : $V"
            echo "         attendu YYYYMMDD.HHMMSS (UTC) ou MMDDhhmmCCYY.ss"
            return 1
            ;;
    esac
    clock_ok || { echo "[WARN] valeur appliquee mais horloge toujours incoherente"; return 1; }
    echo "[ OK ] nouvelle heure : $(date '+%Y-%m-%d %H:%M:%S')"
    return 0
}

src_file()
{
    find_key || { echo "[ERREUR] cle USB introuvable"; return 1; }
    F="$KEY/SET_HEURE"
    [ -f "$F" ] || { echo "[ERREUR] $F absent (deposer a la racine de la cle)"; return 1; }
    V="$(head -n 1 "$F" | tr -d '[:space:]')"
    [ -n "$V" ] || { echo "[ERREUR] fichier SET_HEURE vide"; return 1; }
    echo "[..] source : SET_HEURE ($KEY)"
    apply_value "$V"
}

src_rtc()
{
    RD="/sys/class/rtc/rtc0"
    [ -f "$RD/date" ] && [ -f "$RD/time" ] || {
        echo "[ERREUR] RTC materielle non exposee"; return 1; }
    D="$(cat "$RD/date" 2>/dev/null | tr -d '\r')"     # YYYY-MM-DD
    T="$(cat "$RD/time" 2>/dev/null | tr -d '\r')"     # HH:MM:SS
    YY="${D%%-*}"; REST="${D#*-}"; MM="${REST%%-*}"; DD="${REST#*-}"
    HH="${T%%:*}"; MT="${T#*:}"; MI="${MT%%:*}"; SS="${MT#*:}"
    V="${MM}${DD}${HH}${MI}${YY}.${SS}"
    case "$(echo "$V" | tr -dc '0-9')" in
        [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;;
        *) echo "[ERREUR] RTC illisible ($D $T)"; return 1 ;;
    esac
    # RTC plausible seulement si >= 2020 (sinon pile morte / jamais initialisee)
    case "$YY" in 20[2-9][0-9]) ;; *) echo "[ERREUR] RTC non plausible ($D) - pile ou initialisation"; return 1 ;; esac
    echo "[..] source : RTC materielle"
    apply_value "$V"
}

src_init()
{
    echo "[WARN] source : valeur codee de secours ($FALLBACK_TIME)"
    echo "       heure probablement fausse - preferer SET_HEURE ou SET"
    apply_value "$FALLBACK_TIME"
}

do_status()
{
    echo ""
    echo "=== SET_TIME STATUS ==="
    show_clock

    echo ""
    if clock_ok; then
        echo "  verdict  : horloge coherente"
    else
        echo "  verdict  : HORLOGE PERDUE (< 2020) -> set_time AUTO"
    fi

    echo ""
    echo "--- Sources (ordre AUTO : INIT -> FILE -> adb) ---"
    echo "  INIT      : $FALLBACK_TIME"
    if find_key && [ -f "$KEY/SET_HEURE" ]; then
        echo "  FILE      : SET_HEURE present ($(head -n 1 "$KEY/SET_HEURE" | tr -d '[:space:]'))"
    else
        echo "  FILE      : SET_HEURE absent (admin/*/write_set_heure)"
    fi
    echo "  adb       : SET <v> par le PC (set_box_time / provision --fix / web)"
    if [ -f /sys/class/rtc/rtc0/date ]; then
        echo "  RTC       : $(cat /sys/class/rtc/rtc0/date 2>/dev/null) $(cat /sys/class/rtc/rtc0/time 2>/dev/null) (manuel)"
    else
        echo "  RTC       : non exposee"
    fi
    echo ""
    echo "--- Pousse par un hote ---"
    echo "  adb shell su -c 'set_time SET 20260822.143000'"
    echo "  (ou panneau web SYNC HORLOGE, ou provision --fix)"
    echo ""
    return 0
}

do_auto()
{
    echo ""
    echo "=== SET_TIME AUTO ==="
    show_clock
    if clock_ok; then
        echo "[ OK ] horloge deja coherente, aucun reglage"
        return 0
    fi

    echo "[1/3] INIT : valeur codee..."
    src_init || echo "[ -- ] INIT sans effet, on continue"

    echo "[2/3] FILE : SET_HEURE sur la cle..."
    src_file || echo "[ -- ] SET_HEURE absent ou refuse"

    echo "[3/3] adb : la poussée PC (SET) reste a faire par le PC"
    echo "      (admin/*/set_box_time, provision --fix ou panneau web)"

    if clock_ok; then
        return 0
    fi
    echo "[WARN] horloge toujours incoherente apres AUTO"
    return 1
}

case "$1" in
    ""|AUTO|auto)           require_root && do_auto ;;
    STATUS|status)          do_status ;;
    FILE|file)              require_root && src_file ;;
    RTC|rtc)                require_root && src_rtc ;;
    INIT|init)              require_root && src_init ;;
    SET|set)                require_root && apply_value "$2" ;;
    HELP|help|-h|--help)    sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//' ;;
    *)                      sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
exit "$?"
