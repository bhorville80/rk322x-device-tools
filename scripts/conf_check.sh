#!/system/bin/sh
# conf_check - validation de la configuration (config/device.conf
# + overlay config/profiles/<PROFILE>.conf + secrets.conf).
#
# Controles :
#   [1] cles requises presentes et non vides
#   [2] formats : IP / netmask / gateway / DNS, PREFIX, ports, RAM_MB
#   [3] valeurs autorisees : NETWORK, SSH_MODE, WIRELESS_AIRPLANE, memoire
#   [4] overlay du profil present si PROFILE renseigne
#   [5] cles inconnues -> simple avertissement
#   [6] application effective des optimisations memoire (mem_tune) :
#       cible configuree vs etat reellement actif sur la box
#
# rc = 0 si la configuration est conforme, 1 sinon
# (la section [6] est informative : elle ne fait pas echouer le check).

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

CONF_DIR=""
CONFIG_FILE=""
PROFILE_FILE=""
SECRETS_FILE=""

for D_ in "$(dirname "$0")/../config" /data/scripts/config; do
    if [ -f "$D_/device.conf" ]; then
        CONF_DIR="$(cd "$D_" && pwd)"
        break
    fi
done
[ -n "$CONF_DIR" ] && CONFIG_FILE="$CONF_DIR/device.conf"
[ -n "$CONF_DIR" ] && [ -f "$CONF_DIR/secrets.conf" ] && SECRETS_FILE="$CONF_DIR/secrets.conf"

KO_N=0
WARN_N=0

ok()  { printf '  [ OK ] %s\n' "$1"; }
warn(){ printf '  [WARN] %s\n' "$1"; WARN_N=$((WARN_N+1)); }
ko()  { printf '  [ KO ] %s\n' "$1"; KO_N=$((KO_N+1)); }

cfg_get()
{
    F="$1"; K="$2"
    [ -n "$F" ] && [ -f "$F" ] || return 0
    sed -n "s/^${K}=//p" "$F" 2>/dev/null | head -n 1 | tr -d '\r'
}

is_num()
{
    case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac
}

is_ip()
{
    [ "$(printf '%s' "$1" | tr -dc '.')" = "..." ] || return 1
    O1="$(echo "$1" | cut -d. -f1)"
    O2="$(echo "$1" | cut -d. -f2)"
    O3="$(echo "$1" | cut -d. -f3)"
    O4="$(echo "$1" | cut -d. -f4)"
    is_num "$O1" && is_num "$O2" && is_num "$O3" && is_num "$O4" || return 1
    [ "$O1" -le 255 ] && [ "$O2" -le 255 ] && [ "$O3" -le 255 ] && [ "$O4" -le 255 ]
}

main()
{

echo ""
echo "=== CONF CHECK ==="

if [ ! -f "$CONFIG_FILE" ]; then
    ko "config introuvable ($CONFIG_FILE)"
    echo ""
    return 1
fi
echo "[0] Source : $CONFIG_FILE"
if [ -n "$PROFILE_FILE" ]; then
    echo "    Overlay profil : $PROFILE_FILE"
fi
[ -n "$SECRETS_FILE" ] && echo "    Secrets : $SECRETS_FILE (non diffuse)"

gv()
{
    V="$(cfg_get "$PROFILE_FILE" "$1")"
    [ -z "$V" ] && V="$(cfg_get "$CONFIG_FILE" "$1")"
    [ -z "$V" ] && V="$(cfg_get "$SECRETS_FILE" "$1")"
    printf '%s' "$V"
}

echo ""
echo "[1] Cles requises"
for K in DEVICE_ID DEVICE_NAME INTERFACE IP DEPLOY_VERSION; do
    V="$(gv "$K")"
    if [ -n "$V" ]; then ok "$K = $V"; else ko "$K absent ou vide"; fi
done

echo ""
echo "[2] Formats"
IP="$(gv IP)"
case "$IP" in ''|*[!0-9.]*) ;; *) if is_ip "$IP"; then ok "IP format ($IP)"; else ko "IP invalide ('$IP')"; fi ;; esac

