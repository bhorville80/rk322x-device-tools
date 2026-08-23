#!/system/bin/sh
# inspect_proc - inspection PROCESSUS orientee RAM : qui mange, qui peut
# etre detourne/stoppe sans risque, avec la commande de traitement suggeree.
#
# Lecture seule : aucune action n'est executee. Les candidats sont classes :
#   CRITIQUE    systeme Android, ne pas toucher
#   KIT         notre pile serveurs/scripts (normale, ne pas compter)
#   DEJA_COUPEE present dans les listes PACKAGES_DISABLE/SERVICES_STOP
#               de device.conf -> l'allegement est applique, simple constat
#   CANDIDAT    detournable : paquet -> PACKAGES_DISABLE + cut_services CUT
#               (persistant) ou am force-stop (session) ;
#               service init -> SERVICES_STOP dans device.conf
#
# Usage:
#   inspect_proc                 analyse complete (defaut)
#   inspect_proc TOP [n]         top consommateurs PSS (defaut 15)
#   inspect_proc CANDIDATES      uniquement les candidats + traitement
#   inspect_proc HELP            cette aide (sans root)
#
# Donnees : dumpsys meminfo (PSS precis), repli RSS /proc/*/statm.
# Root non requis ; certaines lectures /proc sont plus riches en root.

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

BASE="$(cd "$(dirname "$0")" && pwd)"

sec()  { echo ""; echo "--- [$1] $2 ---"; }
row()  { printf '  %-24s %s\n' "$1" "$2"; }
none() { echo "  [ -- ] $1"; }

MIN_KB=8000          # seuil candidat : 8 Mo de PSS

# listes de reference -------------------------------------------------------
CRIT="zygote zygote64 system_server surfaceflinger mediaserver servicemanager
vold netd logd installd lmkd audioserver cameraserver drmserver keystore
sdcard healthd thermalserviced sensors qmuxd rild wpa_supplicant dhcpcd
debuggerd gpsd macloader bt_voicemail"
KITP="tcpsvd httpd dropbear watch_usb start_server control_server gui_server"

is_in()
{
    # $1 = mot, liste = $2..
    W_="$1"; shift
    for L_ in "$@"; do
        [ "$W_" = "$L_" ] && return 0
    done
    return 1
}

conf_list()
{
    # $1 = cle config (PACKAGES_DISABLE | SERVICES_STOP) -> contenu brut
    KEY_="$1"
    [ -n "${CONFIG_FILE:-}" ] || return 0
    sed -n "s/^${KEY_}=//p" "$CONFIG_FILE" 2>/dev/null \
        | head -n 1 | tr -d '\r'
}

# collecte ------------------------------------------------------------------
collect_pss()
{
    # sortie : "kb pid name" triee desc ; $1 = limite (0 = tout)
    LIM_="${1:-15}"
    DUMP=""
    if command -v timeout > /dev/null 2>&1; then
        DUMP="$(timeout 20 dumpsys meminfo 2>/dev/null)"
    else
        DUMP="$(dumpsys meminfo 2>/dev/null)"
    fi
    if [ -n "$DUMP" ]; then
        printf '%s\n' "$DUMP" | awk -v min="$MIN_KB" '
            /^Total PSS by process:/ { f=1 ; next }
            f && /^[[:space:]]*$/ { exit }
            f {
                line=$0
                sub(/^[ \t]+/, "", line)
                pos=index(line, ":")
                if (pos < 2) next
                kb=substr(line, 1, pos-1)
                gsub(/[^0-9]/, "", kb)
                rest=substr(line, pos+1)
                sub(/^[ \t]+/, "", rest)
                p=index(rest, "(pid")
                if (p > 1) {
                    name=substr(rest, 1, p-1)
                    sub(/[ \t]+$/, "", name)
                    pid=substr(rest, p)
                    gsub(/[^0-9]/, "", pid)
                } else { name=rest ; pid="" }
                if (kb+0 >= min && name != "" && name != "TOTAL")
                    printf "%s %s %s\n", kb, pid, name
            }' | sort -rn | head -n "$LIM_"
        return 0
    fi
    # repli RSS (/proc) : dumpsys absent/bloque -> estimation grossiere x4
    for d_ in /proc/[0-9]*; do
        pid_="${d_#/proc/}"
        res_="$(awk '{print $2}' "$d_/statm" 2>/dev/null)"
        case "$res_" in ''|*[!0-9]*) continue ;; esac
        rss_=$((res_ * 4))
        [ "$rss_" -ge "$MIN_KB" ] || continue
        name_="$(tr '\0' ' ' < "$d_/cmdline" 2>/dev/null | cut -d' ' -f1)"
        if [ -z "$name_" ]; then
            name_="$(awk '{print $2}' "$d_/comm" 2>/dev/null | tr -d '()')"
        fi
        name_="$(basename "${name_:-unknown}")"
        echo "$rss_ $pid_ $name_"
    done 2>/dev/null | sort -rn | head -n "$LIM_"
}

classify()
{
    # $1=name -> echo CRITIQUE|KIT|COUPEE|CANDIDAT|SHELL
    N_="$1"
    case "$N_" in
        sh|sh.exe|-sh|su|adb)        echo SHELL ; return ;;
    esac
    for C_ in $CRIT; do
        [ "$N_" = "$C_" ] && { echo CRITIQUE ; return ; }
    done
    for K_ in $KITP; do
        [ "$N_" = "$K_" ] && { echo KIT ; return ; }
    done
    case " $(conf_list PACKAGES_DISABLE) $(conf_list SERVICES_STOP) " in
        *" $N_"*) echo COUPEE ; return ;;
    esac
    echo CANDIDAT
}

