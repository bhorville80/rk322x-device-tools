#!/bin/sh
# admin/linux/provision.sh - provisionnement de la MXQ depuis un PC Linux
#
# Chaine complete, chaque etape est verifiee puis validee (avec --fix : corrige puis re-verifie) :
#   [0] reseau   : sous-reseau de la box joignable depuis le PC (--net pour l'ajouter), ping
#   [1] adb      : adb connect <ip>:5555 si necessaire
#   [2] root     : su -c id -u == 0 sur la box
#   [3] version  : /data/scripts/VERSION vs DEPLOY_VERSION (config/device.conf)
#   [4] config   : interface UP, IP statique, passerelle, DNS
#   [5] wireless : Wi-Fi et Bluetooth coupes
#   [6] horloge  : derive < 5 min (sinon remise a l'heure UTC du PC)
#   [7] hdmi     : etat framebuffer (informatif)
#
# Usage:
#   admin/linux/provision.sh [-t CIBLE] [check]      lecture seule : rapport OK/KO
#   admin/linux/provision.sh [-t CIBLE] --net --fix  + adresse PC + corrections
#
# Options:
#   -t CIBLE      cible adb (defaut : <IP>:5555 du profil device.conf)
#   --net         ajoute <sous-reseau>.1/24 au PC si absent (root ou sudo requis)
#   --fix         applique les corrections possibles puis re-valide
#   --skip-date   ne touche pas a l'horloge de la box
#   check|fix     mode global (fix equivaut a --fix)

set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
CONF="$REPO/config/device.conf"

say()  { echo "[prov] $*"; }
die()  { echo "[ERREUR prov] $*" >&2; exit 1; }
usage() { sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; }

TARGET=""
ACTION="check"
FIX=0
SETUP_NET=0
SKIP_DATE=0
ADB_PORT="5555"
PING_TRIES="4"

while [ $# -gt 0 ]; do
    case "$1" in
        -t|--target)  TARGET="${2:-}"; shift 2 ;;
        --net)        SETUP_NET=1; shift ;;
        --fix)        FIX=1; shift ;;
        --skip-date)  SKIP_DATE=1; shift ;;
        check)        ACTION="check"; shift ;;
        fix)          ACTION="fix"; FIX=1; shift ;;
        help|-h|--help) usage ; exit 0 ;;
        *)            die "option inconnue : $1 (voir admin/linux/provision.sh help)" ;;
    esac
done

# --- profil boitier ----------------------------------------------------------
cfg() { sed -n "s/^$1=//p" "$CONF" 2>/dev/null | head -n 1 | tr -d '\r'; }

DEVICE_NAME="$(cfg DEVICE_NAME)"; DEVICE_NAME="${DEVICE_NAME:-boitier}"
IFACE="$(cfg INTERFACE)";         IFACE="${IFACE:-eth0}"
BOX_IP="$(cfg IP)";               BOX_IP="${BOX_IP:-192.168.50.20}"
GW="$(cfg GATEWAY)";              GW="${GW:-192.168.50.1}"
DNS="$(cfg DNS)";                 DNS="${DNS:-$GW}"
VERSION_CFG="$(cfg DEPLOY_VERSION)"; VERSION_CFG="${VERSION_CFG:-?}"
SUBNET="$(echo "$BOX_IP" | cut -d. -f1-3)"
PREFIX="24"