for K in NETMASK GATEWAY DNS; do
    V="$(gv "$K")"
    if [ -z "$V" ]; then
        warn "$K vide (defaut code applique)"
    elif is_ip "$V"; then
        ok "$K = $V"
    else
        ko "$K invalide ('$V')"
    fi
done

PFX="$(gv PREFIX)"
if [ -z "$PFX" ]; then
    warn "PREFIX vide (defaut 24)"
elif is_num "$PFX" && [ "$PFX" -ge 8 ] && [ "$PFX" -le 32 ]; then
    ok "PREFIX = $PFX"
else
    ko "PREFIX invalide ('$PFX', attendu 8..32)"
fi

SP="$(gv SSH_PORT)"
if [ -z "$SP" ]; then
    warn "SSH_PORT vide (defaut 2222)"
elif is_num "$SP" && [ "$SP" -ge 1 ] && [ "$SP" -le 65535 ]; then
    ok "SSH_PORT = $SP"
else
    ko "SSH_PORT invalide ('$SP')"
fi

AP="$(gv ADB_PORT)"
if [ -z "$AP" ]; then
    warn "ADB_PORT vide (defaut admin PC : 5555)"
elif is_num "$AP" && [ "$AP" -ge 1 ] && [ "$AP" -le 65535 ]; then
    ok "ADB_PORT = $AP"
else
    ko "ADB_PORT invalide ('$AP')"
fi

RM="$(gv RAM_MB)"
if [ -z "$RM" ]; then
    warn "RAM_MB vide"
elif is_num "$RM"; then
    ok "RAM_MB = $RM"
else
    ko "RAM_MB invalide ('$RM')"
fi

echo ""
echo "[3] Valeurs autorisees"
NW="$(gv NETWORK)"
case "$NW" in static|dhcp) ok "NETWORK = $NW" ;; *) ko "NETWORK '$NW' (attendu : static|dhcp)" ;; esac

SM="$(gv SSH_MODE)"
case "$SM" in keys|password|any|"") ok "SSH_MODE = ${SM:-<vide, defaut keys>}" ;; *) ko "SSH_MODE '$SM' (attendu : keys|password|any)" ;; esac

WA="$(gv WIRELESS_AIRPLANE)"
case "$WA" in 0|1|"") ok "WIRELESS_AIRPLANE = ${WA:-<vide, defaut 0>}" ;; *) ko "WIRELESS_AIRPLANE '$WA' (attendu : 0|1)" ;; esac

WR="$(gv WEB_RUN)"
case "$WR" in 0|1|"") ok "WEB_RUN = ${WR:-<vide, defaut 0>} (console panneau)" ;; *) ko "WEB_RUN '$WR' (attendu : 0|1)" ;; esac

ZM="$(gv MEM_ZRAM_MB)"
case "$ZM" in "") ok "MEM_ZRAM_MB = <vide, defaut 512>" ;; *) is_num "$ZM" && ok "MEM_ZRAM_MB = $ZM" || ko "MEM_ZRAM_MB '$ZM' (attendu : Mo, nombre)" ;; esac

SWV="$(gv MEM_SWAPPINESS)"
case "$SWV" in "") ok "MEM_SWAPPINESS = <vide, defaut 100>" ;; *) is_num "$SWV" && [ "$SWV" -le 200 ] && ok "MEM_SWAPPINESS = $SWV" || ko "MEM_SWAPPINESS '$SWV' (attendu : 0..200)" ;; esac

LE="$(gv MEM_LMK_EARLY)"
case "$LE" in ""|0|1) ok "MEM_LMK_EARLY = ${LE:-<vide, defaut 0>}" ;; *) ko "MEM_LMK_EARLY '$LE' (attendu : 0|1)" ;; esac

LG="$(gv LOGD_SIZE_KB)"
case "$LG" in "") ok "LOGD_SIZE_KB = <vide, defaut 256>" ;; *) is_num "$LG" && { [ "$LG" -eq 0 ] || { [ "$LG" -ge 64 ] && [ "$LG" -le 4096 ]; } } && ok "LOGD_SIZE_KB = $LG" || ko "LOGD_SIZE_KB '$LG' (attendu : 0 ou 64..4096)" ;; esac

