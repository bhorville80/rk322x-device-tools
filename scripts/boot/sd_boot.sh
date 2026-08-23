#!/system/bin/sh
# sd_boot - carte SD examinee EN DERNIER lieu au demarrage.
#
# Contexte : une carte SD presente a la mise sous tension peut bloquer ou
# retarder le boot rk322x (cf TROUBLESHOOTING "SD CARD / BOOT BLOCKED").
# Ce tool est appele par boot.sh APRES la fin complete du boot (reseau,
# serveurs, mem_tune...) : il attend l'enumeration de la carte, la monte
# si elle est vue par le noyau mais pas montee (seul cas corrigeable en
# software) et trace un diagnostic exploitable en analyse retour.
#
# LIMITE : si le blocage a lieu AVANT init (logo fige, stade loader ou
# driver), aucun software ne peut intervenir -> remediation materielle :
# format FAT32/MBR sans flag boot, ou carte SDHC classe 10 sans UHS.
#
#   sd_boot                 etat : enumeration, montage, config
#   sd_boot STATUS          idem
#   sd_boot CHECK           mode boot : attente enumeration + montage + trace
#   sd_boot MOUNT [ro|rw]   monte la carte sur /mnt/media_rw/sdcard1
#   sd_boot UNMOUNT         demonter proprement
#   sd_boot HELP            cette aide
#
# Config (device.conf) :
#   BOOT_SD_LAST=1     boot.sh lance sd_boot CHECK en toute fin de boot
#   SD_MOUNT_RO=0      1 = monter la carte en lecture seule
#   SD_WAIT_SEC=15     attente max d'enumeration au boot (secondes)

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" "$(dirname "$0")/.." /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

for B in "$(dirname "$0")" "$(dirname "$0")/.." /data/scripts; do
    if [ -f "$B/core/config.sh" ]; then
        . "$B/core/config.sh"
        break
    fi
done

command -v config_get >/dev/null 2>&1 || config_get() { echo "$2"; }
command -v is_root >/dev/null 2>&1 || is_root() { case "$(id -u 2>/dev/null)" in 0) return 0 ;; esac; case "$(id 2>/dev/null)" in "uid=0("*) return 0 ;; esac; return 1; }

MNT="/mnt/media_rw/sdcard1"

# ---- detection ---------------------------------------------------------
# eMMC = mmcblk0 ; la carte SD apparait en mmcblk1 (host mmc1, type SD)

sd_host()
{
    # host mmc portant une carte SD (sinon fallback mmc1 historique)
    for H in /sys/class/mmc_host/mmc*; do
        [ -d "$H" ] || continue
        BASE_H="$(basename "$H")"
        for T in "$H"/"$BASE_H":*/type; do
            [ -f "$T" ] || continue
            if [ "$(cat "$T" 2>/dev/null)" = "SD" ]; then
                printf '%s' "$BASE_H"
                return 0
            fi
        done
    done
    [ -e /dev/block/mmcblk1 ] && { printf '%s' "mmc1"; return 0; }
    return 1
}

sd_host_dev()
{
    H="$(sd_host)" || return 1
    N="${H#mmc}"
    case "$N" in ''|*[!0-9]*) return 1 ;; esac
    [ -e "/dev/block/mmcblk$N" ] && { printf '%s' "/dev/block/mmcblk$N"; return 0; }
    return 1
}

sd_partition()
{
    D="$(sd_host_dev)" || return 1
    if [ -e "${D}p1" ]; then
        printf '%s' "${D}p1"
    elif [ -e "$D" ]; then
        printf '%s' "$D"
    else
        return 1
    fi
}

is_mounted()
{
    D="$(sd_host_dev)" || return 1
    grep -q "$D" /proc/mounts 2>/dev/null
}

wait_card()
{
    # $1 timeout secondes ; 0 = carte presente des maintenant
    W="$1"
    case "$W" in ''|*[!0-9]*) W=15 ;; esac
    I=0
    while [ "$I" -le "$W" ]; do
        if sd_host > /dev/null 2>&1 && [ -n "$(sd_partition 2>/dev/null)" ]; then
            return 0
        fi
        sleep 1
        I=$((I+1))
    done
    return 1
}

# ---- actions -----------------------------------------------------------

do_status()
{
    echo ""
    echo "=== SD BOOT STATUS ==="

    H="$(sd_host 2>/dev/null)"
    if [ -z "$H" ]; then
        echo "  Carte SD       : aucune enumeree"
    else
        P="$(sd_partition 2>/dev/null)"
        SZ=""
        [ -n "$P" ] && SZ="$(cat /sys/block/*/$(basename "$P")/size 2>/dev/null | head -n 1)"
        echo "  Carte SD       : presente (host $H${P:+, $P}${SZ:+, $((SZ / 2048)) Mo})"
        if is_mounted; then
            MP="$(grep "^$(sd_host_dev)" /proc/mounts 2>/dev/null | head -n 1 | cut -d' ' -f2)"
            echo "  Montage        : $MP"
        else
            echo "  Montage        : non montee"
        fi
    fi

    printf '  %-16s : %s\n' "BOOT_SD_LAST" "$(config_get BOOT_SD_LAST "")"
    printf '  %-16s : %s\n' "SD_MOUNT_RO"    "$(config_get SD_MOUNT_RO "")"
    printf '  %-16s : %s\n' "SD_WAIT_SEC"    "$(config_get SD_WAIT_SEC 15)"
    echo ""
    return 0
}

