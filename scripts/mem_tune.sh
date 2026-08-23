#!/system/bin/sh
# mem_tune - optimisation memoire de la box (24/7 headless).
#
#   mem_tune                 etat courant (lecture seule)
#   mem_tune STATUS          idem
#   mem_tune OPTIMIZE        applique le profil optimise :
#                              - zram (swap compresse en RAM) si kernel expose
#                              - vm.swappiness adapte au zram
#                              - seuils lowmemorykiller plus reactifs (option)
#                              - buffers logd reduits (usure eMMC)
#                            premier passage : valeurs d'origine sauvegardees
#   mem_tune RESTORE         remet les valeurs d'origine
#   mem_tune HELP            cette aide
#
# Pilotage (config/device.conf) :
#   MEM_ZRAM_MB=512      taille du swap compresse (0 = laisse tel quel)
#   MEM_SWAPPINESS=100   tendance au swap avec zram (0..200)
#   MEM_LMK_EARLY=1      minfree x1.4 -> kills plus tot sous pression
#   LOGD_SIZE_KB=256     taille buffers logcat (0 = defaut firmware)
#
# NOTE : zram/lmk/sysctl ne survivent pas au reboot -> relancer OPTIMIZE
# apres demarrage (ou futur watchdog de supervision).

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

for B in "$(dirname "$0")" "$(dirname "$0")/../scripts" /data/scripts; do
    if [ -f "$B/core/config.sh" ]; then
        . "$B/core/config.sh"
        break
    fi
done

LMKP="/sys/module/lowmemorykiller/parameters"
ORIG="/data/etc/mem_tune.orig"

command -v config_get >/dev/null 2>&1 || config_get() { echo "$2"; }
command -v is_root >/dev/null 2>&1 || is_root() { case "$(id -u 2>/dev/null)" in 0) return 0 ;; esac; case "$(id 2>/dev/null)" in "uid=0("*) return 0 ;; esac; return 1; }

sec()  { echo ""; echo "--- [$1] $2 ---"; }
row()  { printf '  %-24s %s\n' "$1" "$2"; }
ok()   { printf '  [ OK ] %s\n' "$1"; }
warn() { printf '  [WARN] %s\n' "$1"; }
err()  { printf '  [ERREUR] %s\n' "$1"; }

is_num()
{
    case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac
}

zram_ready()
{
    [ -e /sys/block/zram0 ] && return 0
    [ -b /dev/zram0 ] && return 0
    return 1
}

try_load_zram()
{
    zram_ready && return 0

    command -v modprobe >/dev/null 2>&1 && modprobe zram 2>/dev/null
    zram_ready && return 0

    if command -v busybox >/dev/null 2>&1; then
        busybox modprobe zram 2>/dev/null
        zram_ready && return 0
    fi

    for M in /system/lib/modules/zram.ko /vendor/lib/modules/zram.ko \
             /system/lib/modules/zram_cfg.ko; do
        [ -f "$M" ] || continue
        insmod "$M" 2>/dev/null
        zram_ready && return 0
    done

    return 1
}

zram_active()
{
    grep -q zram0 /proc/swaps 2>/dev/null
}

save_orig()
{
    [ -f "$ORIG" ] && return 0
    mkdir -p "$(dirname "$ORIG")" 2>/dev/null

    {
        echo "swappiness=$(cat /proc/sys/vm/swappiness 2>/dev/null)"
        echo "minfree=$(cat "$LMKP/minfree" 2>/dev/null)"
        echo "logd_kb="
    } > "$ORIG" 2>/dev/null
}

scale_minfree()
{
    # $1 facteur x100 (ex : 140 = +40%) -> minfree recalcule
    F="$1"
    IN="$(cat "$LMKP/minfree" 2>/dev/null)"
    case "$IN" in
        *,*) ;;
        *) return 1 ;;
    esac

    OUT=""
    OLDIFS="$(printf '%s' "$IFS")"
    IFS=','
    set -- $IN
    IFS="$OLDIFS"
    for V in "$@"; do
        is_num "$V" || return 1
        NV=$((V * F / 100))
        OUT="${OUT:+$OUT,}$NV"
    done
    [ -n "$OUT" ] || return 1
    echo "$OUT" > "$LMKP/minfree" 2>/dev/null || return 1
    return 0
}