for BK in BOOT_MEM_TUNE BOOT_CUT_SERVICES BOOT_SET_NETWORK BOOT_TIME_SYNC BOOT_EXPOSE BOOT_ROTATE_LOGS; do
    BV="$(gv "$BK")"
    case "$BV" in ""|0|1) ok "$BK = ${BV:-<vide, defaut 0>}" ;; *) ko "$BK '$BV' (attendu : 0|1)" ;; esac
done
BW="$(gv BOOT_WAIT_BOOT)"
if [ -z "$BW" ]; then
    warn "BOOT_WAIT_BOOT vide (defaut 120)"
elif is_num "$BW"; then
    ok "BOOT_WAIT_BOOT = $BW"
else
    ko "BOOT_WAIT_BOOT invalide ('$BW', attendu : secondes)"
fi

KW="$(gv BOOT_WAIT_KEY)"
case "$KW" in "") ok "BOOT_WAIT_KEY = <vide, defaut 150>" ;; *) is_num "$KW" && ok "BOOT_WAIT_KEY = $KW" || ko "BOOT_WAIT_KEY '$KW' (attendu : secondes)" ;; esac

RK="$(gv REMOTE_KL_DEVICE)"
if [ -z "$RK" ]; then
    warn "REMOTE_KL_DEVICE vide (device IR autodetecte)"
else
    case "$RK" in
        *[!a-zA-Z0-9_.-]*) ko "REMOTE_KL_DEVICE '$RK' (caracteres autorises : a-z A-Z 0-9 _ . -)" ;;
        *) ok "REMOTE_KL_DEVICE = $RK" ;;
    esac
fi

FF="$(gv FD_FORMAT)"
case "$FF" in ""|raw|hdr|full) ok "FD_FORMAT = ${FF:-<vide, PROBE a faire>}" ;; *) ko "FD_FORMAT '$FF' (attendu : raw|hdr|full)" ;; esac

FS="$(gv FD_ROTATE_SEC)"
if [ -z "$FS" ]; then
    warn "FD_ROTATE_SEC vide (defaut 5)"
elif is_num "$FS"; then
    ok "FD_ROTATE_SEC = $FS"
else
    ko "FD_ROTATE_SEC invalide ('$FS', attendu : secondes)"
fi

FI="$(gv FD_ROTATE_ITEMS)"
case "$FI" in
    "") ok "FD_ROTATE_ITEMS = <vide, defaut TIME IP>" ;;
    *)
        BAD=""
        for TOK in $FI; do
            case "$TOK" in
                TIME|IP|RAM|UP) ;;
                *) BAD="$BAD $TOK" ;;
            esac
        done
        if [ -z "$BAD" ]; then
            ok "FD_ROTATE_ITEMS = $FI"
        else
            ko "FD_ROTATE_ITEMS : items inconnus:$BAD (attendus : TIME IP RAM UP)"
        fi
        ;;
esac

BF="$(gv BOOT_FRONT_CLOCK)"
case "$BF" in ""|0|1) ok "BOOT_FRONT_CLOCK = ${BF:-<vide, defaut 0>}" ;; *) ko "BOOT_FRONT_CLOCK '$BF' (attendu : 0|1)" ;; esac

BS="$(gv BOOT_SD_LAST)"
case "$BS" in ""|0|1) ok "BOOT_SD_LAST = ${BS:-<vide, defaut 1>}" ;; *) ko "BOOT_SD_LAST '$BS' (attendu : 0|1)" ;; esac

SR="$(gv SD_MOUNT_RO)"
case "$SR" in ""|0|1) ok "SD_MOUNT_RO = ${SR:-<vide, defaut 0>}" ;; *) ko "SD_MOUNT_RO '$SR' (attendu : 0|1)" ;; esac

SW="$(gv SD_WAIT_SEC)"
case "$SW" in "") ok "SD_WAIT_SEC vide (defaut 15)" ;; *[!0-9]*) ko "SD_WAIT_SEC '$SW' (attendu : secondes)" ;; *) ok "SD_WAIT_SEC = $SW" ;; esac

