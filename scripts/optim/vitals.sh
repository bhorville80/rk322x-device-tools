#!/system/bin/sh
# vitals - signes vitaux de la carte en un coup d'oeil :
# temperatures, CPU (freq/governor/charge), RAM, eMMC (usure + remplissage),
# lien reseau, alimentation (si telemetrie exposee).
#
# Complement de : thermal (detaile profils ECO/PERF), net_diag (reseau),
# sys_diag (horloge/lmkd/entropie/securite).
#
# Usage: vitals.sh [STATUS|WATCH [N] [S]|CSV|help]
#
#   STATUS         rapport complet (lecture seule)
#   WATCH [N] [S]  N releves toutes les S secondes (defaut : 10 x 5s)
#                  -> detecter une montee en temperature dans le temps
#   CSV            une ligne machine (epoch,iso,tmax,zone,mhz,gov,load,ram%,
#                  uptime) pour collecte PC : admin/*/vitals_history
#
# NOTE consommation : les box RK322x n'exposent pas de telemetry PMIC.
# Les proxy disponibles sont la frequence/governor (voir thermal ECO),
# la temperature et la charge reseau/CPU.

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" "$(dirname "$0")/.." /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

OK=0; WARN=0; KO=0
ok()   { printf '  [ OK ] %-22s %s\n' "$1" "$2"; OK=$((OK+1)); }
warn() { printf '  [WARN] %-22s %s\n' "$1" "$2"; WARN=$((WARN+1)); }
ko()   { printf '  [ KO ] %-22s %s\n' "$1" "$2"; KO=$((KO+1)); }
info() { printf '  [ -- ] %-22s %s\n' "$1" "$2"; }

usage()
{
    echo ""
    echo "Usage: vitals.sh <STATUS|WATCH [N] [S]>"
    echo ""
    echo "  STATUS        rapport vital complet (lecture seule)"
    echo "  WATCH [N] [S] N releves toutes les S s (defaut 10 x 5)"
    echo ""
}

# --- lectures brutes ---------------------------------------------------------

zone_temp()   # <- temperature milli-C d'une zone, vide si illisible
{
    cat "$1/temp" 2>/dev/null | tr -dc '0-9'
}

max_temp()    # <- "milliC type" de la zone la plus chaude
{
    BEST=""
    for Z in /sys/class/thermal/thermal_zone*; do
        [ -d "$Z" ] || continue
        T="$(zone_temp "$Z")"
        case "$T" in ''|*[!0-9]*) continue ;; esac
        if [ -z "$BEST" ] || [ "$T" -gt "$BEST" ]; then
            BEST="$T"
            BEST_T="$(cat "$Z/type" 2>/dev/null)"
        fi
    done
    echo "${BEST:-}${BEST_T:+ $BEST_T}"
}

cpu_cur_freq()    # <- kHz du premier coeur pilotable
{
    for C in /sys/devices/system/cpu/cpu[0-9]*; do
        F="$(cat "$C/cpufreq/scaling_cur_freq" 2>/dev/null | tr -dc '0-9')"
        [ -n "$F" ] && { echo "$F"; return 0; }
    done
    return 1
}

cpu_governor()
{
    for C in /sys/devices/system/cpu/cpu[0-9]*; do
        G="$(cat "$C/cpufreq/scaling_governor" 2>/dev/null)"
        [ -n "$G" ] && { echo "$G"; return 0; }
    done
    return 1
}

ram_avail_pct()    # <- % disponible (vide si illisible)
{
    AV="$(sed -n 's/MemAvailable: *\([0-9]*\) kB/\1/p' /proc/meminfo 2>/dev/null | head -n 1 | tr -dc '0-9')"
    TO="$(sed -n 's/MemTotal: *\([0-9]*\) kB/\1/p' /proc/meminfo 2>/dev/null | head -n 1 | tr -dc '0-9')"
    case "$AV" in ''|*[!0-9]*) return 1 ;; esac
    case "$TO" in ''|*[!0-9]*) return 1 ;; esac
    echo $((100 * AV / TO))
}

load1()
{
    cut -d' ' -f1 /proc/loadavg 2>/dev/null
}

swap_used_pct()    # <- % de swap utilise (0 si aucun swap, vide si erreur)
{
    awk 'NR>1 { t+=$3 ; f+=$4 } END { if (t>0) printf "%d\n", (t-f)*100/t ; else print "0" }' /proc/swaps 2>/dev/null
}

pswap_delta()      # <- pages swappées depuis la derniere mesure (etat local)
{
    S="/data/local/tmp/vitals_pswp.state"
    P="$(awk '$1=="pswpin"{i=$2}$1=="pswpout"{o=$2}END{printf "%d", i+o}' /proc/vmstat 2>/dev/null)"
    case "$P" in ''|*[!0-9]*) return 1 ;; esac
    O="$(cat "$S" 2>/dev/null | tr -dc '0-9')"
    echo "$P" > "$S" 2>/dev/null
    case "$O" in ''|*[!0-9]*) return 1 ;; esac
    D=$((P - O)) ; [ "$D" -lt 0 ] && D=0
    echo "$D"
}