treat_for()
{
    # commande de traitement suggeree pour un candidat
    N_="$1"
    case "$N_" in
        *.*)
            echo "pm disable-user --user 0 $N_  (ou : ajouter a PACKAGES_DISABLE puis cut_services CUT ; session seule : am force-stop $N_)" ;;
        *)
            echo "service init : ajouter '$N_' a SERVICES_STOP (device.conf) puis field_mode APPLY" ;;
    esac
}

ram_line()
{
    MT="$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null | head -n 1)"
    MA="$(awk '/MemAvailable/{print $2}' /proc/meminfo 2>/dev/null | head -n 1)"
    MF="$(awk '/MemFree/{print $2}' /proc/meminfo 2>/dev/null | head -n 1)"
    is_num() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac }
    is_num "$MT" && row total "$((MT / 1024)) Mo (dispo : $((MA / 1024)) Mo, libre : $((MF / 1024)) Mo)"
    SW="$(awk 'NR>1{print $3}' /proc/swaps 2>/dev/null | head -n 1)"
    if is_num "$SW" && [ "$SW" -gt 0 ]; then
        row swap "actif : ${SW} ko"
    else
        row swap "[ -- ] aucun"
    fi
}

do_top()
{
    N_="${1:-15}"
    case "$N_" in ''|*[!0-9]*) N_=15 ;; esac
    sec 1 "TOP PSS ($N_) - seuil affichage ${MIN_KB} ko"
    ROWS="$(collect_pss "$N_")"
    if [ -z "$ROWS" ]; then
        none "aucun processus au-dessus du seuil (ou lecture impossible)"
        return 1
    fi
    printf '  %8s %7s %s\n' "PSS-ko" "PID" "NOM"
    printf '%s\n' "$ROWS" | while IFS=' ' read -r KB_ PID_ NM_; do
        CL_="$(classify "$NM_")"
        printf '  %8s %7s [%-8s] %s\n' "$KB_" "${PID_:--}" "$CL_" "$NM_"
    done
}

do_candidates()
{
    sec 3 "CANDIDATS DETOURNABLES (PSS >= ${MIN_KB} ko)"
    ROWS="$(collect_pss 60)"
    if [ -z "$ROWS" ]; then
        none "aucun processus au-dessus du seuil"
        return 1
    fi
    printf '%s\n' "$ROWS" | while IFS=' ' read -r KB_ PID_ NM_; do
        [ "$(classify "$NM_")" = "CANDIDAT" ] || continue
        echo ""
        printf '  %-34s %7s ko (pid %s)\n' "$NM_" "$KB_" "${PID_:--}"
        echo "    traitement : $(treat_for "$NM_")"
    done
    # verdict global (recalcule hors sous-shell)
    printf '%s\n' "$ROWS" | while IFS=' ' read -r KB_ PID_ NM_; do
        [ "$(classify "$NM_")" = "CANDIDAT" ] || continue
        echo "$KB_"
    done | {
        SUM_=0 ; CNT_=0
        while read -r KB_; do
            SUM_=$((SUM_ + KB_)) ; CNT_=$((CNT_ + 1))
        done
        if [ "$CNT_" -eq 0 ]; then
            echo ""
            echo "  [ OK ] aucun candidat : allegement conforme a la configuration"
        else
            echo ""
            echo "  VERDICT : $CNT_ candidat(s), gain potentiel estime ~$((SUM_ / 1024)) Mo"
            echo "  persistant = PACKAGES_DISABLE (device.conf) + cut_services CUT"
        fi
    }
}

do_full()
{
    echo ""
    echo "=== INSPECT PROC - processus & RAM ==="

    sec 1 "RAM globale"
    ram_line

    do_top 15

    sec 2 "PILE KIT / CRITIQUES DETECTES"
    KITV="$(ps 2>/dev/null | grep -E 'tcpsvd|httpd|dropbear|watch_usb|control_server|gui_server|start_server' | grep -v grep | wc -l)"
    if [ "${KITV:-0}" -gt 0 ]; then
        row "pile kit" "$KITV processus serveur actifs (normal, ne pas compter)"
    else
        row "pile kit" "[ -- ] absente (box pas encore deployee ?)"
    fi

    do_candidates

    sec 4 "DOUBLONS SUSPECTS (>1 pid, hors multi-listeners attendus)"
    DUP_="$(printf '%s\n' "$(collect_pss 60)" | awk '{print $3}' \
        | sort | uniq -d | grep -vE '^(tcpsvd|httpd|sh)$')"
    if [ -n "$DUP_" ]; then
        for D_ in $DUP_; do
            row "doublon" "$D_ ($(printf '%s\n' "$(collect_pss 60)" | awk -v n="$D_" '$3==n{c++} END{print c+0}') pids)"
        done
    else
        none "aucun doublon anormal"
    fi

    echo ""
    echo "=== FIN INSPECT PROC ==="
}

case "$1" in
    HELP|-h|--help)
        sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
        exit 0 ;;
esac

main()
{
    case "$1" in
        ""|STATUS)       do_full ;;
        TOP|top)         shift ; do_top "$@" ;;
        CANDIDATES|cand) do_candidates ;;
        *)
            echo "option inconnue : $1 (voir inspect_proc HELP)"
            return 1 ;;
    esac
}

if [ "$RUNLOG_LOADED" -eq 1 ] && runlog_start "$SCRIPT_ID"; then
    main "$@" >> "$RUNLOG_FILE" 2>&1 ; RC=$?
    runlog_end "$RC" ; cat "$RUNLOG_FILE"
else
    main "$@" ; RC=$?
fi
exit "$RC"