echo ""
echo "[4] Profil"
PF="$(gv PROFILE)"
if [ -z "$PF" ]; then
    ok "PROFILE non defini (profil unique)"
else
    case "$PF" in
        *[!a-zA-Z0-9_-]*) ko "PROFILE '$PF' (caracteres autorises : a-z A-Z 0-9 _ -)" ;;
        *)
            if [ -f "$CONF_DIR/profiles/$PF.conf" ]; then
                ok "PROFILE = $PF (overlay present)"
            else
                ko "overlay absent : config/profiles/$PF.conf"
            fi
            ;;
    esac
fi

echo ""
echo "[5] Cles inconnues (avertissement seul)"
KNOWN="DEVICE_ID
DEVICE_NAME
PROFILE
RAM_MB
NETWORK
INTERFACE
ADB_PORT
DEPLOY_VERSION
PREFIX
NETMASK
IP
GATEWAY
DNS
HW_PLATFORM
HW_BOARD
HW_ANDROID
HW_SDK
HW_ABI
HW_PATCH
HW_BUILD
SERVICES_STOP
SERVICES_CUT
SERVICES_CUT_KEEP
PACKAGES_DISABLE
PACKAGES_DISABLE_KEEP
MEM_ZRAM_MB
MEM_SWAPPINESS
MEM_LMK_EARLY
LOGD_SIZE_KB
MEM_SWAP_DEV
MEM_SWAP_FILE
MEM_SWAP_MB
BOOT_MEM_TUNE
BOOT_CUT_SERVICES
BOOT_SET_NETWORK
BOOT_ROTATE_LOGS
BOOT_TIME_SYNC
BOOT_EXPOSE
BOOT_WAIT_BOOT
BOOT_FRONT_CLOCK
BOOT_SD_LAST
SD_MOUNT_RO
BOOT_WAIT_KEY
SD_WAIT_SEC
PANEL_PASS
PANEL_USER
API_MAX_CONN
WEB_RUN
FD_FORMAT
FD_ROTATE_SEC
FD_ROTATE_ITEMS
REMOTE_KL_DEVICE
SSH_PORT
SSH_MODE
SSH_BIN
SSH_PASSWORD
WIRELESS_AIRPLANE
"
UNK=""
for F_ in "$CONFIG_FILE" "$PROFILE_FILE" "$SECRETS_FILE"; do
    [ -n "$F_" ] && [ -f "$F_" ] || continue
    while IFS='=' read -r K _REST; do
        K="$(printf '%s' "$K" | tr -d '\r')"
        case "$K" in ''|\#*) continue ;; esac
        case "
$KNOWN" in
            *"
$K
"*) ;;
            *) UNK="$UNK $K ($(basename "$F_"))" ;;
        esac
    done < "$F_"
done
if [ -n "$UNK" ]; then
    warn "cles non reconnues :$UNK"
else
    ok "aucune cle inconnue"
fi

# ------------------------------------------------------------- [6] application
sec_num=6
echo ""
echo "[6] Application des optimisations (mem_tune)"
if [ ! -e /proc/swaps ] && [ ! -e /proc/sys/vm/swappiness ]; then
    warn "etat runtime disponible uniquement sur la box"
