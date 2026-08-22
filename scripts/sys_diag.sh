#!/system/bin/sh
# sys_diag - sante systeme globale (complement de net_diag) :
# horloge (detecte le retour en 1970), pression memoire (lmkd),
# entropie, vitesse d'ecriture eMMC, posture securite.
#
# Usage: sys_diag.sh [STATUS|help]

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
    if [ -f "$B/core/config.sh" ]; then
        . "$B/core/config.sh"
        break
    fi
done

OK=0; WARN=0; KO=0
ok()   { printf '  [ OK ] %-22s %s\n' "$1" "$2"; OK=$((OK+1)); }
warn() { printf '  [WARN] %-22s %s\n' "$1" "$2"; WARN=$((WARN+1)); }
ko()   { printf '  [ KO ] %-22s %s\n' "$1" "$2"; KO=$((KO+1)); }
info() { printf '  [ -- ] %-22s %s\n' "$1" "$2"; }

prop_get() { getprop "$1" 2>/dev/null | tr -d '\r'; }

find_key()
{
    for d in /mnt/media_rw/*; do
        [ -f "$d/deploy.sh" ] || continue
        KEY="$d"
        return 0
    done
    return 1
}

do_time()
{
    echo ""
    echo "--- [1] Horloge ---"
    NOW="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
    EP="$(date +%s 2>/dev/null | tr -dc '0-9')"
    echo "  date box : $NOW"

    case "$EP" in
        ''|*[!0-9]*) ko "epoch" "illisible" ;;
        *)
            if [ "$EP" -lt 1577836800 ]; then
                ko "horloge" "perdue (avant 2020) -> set_time AUTO / provision --fix"
            else
                ok "horloge" "coherente"
            fi
            ;;
    esac
    TZ="$(prop_get persist.sys.timezone)"
    [ -n "$TZ" ] && info "timezone" "$TZ"
    UP="$(cut -d. -f1 /proc/uptime 2>/dev/null | tr -dc '0-9')"
    [ -n "$UP" ] && info "uptime" "$((UP / 3600))h$(((UP % 3600) / 60))m"
}

do_memory()
{
    echo ""
    echo "--- [2] Memoire / pression ---"
    AV="$(sed -n 's/MemAvailable: *\([0-9]*\) kB/\1/p' /proc/meminfo 2>/dev/null | head -n 1 | tr -dc '0-9')"
    TO="$(sed -n 's/MemTotal: *\([0-9]*\) kB/\1/p' /proc/meminfo 2>/dev/null | head -n 1 | tr -dc '0-9')"
    if [ -n "$AV" ] && [ -n "$TO" ]; then
        PCT=$((100 * AV / TO))
        case "$PCT" in
            [0-9]|[1][0-9]) warn "RAM dispo" "$((AV / 1024))/${TO} Mo (${PCT}%)" ;;
            *)              ok "RAM dispo" "$((AV / 1024))/${TO} Mo (${PCT}%)" ;;
        esac
    else
        info "RAM" "meminfo illisible"
    fi

    ZR="$(ls -1d /sys/block/zram* 2>/dev/null | head -n 1)"
    [ -n "$ZR" ] && info "zRAM" "present ($(basename "$ZR"))" || info "zRAM" "absent (piste : modprobe zram)"

    LMK_SYS="/sys/module/lowmemorykiller/parameters"
    if [ -d "$LMK_SYS" ]; then
        MINFREE="$(cat "$LMK_SYS/minfree" 2>/dev/null | tr -d '\r')"
        info "lmk minfree" "${MINFREE:-?} (pages/4ko)"
    else
        L="$(getprop 2>/dev/null | tr -d '\r' | grep 'ro\.lmk' | head -n 1)"
        case "$L" in
            "") info "lmkd" "params absents (ni sysfs ni props)" ;;
            *)  info "lmkd" "$L" ;;
        esac
    fi
}

do_entropy()
{
    echo ""
    echo "--- [3] Entropie ---"
    E="$(cat /proc/sys/kernel/random/entropy_avail 2>/dev/null | tr -dc '0-9')"
    P="$(cat /proc/sys/kernel/random/poolsize 2>/dev/null | tr -dc '0-9')"
    P="${P:-4096}"
    case "$E" in
        ''|*[!0-9]*) info "entropy_avail" "illisible" ;;
        *)
            if [ "$E" -lt 256 ]; then
                warn "entropie" "$E/$P (faible : rngd si blocages TLS)"
            else
                ok "entropie" "$E/$P"
            fi
            ;;
    esac
}

do_storage()
{
    echo ""
    echo "--- [4] Stockage ---"
    for MNT in /data /system; do
        DF="$(df -k "$MNT" 2>/dev/null | sed -n '2p' | tr -s ' ')"
        USE="$(printf '%s\n' "$DF" | cut -d' ' -f5 | tr -dc '0-9')"
        case "$USE" in
            '') info "$MNT usage" "df illisible" ;;
            *)
                if [ "$USE" -ge 90 ]; then
                    warn "$MNT usage" "${USE}%"
                else
                    ok "$MNT usage" "${USE}%"
                fi
                ;;
        esac
    done

    for LT in /sys/class/mmc_host/mmc*/mmc*:0001/device/life_time; do
        [ -f "$LT" ] || continue
        V="$(tr '\n' ' ' < "$LT" 2>/dev/null | tr -s ' ')"
        [ -n "$V" ] && info "eMMC life_time" "$V(A/B)"
        break
    done

    TMP="/data/local/tmp/.spd_$$"
    S0="$(cut -d. -f1 /proc/uptime 2>/dev/null | tr -dc '0-9')"
    dd if=/dev/zero of="$TMP" bs=64k count=128 2>/dev/null
    SYNC_RC=$?
    S1="$(cut -d. -f1 /proc/uptime 2>/dev/null | tr -dc '0-9')"
    rm -f "$TMP" 2>/dev/null
    if [ "$SYNC_RC" -eq 0 ] && [ -n "$S0" ] && [ -n "$S1" ]; then
        D=$((S1 - S0))
        [ "$D" -le 0 ] && D=1
        MB=$((8 / D))
        case "$MB" in
            0) warn "ecriture eMMC" "<1 Mo/s (lent : fs sature ?)" ;;
            *) ok "ecriture eMMC" "~${MB} Mo/s (8 Mo en ${D}s)" ;;
        esac
    else
        info "ecriture eMMC" "test impossible"
    fi
}