uptime_min()
{
    U="$(cut -d. -f1 /proc/uptime 2>/dev/null | tr -dc '0-9')"
    case "$U" in ''|*[!0-9]*) return 1 ;; esac
    echo $((U / 60))
}

# --- relevé compact (une ligne) pour WATCH -----------------------------------

snapshot_line()
{
    MT="$(max_temp)"
    TMAX="${MT%% *}"
    TC=""
    case "$TMAX" in ''|*[!0-9]*) ;; *) TC="$((TMAX / 1000))C" ;; esac
    F="$(cpu_cur_freq)" && FM="$((F / 1000))MHz" || FM="?"
    G="$(cpu_governor)" || G="?"
    L="$(load1)"
    R="$(ram_avail_pct)" && RP="${R}%" || RP="?"
    SW="$(swap_used_pct)" && SP="${SW}%" || SP="-"
    printf '%s  Tmax=%-5s cpu=%-7s gov=%-12s load=%-5s ram=%-5s swp=%s\n' \
        "$(date '+%H:%M:%S')" "${TC:-?}" "$FM" "$G" "${L:-?}" "$RP" "$SP"
}

# --- sections STATUS ----------------------------------------------------------

sec_thermal()
{
    echo ""
    echo "--- [1] Temperatures ---"
    ANY=0
    for Z in /sys/class/thermal/thermal_zone*; do
        [ -d "$Z" ] || continue
        T="$(zone_temp "$Z")"
        case "$T" in ''|*[!0-9]*) continue ;; esac
        ANY=1
        N="$(cat "$Z/type" 2>/dev/null)"
        C=$((T / 1000))
        if [ "$C" -ge 75 ]; then
            ko "${N:-zone}" "${C} C (critique, voir thermal ECO)"
        elif [ "$C" -ge 60 ]; then
            warn "${N:-zone}" "${C} C (elevee)"
        else
            ok "${N:-zone}" "${C} C"
        fi
    done
    [ "$ANY" -eq 0 ] && info "zones" "aucune zone thermique lisible"
}

sec_cpu()
{
    echo ""
    echo "--- [2] CPU / charge ---"
    G="$(cpu_governor)" && info "governor" "$G (profil : thermal ECO/PERF)"
    F="$(cpu_cur_freq)" && info "frequence" "$((F / 1000)) MHz"
    L="$(load1)"
    NC="$(ls -1d /sys/devices/system/cpu/cpu[0-9]* 2>/dev/null | wc -l)"
    case "$L" in ''|*.*.*) ;; *)
        case "$L" in
            *.*) INT="${L%%.*}"; DEC="${L#*.}";;
            *)   INT="$L"; DEC="0";;
        esac
        case "$INT$DEC" in ''|*[!0-9]*) ;;
            *) if [ "$((INT * 10 + DEC))" -gt "$((NC * 20))" ]; then
                   warn "charge" "$L ($NC coeurs)"
               else
                   ok "charge" "$L ($NC coeurs)"
               fi ;;
        esac ;;
    esac
}

sec_ram()
{
    echo ""
    echo "--- [3] RAM ---"
    R="$(ram_avail_pct)" && ok "RAM dispo" "${R}%" || info "RAM dispo" "illisible"

    # swap : total/libre + % utilise + activite (thrashing ?)
    awk 'NR>1 { t+=$3 ; f+=$4 ; n++ }
         END {
             if (n>0) printf "%d partitions/fichiers, total %d Mo, libre %d Mo (%d%% utilise)\n", n, t/1024, f/1024, (t-f)*100/t
             else print "aucun swap actif"
         }' /proc/swaps 2>/dev/null | while IFS= read -r L_; do
        info "swap" "$L_"
    done
    D="$(pswap_delta 2>/dev/null)"
    case "$D" in
        "") info "activite swap" "premiere mesure (delta au prochain appel)" ;;
        0)   ok "activite swap" "nulle depuis la derniere mesure" ;;
        *)   if [ "$D" -gt 2048 ]; then
                 warn "activite swap" "$D pages/ecart -> THRASHING possible (RAM insuffisante)"
             else
                 ok "activite swap" "$D pages/ecart"
             fi ;;
    esac
}

sec_storage()
{
    echo ""
    echo "--- [4] Stockage / usure ---"

    for M in /sys/class/mmc_host/mmc*/mmc*:0001/device; do
        [ -d "$M" ] || continue
        EOL="$(cat "$M/pre_eol_info" 2>/dev/null | tr -d '\r')"
        LT_A="$(cat "$M/life_time" 2>/dev/null | head -n 1 | tr -d '\r')"
        case "$EOL" in
            0x01) ok  "eMMC eol"  "$EOL (normale)  life_time=$LT_A" ;;
            0x02) warn "eMMC eol" "$EOL (reserve consommee)  life_time=$LT_A" ;;
            0x03) ko   "eMMC eol" "$EOL (urgent, sauvegarder !)  life_time=$LT_A" ;;
            "")   info "eMMC eol"  "non expose par ce noyau" ;;
            *)    info "eMMC eol"  "$EOL  life_time=$LT_A" ;;
        esac
        break
    done

    DL="$(df -k /data 2>/dev/null | tail -n 1)"
    case "$DL" in
        */data*|"Filesystem"*) ;;
        "")
            info "/data" "illisible"
            ;;
        *)
            set -- $DL
            USE="$5"
            case "$USE" in *%) USE="${USE%\%}" ;; *) USE="" ;; esac
            case "$USE" in ''|*[!0-9]*)
                ko "/data" "remplissage illisible"
            ;;
                [0-9]|[1-7][0-9]) ok "/data" "${USE}% utilise" ;;
                [8][0-9]|[9][0-4]) warn "/data" "${USE}% utilise" ;;
                *) ko "/data" "${USE}% utilise (presque plein)" ;;
            esac
            ;;
    esac
}