else
    APP_N=0 ; TOT_N=0

    ZM="$(gv MEM_ZRAM_MB)" ; case "$ZM" in '') ZM=512 ;; esac
    if [ "$ZM" = "0" ]; then
        printf '  [ N/A      ] %-26s cible=desactive\n' "zram (MEM_ZRAM_MB)"
    elif [ ! -e /sys/block/zram0 ] && [ ! -b /dev/zram0 ]; then
        printf '  [ N/A      ] %-26s zram absent du kernel\n' "zram (MEM_ZRAM_MB)"
    elif grep -q zram0 /proc/swaps 2>/dev/null; then
        printf '  [ APPLIQUE ] %-26s zram0 actif (%s Mo)\n' "zram (MEM_ZRAM_MB)" "$ZM"
        TOT_N=$((TOT_N+1))
        APP_N=$((APP_N+1))
    elif [ -f "/data/etc/mem_tune.zram_unavailable" ]; then
        # mem_tune OPTIMIZE a constate un backend compression casse :
        # limite firmware definitive, pas un oubli d'application
        printf '  [ INDISPON.] %-26s backend kernel casse (cf. mem_tune)\n' "zram (MEM_ZRAM_MB)"
    else
        TOT_N=$((TOT_N+1))
        printf '  [ PAS LANCE] %-26s cible=%s Mo\n' "zram (MEM_ZRAM_MB)" "$ZM"
    fi

    SWV="$(gv MEM_SWAPPINESS)" ; case "$SWV" in '') SWV=100 ;; esac
    TOT_N=$((TOT_N+1))
    CUR_SW="$(cat /proc/sys/vm/swappiness 2>/dev/null)"
    if [ "$CUR_SW" = "$SWV" ]; then
        printf '  [ APPLIQUE ] %-26s swappiness=%s\n' "vm tunable" "$SWV"
        APP_N=$((APP_N+1))
    else
        printf '  [ PAS LANCE] %-26s cible=%s actuel=%s\n' "vm tunable" "$SWV" "${CUR_SW:-?}"
    fi

    LE="$(gv MEM_LMK_EARLY)" ; case "$LE" in '') LE=0 ;; esac
    if [ "$LE" = "1" ]; then
        TOT_N=$((TOT_N+1))
        ORIG_F="/data/etc/mem_tune.orig"
        if [ -f "$ORIG_F" ] && [ -e /sys/module/lowmemorykiller/parameters/minfree ]; then
            printf '  [ APPLIQUE ] %-26s minfree modifie (origine sauvegardee)\n' "lmk early (MEM_LMK_EARLY)"
            APP_N=$((APP_N+1))
        else
            printf '  [ PAS LANCE] %-26s minfree d origine ou non sauvegarde\n' "lmk early (MEM_LMK_EARLY)"
        fi
    else
        printf '  [ N/A      ] %-26s cible=desactive\n' "lmk early (MEM_LMK_EARLY)"
    fi

    LG="$(gv LOGD_SIZE_KB)" ; case "$LG" in '') LG=256 ;; esac
    if is_num "$LG" && [ "$LG" -gt 0 ]; then
        TOT_N=$((TOT_N+1))
        CUR_LG="$(getprop persist.logd.size 2>/dev/null)"
        if [ "$CUR_LG" = "${LG}K" ] || logcat -g 2>/dev/null | grep -q "${LG}K"; then
            printf '  [ APPLIQUE ] %-26s buffers=%sK\n' "logd (LOGD_SIZE_KB)" "$LG"
            APP_N=$((APP_N+1))
        else
            printf '  [ PAS LANCE] %-26s cible=%sK actuel=%s\n' "logd (LOGD_SIZE_KB)" "$LG" "${CUR_LG:-defaut}"
        fi
    else
        printf '  [ N/A      ] %-26s cible=defaut firmware\n' "logd (LOGD_SIZE_KB)"
    fi

    echo ""
    if [ "$TOT_N" -eq 0 ]; then
        warn "rien a appliquer (toutes les optimisations desactivees)"
    elif [ "$APP_N" -eq "$TOT_N" ]; then
        ok "optimisations appliquees ($APP_N/$TOT_N)"
    else
        warn "$((TOT_N - APP_N)) optimisation(s) non lancee(s) sur $TOT_N -> mem_tune OPTIMIZE"
    fi
fi

echo ""
if [ "$KO_N" -eq 0 ]; then
    echo "[ OK ] configuration conforme${WARN_N:+ ($WARN_N avertissement(s))}"
    RC=0
else
    echo "[ ERREUR ] configuration invalide : $KO_N erreur(s), $WARN_N avertissement(s)"
    RC=1
fi
echo ""
return $RC
}

if [ "$RUNLOG_LOADED" -eq 1 ] && runlog_start "$SCRIPT_ID"; then
    main >> "$RUNLOG_FILE" 2>&1
    RC=$?
    runlog_end "$RC"
    cat "$RUNLOG_FILE"
else
    main
    RC=$?
fi
exit 0