PASS=0; KO=0; FIXED=0
ok()    { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()    { printf '  [ KO ] %-28s %s\n' "$1" "$2"; KO=$((KO+1)); }
fixed() { printf '  [FIX ] %-28s %s\n' "$1" "$2"; FIXED=$((FIXED+1)); PASS=$((PASS+1)); }
warn()  { printf '  [WARN] %-28s %s\n' "$1" "$2"; }
info()  { printf '  [ -- ] %s\n' "$1"; }

# --- helpers distants --------------------------------------------------------
command -v adb >/dev/null 2>&1 || die "adb introuvable dans le PATH"

if [ -n "$TARGET" ]; then
    adb_run() { adb -s "$TARGET" "$@"; }
else
    adb_run() { adb "$@"; }
fi

rget()
{
    adb_run shell "$1" 2>/dev/null | tr -d '\r'
}

rrun()
{
    adb_run shell "su -c '$1'" > /dev/null 2>&1
}

trim()
{
    printf '%s' "$1" | sed 's/^ *//;s/ *$//'
}

# === [0] RESEAU ==============================================================
stage_network()
{
    echo ""
    echo "--- [0] Reseau PC -> box ---"

    if ip -4 addr show 2>/dev/null | grep -q "inet $SUBNET\."; then
        ok "PC present sur $SUBNET.0/$PREFIX"
    else
        warn "PC hors sous-reseau" "$SUBNET.0/$PREFIX absent des interfaces"
        if [ "$SETUP_NET" = "1" ]; then
            IF_PC="$(ip -4 route show default 2>/dev/null | sed -n 's/.*dev \([^ ]*\).*/\1/p' | head -n 1)"
            [ -n "$IF_PC" ] || IF_PC="$(ip -o link 2>/dev/null | sed -n 's/^[0-9]*: \([^@]*\):.*/\1/p' | grep -v '^lo$' | head -n 1)"
            [ -n "$IF_PC" ] || die "interface reseau du PC introuvable"
            ADDR="$SUBNET.1/$PREFIX"
            if ip addr add "$ADDR" dev "$IF_PC" 2>/dev/null; then
                fixed "adresse PC" "$ADDR sur $IF_PC"
            elif sudo ip addr add "$ADDR" dev "$IF_PC"; then
                fixed "adresse PC" "$ADDR sur $IF_PC (sudo)"
            else
                ko "adresse PC" "echec ajout $ADDR sur $IF_PC (droits root ?)"
            fi
        else
            info "relancer avec --net pour poser $SUBNET.1/$PREFIX sur le PC"
        fi
    fi

    TRY=1
    while [ "$TRY" -le "$PING_TRIES" ]; do
        if ping -c 1 -W 2 "$BOX_IP" > /dev/null 2>&1; then
            break
        fi
        TRY=$((TRY+1))
        [ "$TRY" -le "$PING_TRIES" ] && sleep 1
    done
    if [ "$TRY" -gt "$PING_TRIES" ]; then
        die "$DEVICE_NAME injoignable (ping $BOX_IP) : verifier cable/switch/adresse"
    fi
    ok "ping $BOX_IP"
}

# === [1] ADB =================================================================
stage_adb()
{
    echo ""
    echo "--- [1] ADB ---"

    if adb_run get-state > /dev/null 2>&1; then
        ok "adb connecte (${TARGET:-defaut})"
        return 0
    fi

    say "connexion adb $BOX_IP:$ADB_PORT..."
    adb connect "$BOX_IP:$ADB_PORT" > /dev/null 2>&1 || true
    sleep 1
    TRY=1
    while [ "$TRY" -le 3 ]; do
        if adb_run get-state > /dev/null 2>&1; then
            ok "adb connecte ($BOX_IP:$ADB_PORT)"
            return 0
        fi
        adb connect "$BOX_IP:$ADB_PORT" > /dev/null 2>&1 || true
        sleep 2
        TRY=$((TRY+1))
    done
    die "adb injoignable sur $BOX_IP:$ADB_PORT (activer le debug USB / adb tcpip sur la box)"
}

# === [2..7] CONTROLES ========================================================
ROOT_OK=""
check_root()
{
    echo ""
    echo "--- [2] Root ---"
    R="$(trim "$(rget 'su -c id -u')")"
    if [ "$R" = "0" ]; then
        ROOT_OK=1
        ok "acces root (su)"
    else
        ROOT_OK=""
        warn "acces root" "indisponible ($(rget 'id -u' 2>/dev/null))${FIX:+ : corrections impossibles}"
    fi
    if [ "$FIX" = "1" ] && [ -z "$ROOT_OK" ]; then
        die "--fix exige un acces root sur la box"
    fi
}

check_version()
{
    echo ""
    echo "--- [3] Toolkit installe ---"
    V_INST="$(rget 'cat /data/scripts/VERSION' | sed -n 's/^version *: *//p' | head -n 1)"
    V_INST="$(trim "$V_INST")"
    if [ -z "$V_INST" ]; then
        ko "version installee" "absente (installer : tools/dpk.sh install)"
    elif [ "$V_INST" = "$VERSION_CFG" ]; then
        ok "version installee = $V_INST"
    else
        ko "version installee" "$V_INST (profil v$VERSION_CFG, mettre a jour : tools/dpk.sh install)"
    fi
}

read_iface_state()
{
    trim "$(rget "ip link show $IFACE")"
}

read_ip()
{
    trim "$(rget "ip addr show $IFACE" | sed -n 's/.*inet \([0-9.]*\).*/\1/p' | head -n 1)"
}

read_gw()
{
    trim "$(rget 'ip route' | sed -n 's/^default via \([0-9.]*\).*/\1/p' | head -n 1)"
}

read_dns()
{
    trim "$(rget 'getprop net.dns1')"
}

check_network_cfg()
{
    echo ""
    echo "--- [4] Config reseau box ($IFACE) ---"

    ST="$(read_iface_state)"
    case "$ST" in
        *"state UP"*|*"state UNKNOWN"*) ok "$IFACE UP" ;;
        "") ko "$IFACE" "interface absente" ;;
        *)  ko "$IFACE DOWN" "correction possible avec --fix"
            if [ "$FIX" = "1" ]; then
                rrun "ip link set $IFACE up"
                ST="$(read_iface_state)"
                case "$ST" in *"state UP"*|*"state UNKNOWN"*) fixed "$IFACE UP" "applied" ;; *) ko "$IFACE apres fix" "toujours DOWN" ;; esac
            fi ;;
    esac

    CUR="$(read_ip)"
    if [ "$CUR" = "$BOX_IP" ]; then
        ok "IP $IFACE = $BOX_IP"
    else
        ko "IP $IFACE" "${CUR:-aucune} (attendu $BOX_IP)"
        if [ "$FIX" = "1" ]; then
            rrun "ip addr flush dev $IFACE; ip addr add $BOX_IP/$PREFIX dev $IFACE"
            CUR="$(read_ip)"
            [ "$CUR" = "$BOX_IP" ] && fixed "IP $IFACE" "= $BOX_IP" || ko "IP apres fix" "${CUR:-aucune}"
        fi
    fi

    CUR="$(read_gw)"
    if [ "$CUR" = "$GW" ]; then
        ok "passerelle = $GW"
    else
        ko "passerelle" "${CUR:-absente} (attendu $GW)"
        if [ "$FIX" = "1" ]; then
            rrun "ip route del default; ip route add default via $GW dev $IFACE"
            CUR="$(read_gw)"
            [ "$CUR" = "$GW" ] && fixed "passerelle" "= $GW" || ko "passerelle apres fix" "${CUR:-absente}"
        fi
    fi

    CUR="$(read_dns)"
    if [ "$CUR" = "$DNS" ]; then
        ok "DNS = $DNS"
    else
        ko "DNS" "${CUR:-non defini} (attendu $DNS)"
        if [ "$FIX" = "1" ]; then
            rrun "setprop net.dns1 $DNS; setprop net.dns2 8.8.8.8"
            CUR="$(read_dns)"
            [ "$CUR" = "$DNS" ] && fixed "DNS" "= $DNS" || ko "DNS apres fix" "${CUR:-non defini}"
        fi
    fi
}