do_status()
{
    echo ""
    echo "=== MEM TUNE ==="

    MT="$(sed -n 's/^MemTotal: *\([0-9]*\) kB/\1/p' /proc/meminfo 2>/dev/null | head -n 1)"
    MA="$(sed -n 's/^MemAvailable: *\([0-9]*\) kB/\1/p' /proc/meminfo 2>/dev/null | head -n 1)"

    sec 1 "RAM"
    if is_num "$MT"; then
        row total "$((MT / 1024)) Mo"
        if is_num "$MA"; then
            row disponible "$((MA / 1024)) Mo ($((MA * 100 / MT))%)"
        fi
    else
        row total "illisible"
    fi

    sec 2 "zram / swap"
    if zram_active; then
        ZS="$(cat /sys/block/zram0/disksize 2>/dev/null)"
        row zram0 "ACTIF${ZS:+ ($((ZS / 1048576)) Mo compresses)}"
        grep zram0 /proc/swaps 2>/dev/null | sed 's/^/    /'
    elif zram_ready; then
        row zram0 "present mais inactif"
    else
        row zram0 "non expose par ce kernel"
    fi
    SWAPS="$(sed -n '2,$p' /proc/swaps 2>/dev/null | grep -cv '^$')"
    row "autres swaps" "${SWAPS:-0}"

    sec 3 "VM tunables"
    row swappiness "$(cat /proc/sys/vm/swappiness 2>/dev/null)"
    row vfs_cache_pressure "$(cat /proc/sys/vm/vfs_cache_pressure 2>/dev/null)"

    sec 4 "lowmemorykiller"
    MF="$(cat "$LMKP/minfree" 2>/dev/null)"
    MA_="$(cat "$LMKP/min_adj" 2>/dev/null)"
    row minfree "${MF:-absent}"
    row min_adj "${MA_:-(built-in)}"

    sec 5 "logd (buffers logcat)"
    row "logcat -g" "$(logcat -g 2>/dev/null | tr '\n' ' ')"
    row persist.logd.size "$(getprop persist.logd.size 2>/dev/null)"

    sec 6 "Profil cible (device.conf)"
    row MEM_ZRAM_MB "$(config_get MEM_ZRAM_MB 512) Mo"
    row MEM_SWAPPINESS "$(config_get MEM_SWAPPINESS 100)"
    row MEM_LMK_EARLY "$(config_get MEM_LMK_EARLY 0)"
    row LOGD_SIZE_KB "$(config_get LOGD_SIZE_KB 256) Ko"

    if [ -f "$ORIG" ]; then
        echo ""
        ok "profil applique (origine sauvegardee dans $ORIG)"
    else
        echo ""
        warn "profil non applique (valeurs d'origine actives)"
    fi

    echo ""
    return 0
}