do_security()
{
    echo ""
    echo "--- [5] Securite ---"
    AP="$(prop_get service.adb.tcp.port)"
    LISTEN="$(netstat -tln 2>/dev/null | grep -c ':5555 ')"
    if [ "${LISTEN:-0}" -gt 0 ] || [ "$AP" = "5555" ]; then
        warn "adb reseau" "port 5555 ouvert sur LAN (iptables a prevoir)"
    else
        info "adb reseau" "ferme"
    fi

    if find_key && [ -f "$KEY/server/token" ]; then
        ok "API control" "token actif"
    else
        warn "API control 8080" "sans token (server/token sur la cle)"
    fi

    SSH_L="$(netstat -tln 2>/dev/null | grep -c ':2222 ')"
    [ "${SSH_L:-0}" -gt 0 ] && warn "ssh 2222" "actif" || info "ssh 2222" "inactif"

    SL="$(prop_get ro.boot.selinux)"
    [ -n "$SL" ] && info "selinux" "$SL"

    W="$(prop_get wifi_on)"
    B="$(prop_get bluetooth_on)"
    if [ -z "$W" ] && [ -z "$B" ]; then
        info "wireless" "etat inconnu"
    elif [ "$W" != "0" ] || [ "$B" != "0" ]; then
        warn "wireless" "wifi_on=$W bt_on=$B"
    else
        ok "wireless" "coupee"
    fi
}

do_status()
{
    echo ""
    echo "=== SYS DIAG ==="
    do_time
    do_memory
    do_entropy
    do_storage
    do_security

    echo ""
    echo "=== RESUME : ok=$OK warn=$WARN ko=$KO ==="
    [ "$KO" -gt 0 ] && echo "Priorite : corriger les KO ci-dessus"
    [ "$KO" -eq 0 ] && [ "$WARN" -gt 0 ] && echo "Ameliorations possibles : voir les WARN"
    echo ""
    [ "$KO" -eq 0 ] && return 0
    return 1
}

usage()
{
    echo ""
    echo "Usage: sys_diag [STATUS]"
    echo ""
    echo "  Diagnostic systeme complet (defaut) : horloge, memoire/lmkd,"
    echo "  entropie, stockage/eMMC, securite."
    echo "  Complement de net_diag (reseau) et inspect_all (rapport global)."
    echo ""
    return 1
}

case "$1" in
    ""|STATUS|status) do_status ;;
    HELP|help|-h|--help) usage ;;
    *)                usage ;;
esac
