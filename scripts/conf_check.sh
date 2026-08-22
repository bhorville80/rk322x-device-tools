#!/system/bin/sh
# conf_check - validation de la configuration (config/device.conf
# + overlay config/profiles/<PROFILE>.conf + secrets.conf).
#
# Controles :
#   [1] cles requises presentes et non vides
#   [2] formats : IP / netmask / gateway / DNS, PREFIX, ports, RAM_MB
#   [3] valeurs autorisees : NETWORK, SSH_MODE, WIRELESS_AIRPLANE
#   [4] overlay du profil present si PROFILE renseigne
#   [5] cles inconnues -> simple avertissement
#
# rc = 0 si tout est conforme, 1 sinon.

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

ZM="$(gv MEM_ZRAM_MB)"
case "$ZM" in "") ok "MEM_ZRAM_MB = <vide, defaut 512>" ;; *) is_num "$ZM" && ok "MEM_ZRAM_MB = $ZM" || ko "MEM_ZRAM_MB '$ZM' (attendu : Mo, nombre)" ;; esac

SWV="$(gv MEM_SWAPPINESS)"
case "$SWV" in "") ok "MEM_SWAPPINESS = <vide, defaut 100>" ;; *) is_num "$SWV" && [ "$SWV" -le 200 ] && ok "MEM_SWAPPINESS = $SWV" || ko "MEM_SWAPPINESS '$SWV' (attendu : 0..200)" ;; esac

LE="$(gv MEM_LMK_EARLY)"
case "$LE" in ""|0|1) ok "MEM_LMK_EARLY = ${LE:-<vide, defaut 0>}" ;; *) ko "MEM_LMK_EARLY '$LE' (attendu : 0|1)" ;; esac

LG="$(gv LOGD_SIZE_KB)"
case "$LG" in "") ok "LOGD_SIZE_KB = <vide, defaut 256>" ;; *) is_num "$LG" && { [ "$LG" -eq 0 ] || { [ "$LG" -ge 64 ] && [ "$LG" -le 4096 ]; } } && ok "LOGD_SIZE_KB = $LG" || ko "LOGD_SIZE_KB '$LG' (attendu : 0 ou 64..4096)" ;; esac

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
