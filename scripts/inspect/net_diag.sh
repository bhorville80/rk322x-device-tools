#!/system/bin/sh
# net_diag - diagnostics reseau de la box :
# lien (vitesse/duplex), adresses (auto-detection), routes, DNS,
# connectivite (passerelle + internet), latence, ports en ecoute.
#
# Usage: net_diag.sh [STATUS|PORTS|PING <hote>|THROUGHPUT <ip>|help]

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" "$(dirname "$0")/.." /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

for B in "$(dirname "$0")" "$(dirname "$0")/core" "$(dirname "$0")/../core" /data/scripts /data/scripts/core; do
    if [ -f "$B/core/config.sh" ]; then
        . "$B/core/config.sh"
        break
    fi
done

IFACE="$(config_get INTERFACE eth0)"
EXPECT_IP="$(config_get IP 192.168.50.20)"
GW="$(config_get GATEWAY 192.168.50.1)"
DNS="$(config_get DNS 192.168.50.1)"
SUBNET="$(printf '%s' "$EXPECT_IP" | cut -d. -f1-3)"

OK=0; KO=0; WARN=0
ok()   { printf '  [ OK ] %-24s %s\n' "$1" "$2"; OK=$((OK+1)); }
ko()   { printf '  [ KO ] %-24s %s\n' "$1" "$2"; KO=$((KO+1)); }
warn() { printf '  [WARN] %-24s %s\n' "$1" "$2"; WARN=$((WARN+1)); }
info() { printf '  [ -- ] %-24s %s\n' "$1" "$2"; }

state_of()
{
    ip link show "$1" 2>/dev/null | tr -d '\r'
}

ip_of()
{
    ip addr show "$1" 2>/dev/null \
        | sed -n 's/.*inet \([0-9.]*\).*/\1/p' | head -n 1 | tr -d '\r'
}

ping_ms()
{
    # $1 hote -> "rc latence-ms" (latence vide si echec)
    OUT="$(ping -c 1 -W 2 "$1" 2>/dev/null | tr -d '\r')"
    RC=$?
    MS="$(printf '%s\n' "$OUT" | sed -n 's/.*time=\([0-9.]*\) ms.*/\1/p')"
    printf '%s %s' "$RC" "${MS:-}"
}

do_status()
{
    echo ""
    echo "=== NET DIAG ($IFACE, profil v$(sed -n 's/^DEPLOY_VERSION=//p' "$(dirname "$0")/../../config/device.conf" 2>/dev/null | head -n 1 | tr -d '\r')) ==="

    echo ""
    echo "--- [1] Lien ---"
    ST="$(state_of "$IFACE")"
    case "$ST" in
        *"state UP"*|*"state UNKNOWN"*) ok "$IFACE" "UP" ;;
        "")                             ko "$IFACE" "absente" ;;
        *)                              ko "$IFACE" "DOWN" ;;
    esac
    SPD="$(cat "/sys/class/net/$IFACE/speed" 2>/dev/null | tr -dc '0-9')"
    DPX="$(cat "/sys/class/net/$IFACE/duplex" 2>/dev/null | tr -d '\r')"
    case "$SPD" in
        ''|0) info "vitesse" "non rapportee par le driver" ;;
        *)    info "lien" "${SPD} Mbps ${DPX:-duplex ?}" ;;
    esac
    MAC="$(cat "/sys/class/net/$IFACE/address" 2>/dev/null | tr -d '\r')"
    [ -n "$MAC" ] && info "MAC" "$MAC"

    echo ""
    echo "--- [2] Adresses ---"
    CUR="$(ip_of "$IFACE")"
    case "$CUR" in
        "$EXPECT_IP") ok "IP $IFACE" "$CUR" ;;
        "")           ko "IP $IFACE" "aucune (remede : set_network)" ;;
        *)            warn "IP $IFACE" "$CUR (attendu $EXPECT_IP)" ;;
    esac

    DETECTED=""
    for D in /sys/class/net/*; do
        N="$(basename "$D")"
        case "$N" in lo) continue ;; esac
        A="$(ip_of "$N")"
        [ -z "$A" ] && continue
        case "$A" in
            "$SUBNET".*) [ -z "$DETECTED" ] && DETECTED="$N ($A)" ;;
        esac
        printf '       %-10s %s\n' "$N" "$A"
    done
    case "$DETECTED" in
        "") [ -n "$CUR" ] || warn "auto-detection" "aucune IP dans $SUBNET.0/24" ;;
        *)  info "sous-reseau cible" "$SUBNET.0/24 sur $DETECTED" ;;
    esac

    echo ""
    echo "--- [3] Routes ---"
    RGW="$(ip route 2>/dev/null | tr -d '\r' | sed -n 's/^default via \([0-9.]*\).*/\1/p' | head -n 1)"
    case "$RGW" in
        "$GW") ok "passerelle" "$RGW" ;;
        "")    ko "passerelle" "absente (remede : set_network)" ;;
        *)     warn "passerelle" "$RGW (attendu $GW)" ;;
    esac
    ip route 2>/dev/null | grep -q "$SUBNET\." \
        && info "route locale" "$SUBNET.0/24 presente" \
        || warn "route locale" "$SUBNET.0/24 absente"

    echo ""
    echo "--- [4] DNS ---"
    D1="$(getprop net.dns1 2>/dev/null | tr -d '\r')"
    D2="$(getprop net.dns2 2>/dev/null | tr -d '\r')"
    [ -n "$D1" ] && ok "serveurs" "$D1 ${D2:+/ $D2}" || ko "serveurs" "non definis"
    R="$(ping_ms "$DNS")"
    case "$R" in 0\ *) ok "resolution/reponse" "DNS $DNS (${R#0 }) ms" ;;
                 *)     ko "DNS $DNS" "sans reponse (resolutions en echec probable)" ;;
    esac

    echo ""
    echo "--- [5] Connectivite ---"
    R="$(ping_ms "$GW")"
    case "$R" in 0\ *) ok "passerelle ping" "${R#0 } ms" ;;
                 *)     ko "passerelle ping" "$GW sans reponse" ;;
    esac
    R="$(ping_ms 8.8.8.8)"
    case "$R" in 0\ *) ok "internet (ICMP)" "8.8.8.8 ${R#0 } ms" ;;
                 *)     warn "internet (ICMP)" "bloque ou hors ligne (LAN seul ?)" ;;
    esac
    R="$(ping_ms google.com)"
    case "$R" in 0\ *) ok "internet (DNS+ICMP)" "${R#0 } ms" ;;
                 *)     warn "internet (DNS+ICMP)" "echec : DNS ou sortie coupee" ;;
    esac

    echo ""
    echo "=== RESUME : ok=$OK ko=$KO warn=$WARN ==="
    [ "$KO" -eq 0 ] && return 0
    echo "Remedes : set_network (config statique), check_state (vue globale)"
    return 1
}