sec_net()
{
    echo ""
    echo "--- [5] Reseau ---"
    for IF in eth0 wlan0; do
        D="/sys/class/net/$IF"
        [ -d "$D" ] || continue
        CA="$(cat "$D/carrier" 2>/dev/null | tr -dc '0-9')"
        RX="$(cat "$D/statistics/rx_bytes" 2>/dev/null | tr -dc '0-9')"
        TX="$(cat "$D/statistics/tx_bytes" 2>/dev/null | tr -dc '0-9')"
        case "$CA" in
            1) ok "$IF" "lien actif  rx=$((RX / 1024 / 1024)) Mo tx=$((TX / 1024 / 1024)) Mo" ;;
            0) warn "$IF" "lien down  rx=${RX:-?} tx=${TX:-?}" ;;
            *) info "$IF" "etat inconnu (interface presente)" ;;
        esac
    done
    ip -4 addr show eth0 2>/dev/null | sed -n 's/.*inet \([0-9.]*\).*/  [ -- ] IP                 \1/p'
}

sec_power()
{
    echo ""
    echo "--- [6] Alimentation ---"
    FOUND=0
    for P in /sys/class/power_supply/*; do
        [ -d "$P" ] || continue
        FOUND=1
        V="$(cat "$P/voltage_now" 2>/dev/null)"
        C="$(cat "$P/current_now" 2>/dev/null)"
        S="$(cat "$P/status" 2>/dev/null | tr -d '\r')"
        MSG="$S"
        [ -n "$V" ] && MSG="$MSG ${V}uV"
        [ -n "$C" ] && MSG="$MSG ${C}uA"
        info "$(basename "$P")" "${MSG:-present}"
    done
    if [ "$FOUND" -eq 0 ]; then
        info "telemetrie" "aucune (PMIC non expose sur RK322x)"
        info "proxy conso" "frequences basses + thermal ECO = moins de watts"
    fi
}

do_status()
{
    echo ""
    echo "=== VITALS $(date '+%Y-%m-%d %H:%M:%S') ==="
    UP="$(uptime_min)" && [ -n "$UP" ] && info "uptime" "${UP} min"

    sec_thermal
    sec_cpu
    sec_ram
    sec_storage
    sec_net
    sec_power

    echo ""
    echo "--- Bilan ---"
    printf '  OK:%s  WARN:%s  KO:%s\n' "$OK" "$WARN" "$KO"
    echo ""

    [ "$KO" -eq 0 ] || return 1
    return 0
}

do_watch()
{
    N="${1:-10}"
    S="${2:-5}"
    case "$N" in ''|*[!0-9]*) N=10 ;; esac
    case "$S" in ''|*[!0-9]*) S=5 ;; esac
    [ "$N" -ge 1 ] || N=1
    [ "$S" -ge 1 ] || S=1

    echo ""
    echo "=== VITALS WATCH : $N releves x ${S}s ==="
    echo ""
    I=0
    while [ "$I" -lt "$N" ]; do
        I=$((I + 1))
        snapshot_line
        [ "$I" -lt "$N" ] && sleep "$S"
    done
    echo ""
    return 0
}

do_csv()
{
    MT="$(max_temp)"
    TMAX="${MT%% *}"
    ZONE="${MT#* }"
    [ "$ZONE" = "$TMAX" ] && ZONE=""
    F="$(cpu_cur_freq)" && FM="$((F / 1000))" || FM=""
    G="$(cpu_governor)"
    L="$(load1)"
    R="$(ram_avail_pct)"
    U="$(uptime_min)"
    SW="$(swap_used_pct)"
    PD="$(pswap_delta 2>/dev/null)"
    E="$(date +%s 2>/dev/null | tr -dc '0-9')"
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "${E:-0}" \
        "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)" \
        "$([ -n "$TMAX" ] && echo $((TMAX / 1000)))" \
        "$ZONE" "$FM" "$G" "$L" "$R" "$U" \
        "${SW:-}" "${PD:-}"
}

case "$1" in
    ""|STATUS|status)       do_status ;;
    WATCH|watch)            shift; do_watch "$@" ;;
    CSV|csv)                do_csv ;;
    HELP|help|-h|--help)    usage ;;
    *)                      usage; exit 1 ;;
esac
exit "$?"