do_mount()
{
    MODE="${1:-}"
    if [ -z "$MODE" ]; then
        case "$(config_get SD_MOUNT_RO 0)" in 1) MODE="ro" ;; *) MODE="rw" ;; esac
    fi
    case "$MODE" in ro|rw) ;; *) echo "[ERREUR] mode attendu : ro|rw ('$MODE')"; return 1 ;; esac

    if ! is_root; then
        echo "[ERREUR] privileges root requis : su -c \"sh $0 MOUNT $MODE\""
        return 1
    fi

    if is_mounted; then
        echo "[ -- ] deja montee ($(grep "^$(sd_host_dev)" /proc/mounts 2>/dev/null | head -n 1 | cut -d' ' -f2))"
        return 0
    fi

    P="$(sd_partition)" || { echo "[ERREUR] aucune partition SD a monter"; return 1; }
    mkdir -p "$MNT" 2>/dev/null

    # vfat d'abord (cas standard), montage generique ensuite
    if mount -t vfat -o "${MODE},noatime,uid=1023,gid=1023,fmask=0007,dmask=0007" "$P" "$MNT" 2>/dev/null \
       || mount -o "${MODE}" "$P" "$MNT" 2>/dev/null; then
        echo "[ OK ] $(basename "$P") -> $MNT ($MODE)"
        return 0
    fi
    echo "[ ERREUR ] montage de $P impossible (fs non supporte ? essayer sd_inspect)"
    return 1
}

do_unmount()
{
    if ! is_root; then
        echo "[ERREUR] privileges root requis : su -c \"sh $0 UNMOUNT\""
        return 1
    fi
    if ! is_mounted; then
        echo "[ -- ] rien de monte"
        return 0
    fi
    P="$(sd_partition)"
    if umount "$MNT" 2>/dev/null || umount "$P" 2>/dev/null; then
        echo "[ OK ] $MNT demonte"
        return 0
    fi
    echo "[ ERREUR ] demontage impossible (fichier ouvert ?)"
    return 1
}

do_check()
{
    W="$(config_get SD_WAIT_SEC 15)"

    echo "--- [SD] examen en fin de boot ---"

    if wait_card "$W"; then
        H="$(sd_host 2>/dev/null)"
        P="$(sd_partition 2>/dev/null)"
        echo "  carte enumeree : ${P:-host $H}"

        if is_mounted; then
            echo "  [ OK ] deja montee par le systeme"
            return 0
        fi

        # vue par le noyau mais pas montee : cas corrigeable en software
        if do_mount; then
            echo "  [ OK ] montee tardive -> $MNT"
            return 0
        fi
        echo "  [ KO ] carte vue mais montage impossible (cf sd_inspect)"
        return 1
    fi

    echo "  [ -- ] aucune carte SD enumeree (${W}s) - normal sans carte"
    return 0
}

usage()
{
    echo ""
    echo "Usage: sd_boot <STATUS|CHECK|MOUNT [ro|rw]|UNMOUNT|HELP>"
    echo ""
    echo "  STATUS          carte enumeree ? montee ? config active"
    echo "  CHECK           mode boot : attente enumeration puis montage"
    echo "                  (lance automatiquement en FIN de boot si BOOT_SD_LAST=1)"
    echo "  MOUNT [ro|rw]   montage manuel (defaut selon SD_MOUNT_RO)"
    echo "  UNMOUNT         demontage propre"
    echo ""
    echo "Rappel : ce tool agit APRES la fin du boot. Un blocage au logo"
    echo "(stade loader/driver) se regle cote carte : FAT32/MBR sans flag boot."
    echo ""
    return 0
}

main()
{
    case "$1" in
        ""|STATUS|status)    do_status ;;
        CHECK|check)         do_check ;;
        MOUNT|mount)         shift; do_mount "$@" ;;
        UNMOUNT|unmount)     do_unmount ;;
        HELP|help|-h|--help) usage ;;
        *)                   usage ;;
    esac
}

if [ "$RUNLOG_LOADED" -eq 1 ] && runlog_start "$SCRIPT_ID"; then
    main "$@" >> "$RUNLOG_FILE" 2>&1
    RC=$?
    runlog_end "$RC"
    cat "$RUNLOG_FILE"
else
    main "$@"
    RC=$?
fi
exit "$RC"
