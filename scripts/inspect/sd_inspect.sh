#!/system/bin/sh
# sd_inspect - investigation carte SD : boot bloque quand la SD est inseree
#
# Contexte RK322x : le BootROM/loader peut essayer de booter sur la SD,
# et le driver mmc des noyaux 3.10/4.4 peut se bloquer sur certaines cartes
# (SDXC/UHS). Cet outil rassemble les preuves pour trancher entre :
#   A) blocage au stade loader (avant le noyau)    -> TROUBLESHOOTING.md
#   B) blocage au stade noyau/init (erreurs mmc)   -> traces pstore
#   C) carte vue mais jamais montee (stade vold)   -> adoption/format
#
# Usage: sd_inspect.sh [STATUS|DMESG|help]
#
#   STATUS   rapport complet carte SD / mmc (lecture seule)
#   DMESG    messages noyau live filtres mmc/sdhci (apres insertion a chaud :
#            inserer la carte, attendre 5s, puis lancer DMESG)

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
    echo "Usage: sd_inspect.sh <STATUS|DMESG>"
    echo ""
    echo "  STATUS   rapport complet carte SD / mmc (lecture seule)"
    echo "  DMESG    messages noyau live filtres (insertion a chaud)"
    echo ""
}

dev_file()    # tolere les deux layouts sysfs (fichier direct ou sous device/)
{
    cat "$1/$2" 2>/dev/null || cat "$1/device/$2" 2>/dev/null
}

human_size()    # secteurs 512B -> taille lisible
{
    S="$1"
    case "$S" in ''|*[!0-9]*) echo "?" ; return ;; esac
    M=$((S / 2048))
    if [ "$M" -ge 1024 ]; then
        echo "$((M / 1024)),$(((M % 1024) * 10 / 1024)) Gio"
    else
        echo "${M} Mio"
    fi
}

blk_of_dev()
{
    ls -1d "$1"/block/mmcblk* "$1"/device/block/mmcblk* 2>/dev/null | head -n 1
}

sec_hosts()
{
    echo ""
    echo "--- [1] Controleurs mmc ---"
    ANY=0
    for H in /sys/class/mmc_host/mmc*; do
        [ -d "$H" ] || continue
        ANY=1
        HN="$(basename "$H")"
        FOUND=""
        for D in "$H"/mmc*:0001; do
            [ -d "$D" ] || continue
            FOUND=1
            DN="$(basename "$D")"
            TYPE="$(dev_file "$D" type | tr -d '\r')"
            NAME="$(dev_file "$D" name | tr -d '\r')"
            INFO="${TYPE:-?}${NAME:+ ($NAME)}"
            BLK="$(blk_of_dev "$D")"
            if [ -n "$BLK" ]; then
                SZ="$(cat "$BLK/size" 2>/dev/null | tr -dc '0-9')"
                INFO="$INFO $(human_size "$SZ") $(basename "$BLK")"
            fi
            printf '      %-10s %-12s %s\n' "$HN" "$DN" "$INFO"
        done
        [ -n "$FOUND" ] || printf '      %-10s %-12s %s\n' "$HN" "-" "aucune carte"
    done
    [ "$ANY" -eq 0 ] && info "controleurs" "aucun host mmc expose"
}

find_sd_dev()
{
    for D in /sys/class/mmc_host/mmc*/mmc*:0001; do
        [ -d "$D" ] || continue
        T="$(dev_file "$D" type | tr -d '\r')"
        [ "$T" = "SD" ] && { echo "$D"; return 0; }
    done
    return 1
}

sec_sd_card()
{
    echo ""
    echo "--- [2] Carte SD ---"
    D="$(find_sd_dev)" || { info "carte SD" "absente ou non enumeree par le noyau"; return 1; }
    NAME="$(dev_file "$D" name | tr -d '\r')"
    OID="$(dev_file "$D" oemid | tr -d '\r')"
    DT="$(dev_file "$D" date | tr -d '\r')"
    SCR="$(dev_file "$D" scr | head -n 1 | tr -d '\r')"
    ok "carte SD vue" "${NAME:-?} / OEM ${OID:-?} / ${DT:-?}"
    [ -n "$SCR" ] && info "scr" "$SCR"
    BLK="$(blk_of_dev "$D")"
    if [ -n "$BLK" ]; then
        SZ="$(cat "$BLK/size" 2>/dev/null | tr -dc '0-9')"
        info "peripherique" "$(basename "$BLK") $(human_size "$SZ")"
        PARTS="$(ls -1 "$BLK"/"${BLK##*/}"p* 2>/dev/null | wc -l)"
        case "$PARTS" in
            ''|0) warn "partitions" "aucune partition detectee (carte brute ?)" ;;
            *)    info "partitions" "$PARTS" ;;
        esac
    fi
    return 0
}