do_optimize()
{
    echo ""
    echo "=== MEM TUNE - OPTIMIZE ==="

    if ! is_root; then
        err "privileges root requis (su -c \"sh $0 OPTIMIZE\")"
        return 1
    fi

    save_orig
    RC=0

    ZMB="$(config_get MEM_ZRAM_MB 512)"
    if [ "$ZMB" != "0" ] && is_num "$ZMB"; then
        echo "[1] zram (${ZMB} Mo)..."
        if zram_active; then
            ok "deja actif"
        elif ! try_load_zram; then
            warn "module zram indisponible sur ce kernel (pas de swap compresse)"
        else
            echo "$((ZMB * 1024 * 1024))" > /sys/block/zram0/disksize 2>/dev/null
            if busybox mkswap /dev/zram0 > /dev/null 2>&1 \
               && busybox swapon -p 10 /dev/zram0 > /dev/null 2>&1; then
                ok "zram0 actif (${ZMB} Mo, prio 10)"
            else
                err "activation zram impossible (mkswap/swapon)"
                RC=1
            fi
        fi
    fi

    SW="$(config_get MEM_SWAPPINESS 100)"
    if is_num "$SW"; then
        echo "[2] vm.swappiness = $SW..."
        if echo "$SW" > /proc/sys/vm/swappiness 2>/dev/null; then
            ok "applique"
        else
            warn "/proc/sys/vm/swappiness non inscriptible"
        fi
    fi

    case "$(config_get MEM_LMK_EARLY 0)" in
        1)
            echo "[3] lowmemorykiller (minfree x1.4)..."
            if [ ! -w "$LMKP/minfree" ]; then
                warn "lowmemorykiller non expose"
            elif scale_minfree 140; then
                ok "minfree = $(cat "$LMKP/minfree" 2>/dev/null)"
            else
                err "recalcul minfree impossible"
                RC=1
            fi
            ;;
        *)
            echo "[3] lowmemorykiller : inchange (MEM_LMK_EARLY=0)"
            ;;
    esac

    LK="$(config_get LOGD_SIZE_KB 256)"
    if is_num "$LK" && [ "$LK" -ge 64 ] && [ "$LK" -le 4096 ]; then
        echo "[4] buffers logd = ${LK} Ko..."
        if logcat -G "${LK}K" > /dev/null 2>&1; then
            setprop persist.logd.size "${LK}K" 2>/dev/null
            ok "applique (+ persist.logd.size)"
        else
            warn "logcat -G refuse (logd ?)"
        fi
    fi

    echo ""
    if [ "$RC" -eq 0 ]; then
        echo "[ OK ] profil optimise applique"
        echo "       (volatile : relancer apres chaque reboot)"
    else
        echo "[ ERREUR ] profil partiellement applique (voir ci-dessus)"
    fi
    echo ""
    return $RC
}

do_restore()
{
    echo ""
    echo "=== MEM TUNE - RESTORE ==="

    if ! is_root; then
        err "privileges root requis (su -c \"sh $0 RESTORE\")"
        return 1
    fi

    if [ ! -f "$ORIG" ]; then
        warn "aucune sauvegarde ($ORIG absent) - rien a restaurer"
        return 0
    fi

    OS="$(sed -n 's/^swappiness=//p' "$ORIG")"
    OM="$(sed -n 's/^minfree=//p' "$ORIG")"
    OL="$(sed -n 's/^logd_kb=//p' "$ORIG")"

    if [ -n "$OS" ] && is_num "$OS"; then
        echo "$OS" > /proc/sys/vm/swappiness 2>/dev/null \
            && ok "swappiness = $OS" || warn "swappiness non restaure"
    fi

    if [ -n "$OM" ] && [ -w "$LMKP/minfree" ]; then
        echo "$OM" > "$LMKP/minfree" 2>/dev/null \
            && ok "minfree restaure" || warn "minfree non restaure"
    fi

    if zram_active; then
        busybox swapoff /dev/zram0 > /dev/null 2>&1
        echo 1 > /sys/block/zram0/reset 2>/dev/null
        zram_active && err "zram0 toujours actif" || ok "zram0 desactive"
    fi

    if is_num "$OL" && [ "$OL" -gt 0 ]; then
        logcat -G "${OL}K" > /dev/null 2>&1 && ok "buffers logd = ${OL} Ko"
    fi

    rm -f "$ORIG"
    echo ""
    echo "[ OK ] valeurs d'origine restaurees"
    echo ""
    return 0
}

case "$1" in
    ""|STATUS|status) do_status ;;
    OPTIMIZE|optimize|ON|on)  do_optimize ;;
    RESTORE|restore|OFF|off)  do_restore ;;
    HELP|help|-h|--help)
        sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    *)
        echo "Usage: mem_tune [STATUS|OPTIMIZE|RESTORE|help]"
        exit 1
        ;;
esac