port_label()
{
    case "$1" in
        *:8000) echo "HTTP cle (start_server)" ;;
        *:8180) echo "API control" ;;
        *:8081) echo "GUI remote" ;;
        *:5555) echo "adb tcp" ;;
        *:2222) echo "ssh dropbear (si lance)" ;;
        *)      echo "" ;;
    esac
}

proc_listen_ports()
{
    # /proc/net/tcp{,6} lu CHAMP PAR CHAMP (espaces ou tabs selon noyau) :
    # champ 3 = adresse locale hex (port apres le dernier ':'),
    # champ 5 = etat, 0A = LISTEN. Seule source fiable quand netstat est
    # absent/muet sur vieux firmware (cf TROUBLESHOOTING, recette v13).
    for F_ in /proc/net/tcp /proc/net/tcp6; do
        [ -f "$F_" ] || continue
        # champs : sl | adresse locale | adresse distante | etat | ...
        while read -r SL_ LA_ RA_ ST_ _; do
            [ "$ST_" = "0A" ] || continue
            H_="${LA_##*:}"
            case "$H_" in
                ''|*[!0-9A-Fa-f]*) continue ;;
            esac
            printf '%d\n' "$((16#$H_))" 2>/dev/null
        done < "$F_"
    done
}

port_inode()
{
    # inode du socket LISTEN sur le port decimal $1 (tcp puis tcp6)
    H_="$(printf '%04X' "$1" 2>/dev/null)"
    [ -n "$H_" ] || return 1
    for F_ in /proc/net/tcp /proc/net/tcp6; do
        [ -f "$F_" ] || continue
        IN_="$(awk '{split($2,a,":")} a[2]=="'"$H_"'" && $4=="0A" {printf "%d", $11; exit}' "$F_" 2>/dev/null)"
        [ -n "$IN_" ] && { echo "$IN_"; return 0; }
    done
    return 1
}