sec_mounts()
{
    echo ""
    echo "--- [3] Montage / vold ---"
    MNTS="$(grep -E 'mmcblk[0-9]+p?[0-9]*' /proc/mounts 2>/dev/null | grep -vE 'mmcblk[0-9]+(p[0-9]+)? .*(ext4) ' | grep -iE 'vfat|exfat|fuse|sdcardfs|ntfs' )"
    # montage eMMC exclu : ne garder que ce qui n'est pas le boot principal ext4
    SD_MNTS="$(grep -E 'mmcblk[0-9]+' /proc/mounts 2>/dev/null | grep -viE 'ext4' )"
    if [ -n "$SD_MNTS" ]; then
        printf '%s\n' "$SD_MNTS" | while IFS= read -r L; do
            info "monte" "$(printf '%s' "$L" | awk '{print $2" ("$3")"}')"
        done
    else
        D="$(find_sd_dev)"
        if [ -n "$D" ]; then
            warn "montage" "carte vue par le noyau mais rien de monte -> stade vold/format"
        else
            info "montage" "sans objet (pas de carte)"
        fi
    fi

    PS="$(ps 2>/dev/null | grep -c '[s]dcard')"
    [ -n "$PS" ] && info "daemons sdcard" "$PS instance(s)"

    if [ -d /data/misc/vold/expand ]; then
        ko "adoption vold" "/data/misc/vold/expand present (metadonnees stockage adopte)"
    else
        ok "adoption vold" "absente (bon point)"
    fi
}

sec_last_boot()
{
    echo ""
    echo "--- [4] Traces du precedent demarrage (pstore) ---"
    PSTORE=""
    for F in /sys/fs/pstore/console-ramoops* /sys/fs/pstore/dmesg-ramoops* /proc/last_kmsg; do
        [ -f "$F" ] && PSTORE="$PSTORE $F"
    done
    if [ -z "$PSTORE" ]; then
        info "pstore" "non expose par ce noyau (preuve apres boot impossible)"
        return 1
    fi
    for F in $PSTORE; do
        N="$(wc -l < "$F" 2>/dev/null | tr -dc '0-9')"
        info "$(basename "$F")" "${N:-?} lignes"
    done
    ERRS="$(grep -ihE 'mmc[0-9]|sdhci' $PSTORE 2>/dev/null | grep -icE 'timeout|crc|error|fail')"
    case "$ERRS" in
        ''|0)
            ok "erreurs mmc pstore" "aucune trace d'erreur mmc du boot precedent"
            ;;
        *)
            ko "erreurs mmc pstore" "$ERRS ligne(s) timeout/crc/error -> driver/carte"
            echo ""
            echo "      extrait :"
            grep -ihE 'mmc[0-9]|sdhci' $PSTORE 2>/dev/null | \
                grep -iE 'timeout|crc|error|fail' | tail -n 8 | sed 's/^/        /'
            ;;
    esac
    return 0
}

sec_verdict()
{
    echo ""
    echo "--- [5] Verdict / pistes ---"
    D="$(find_sd_dev)"
    if [ -z "$D" ]; then
        info "etat" "pas de carte visible maintenant"
        echo "      si la box vient de bloquer au boot avec la carte inseree :"
        echo "      A) bloquage logo/LED (avant noyau)   -> loader : voir TROUBLESHOOTING"
        echo "         (reflash loader via RKDevTool, ou autre carte FAT32 MBR)"
        echo "      B) redemarrer sans la carte puis relancer sd_inspect DMESG"
        echo "         et re-inserer a chaud pour capturer les erreurs en direct"
    else
        MNT="$(grep -E 'mmcblk[0-9]+' /proc/mounts 2>/dev/null | grep -viE 'ext4' | head -n 1)"
        if [ -n "$MNT" ]; then
            ok "utilisation" "carte montee et utilisable"
        else
            echo "      carte vue mais non montee :"
            echo "      - formater en FAT32, MBR, une seule partition primaire,"
            echo "        sans flag boot (depuis le PC)"
            echo "      - retester insertion a chaud + sd_inspect DMESG"
        fi
    fi
    echo ""
}

do_status()
{
    echo ""
    echo "=== SD INSPECT $(date '+%Y-%m-%d %H:%M:%S') ==="

    sec_hosts
    sec_sd_card
    sec_mounts
    sec_last_boot
    sec_verdict

    echo "--- Bilan ---"
    printf '  OK:%s  WARN:%s  KO:%s\n' "$OK" "$WARN" "$KO"
    echo ""

    [ "$KO" -eq 0 ] || return 2
    [ "$WARN" -eq 0 ] || return 1
    return 0
}

do_dmesg()
{
    echo ""
    echo "=== SD INSPECT DMESG (live) ==="
    echo ""
    OUT="$(dmesg 2>/dev/null | grep -iE 'mmc[0-9]|sdhci' | tail -n 40)"
    if [ -z "$OUT" ]; then
        info "dmesg" "aucune ligne mmc/sdhci (ou dmesg inaccessible)"
    else
        printf '%s\n' "$OUT" | sed 's/^/  /'
    fi
    echo ""
    return 0
}

case "$1" in
    ""|STATUS|status)       do_status ;;
    DMESG|dmesg)            do_dmesg ;;
    HELP|help|-h|--help)    usage ;;
    *)                      usage; exit 1 ;;
esac
exit "$?"