read_wifi()  { trim "$(rget 'settings get global wifi_on')"; }
read_bt()    { trim "$(rget 'settings get global bluetooth_on')"; }

check_wireless()
{
    echo ""
    echo "--- [5] Wireless ---"

    W="$(read_wifi)"
    case "$W" in
        0) ok "Wi-Fi coupe" ;;
        1)
            ko "Wi-Fi" "ACTIF"
            if [ "$FIX" = "1" ]; then
                rrun "svc wifi disable; settings put global wifi_on 0"
                [ "$(read_wifi)" = "0" ] && fixed "Wi-Fi coupe" "applied" || ko "Wi-Fi apres fix" "toujours actif"
            fi ;;
        *) info "Wi-Fi : etat inconnu ($W)" ;;
    esac

    B="$(read_bt)"
    case "$B" in
        0) ok "Bluetooth coupe" ;;
        1)
            ko "Bluetooth" "ACTIF"
            if [ "$FIX" = "1" ]; then
                rrun "svc bluetooth disable; settings put global bluetooth_on 0"
                [ "$(read_bt)" = "0" ] && fixed "Bluetooth coupe" "applied" || ko "Bluetooth apres fix" "toujours actif"
            fi ;;
        *) info "Bluetooth : etat inconnu ($B)" ;;
    esac
}

check_clock()
{
    echo ""
    echo "--- [6] Horloge ---"

    [ "$SKIP_DATE" = "1" ] && { info "horloge : passee (--skip-date)"; return 0; }

    BOX_S="$(rget 'date +%s')"
    case "$BOX_S" in ''|*[!0-9]*)
        ko "horloge" "lecture impossible ($BOX_S)"
        return 0 ;;
    esac

    PC_S="$(date +%s)"
    DRIFT=$((BOX_S - PC_S))
    DRIFT="${DRIFT#-}"

    if [ "$DRIFT" -le 300 ]; then
        ok "horloge (derive ${DRIFT}s)"
    else
        ko "horloge" "derive ${DRIFT}s"
        if [ "$FIX" = "1" ]; then
            VAL="$(date -u '+%Y%m%d.%H%M%S')"
            rrun "date -u -s $VAL"
            BOX_S="$(rget 'date +%s')"
            case "$BOX_S" in ''|*[!0-9]*)
                ko "horloge apres fix" "lecture impossible" ;;
                *)
                    DRIFT=$((BOX_S - $(date +%s)))
                    DRIFT="${DRIFT#-}"
                    [ "$DRIFT" -le 300 ] && fixed "horloge" "remise a l'heure UTC" \
                        || ko "horloge apres fix" "derive ${DRIFT}s" ;;
            esac
        fi
    fi
}

check_hdmi()
{
    echo ""
    echo "--- [7] HDMI (informatif) ---"
    B="$(trim "$(rget 'cat /sys/class/graphics/fb0/blank')")"
    case "$B" in
        1)  info "framebuffer blank (ecran coupe, field mode)" ;;
        0)  info "framebuffer actif" ;;
        "") info "fb0/blank illisible" ;;
        *)  info "framebuffer : $B" ;;
    esac
}

summary()
{
    echo ""
    echo "=== RESUME PROVISIONNEMENT ($DEVICE_NAME) ==="
    printf '  OK/FIX : %-4d KO : %d\n' "$PASS" "$KO"
    echo ""
    if [ "$KO" -eq 0 ]; then
        echo "OK : configuration conforme au profil"
        return 0
    fi
    echo "KO restants : relancer avec --fix (et --net au besoin)"
    return 1
}

stage_network
stage_adb
check_root
check_version
check_network_cfg
check_wireless
check_clock
check_hdmi
summary