port_owner()
{
    # qui tient ce port ? resolution inode socket -> /proc/*/fd -> pid/cmdline.
    # Rend le squatter NOMME au lieu d'un mystere (cas v23 : serveur HTTP
    # integre de Kodi sur 8180, rebondissant a chaque reprise d'ecran).
    IN_="$(port_inode "$1")" || return 1
    [ -n "$IN_" ] || return 1
    for D_ in /proc/[0-9]*; do
        PID_="${D_#/proc/}"
        [ "$PID_" = "$$" ] && continue
        for FD_ in "$D_"/fd/*; do
            L_="$(readlink "$FD_" 2>/dev/null)"
            case "$L_" in
                socket:\[$IN_\])
                    C_="$(tr '\0' ' ' < "$D_/cmdline" 2>/dev/null | cut -c1-70)"
                    [ -n "$C_" ] || C_="$(cat "$D_/comm" 2>/dev/null | tr -d '\r\n')"
                    U_="$(awk '/^Uid:/{print $2}' "$D_/status" 2>/dev/null)"
                    case "${U_:-}" in
                        0)      U_="root" ;;
                        1000)   U_="system" ;;
                        2000)   U_="shell" ;;
                        10*)    U_="app u0_a${U_#100}" ;;
                    esac
                    printf 'pid %s (%s) : %s' "$PID_" "${U_:-uid?}" "${C_:-?}"
                    return 0 ;;
            esac
        done
    done
    return 1
}

# ne garder que des ports credibles (1..65535) : un netstat exotique
# (vieux toolbox) peut sortir n'importe quoi (recette v18 : unique entree
# "12884901988 service inconnu" qui masquait le fallback /proc)
ports_valid()
{
    while IFS= read -r P_; do
        case "$P_" in ''|*[!0-9]*) continue ;; esac
        [ "$P_" -ge 1 ] && [ "$P_" -le 65535 ] && echo "$P_"
    done
}

do_ports()
{
    echo ""
    echo "=== PORTS EN ECOUTE ==="

    NET_=""
    if command -v netstat > /dev/null 2>&1; then
        NET_="$(netstat -tln 2>/dev/null | tr -d '\r' \
                | sed -n 's/^.*[[:space:]]\(0\.0\.0\.0\|::\):\([0-9][0-9]*\)[[:space:]].*/\2/p')"
    fi
    # fusion des deux sources puis filtre : ni l'une ni l'autre n'est seule
    # fiable selon le firmware ; la validation 1..65535 evacue les delires
    LISTEN="$(printf '%s\n%s\n' "$NET_" "$(proc_listen_ports)" | ports_valid | sort -un)"

    if [ -n "$LISTEN" ]; then
        for P in $LISTEN; do
            L="$(port_label ":$P")"
            printf '  %-8s %s\n' "$P" "${L:-service inconnu}"
            O_="$(port_owner "$P" 2>/dev/null)"
            [ -n "$O_" ] && printf '           ^ %s\n' "$O_"
        done
    else
        echo "  (rien detecte : netstat muet ET /proc/net/tcp illisible)"
        echo "  sonde directe : busybox wget -qO- http://127.0.0.1:8180/api/HELP"
    fi
    return 0
}

do_ping()
{
    H="$1"
    [ -n "$H" ] || { echo "usage : net_diag PING <hote>"; return 1; }
    echo ""
    echo "=== PING $H (4 essais) ==="
    OUT="$(ping -c 4 -W 2 "$H" 2>&1 | tr -d '\r')"
    RC=$?
    printf '%s\n' "$OUT" | tail -n 2 | sed 's/^/  /'
    [ "$RC" -eq 0 ] && return 0
    return 1
}

do_throughput()
{
    T="$1"
    [ -n "$T" ] || { echo "usage : net_diag THROUGHPUT <ip-receveur>"; return 1; }
    echo ""
    echo "=== THROUGHPUT (dd sur nc) vers $T:9000 ==="

    if command -v nc > /dev/null 2>&1; then
        NC="nc"
    elif busybox 2>&1 | grep -qw nc; then
        NC="busybox nc"
    else
        echo "[ERREUR] nc indisponible (ni standalone ni applet busybox)"
        return 1
    fi

    cat << EOF
Cote receveur (PC) :
  nc -l -p 9000 > /dev/null
Puis relancer : net_diag THROUGHPUT $T
EOF
    echo "[*] envoi 16 Mo..."
    S0="$(cut -d. -f1 /proc/uptime 2>/dev/null | tr -dc '0-9')"
    dd if=/dev/zero bs=64k count=256 2>/dev/null | $NC "$T" 9000
    RC=$?
    S1="$(cut -d. -f1 /proc/uptime 2>/dev/null | tr -dc '0-9')"
    if [ "$RC" -eq 0 ] && [ -n "$S0" ] && [ -n "$S1" ]; then
        D=$((S1 - S0))
        [ "$D" -le 0 ] && D=1
        echo "[ OK ] 16 Mo en ${D}s (~$((16 / D)) Mo/s)"
    else
        echo "[ERREUR] envoi echoue (receveur pret ?)"
    fi
    return 0
}

usage()
{
    echo ""
    echo "Usage: net_diag [STATUS|PORTS|PING <hote>|THROUGHPUT <ip>]"
    echo ""
    echo "  STATUS          diagnostic complet (defaut)"
    echo "  PORTS           services en ecoute (cle/API/GUI/adb/ssh)"
    echo "  PING <hote>     latence detaillee"
    echo "  THROUGHPUT <ip> test debit sortant (nc requis chez le receveur)"
    echo ""
    return 1
}

case "$1" in
    ""|STATUS|status)  do_status ;;
    PORTS|ports)       do_ports ;;
    PING|ping)         shift; do_ping "$1" ;;
    THROUGHPUT|throughput) shift; do_throughput "$1" ;;
    HELP|help|-h|--help) usage ;;
    *)                 usage ;;
esac
