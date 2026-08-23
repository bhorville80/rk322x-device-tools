#!/system/bin/sh
# nreg - base de non-regression executable (miroir de docs/NON-REG.md).
#
# Verifie que les acquis valides sur le device tiennent toujours :
# chaque theme du script correspond a une section du document.
#
# Usage:
#   nreg              lance TOUS les themes, bilan PASS/FAIL (rc 0/1)
#   nreg <theme>      lance un seul theme (numero ou nom, prefixe accepte)
#   nreg HELP         cette aide
#
# Themes :
#   1 deploiement    2 outils       3 configuration   4 memoire
#   5 boot           6 reseau       7 wifi            8 diagnostic
#   9 sd            10 traces
#
# Portee : lecture seule + commandes STATUS rapides (< 30 s).
# Aucune action destructive (pas d'install, pas de reboot, pas de purge).

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

CFG_LOADED=0
for B in "$(dirname "$0")" /data/scripts; do
    if [ -f "$B/core/config.sh" ]; then
        . "$B/core/config.sh"
        CFG_LOADED=1
        break
    fi
done

BASE="$(cd "$(dirname "$0")" && pwd)"

PASS=0
FAIL=0

t_ok() { printf '  [ OK ] %-46s\n' "$1"; PASS=$((PASS+1)); }
t_ko() { printf '  [ KO ] %-46s (%s)\n' "$1" "$2"; FAIL=$((FAIL+1)); }

# verif generique par code retour
check_rc()
{
    LABEL="$1"; shift
    EXPECTED="$1"; shift
    "$@" > /dev/null 2>&1
    RC=$?
    case " $EXPECTED " in
        *" $RC "*) t_ok "$LABEL" ;;
        *)         t_ko "$LABEL" "rc=$RC attendu:$EXPECTED" ;;
    esac
}

# verif par valeur : $1 libelle, $2 attendu, $3 obtenu
check_eq()
{
    if [ "$2" = "$3" ]; then
        t_ok "$1"
    else
        t_ko "$1" "obtenu:'$3' attendu:'$2'"
    fi
}

section() { echo ""; echo "--- [$1] $2 ---"; }

help_show()
{
    echo ""
    echo "=== NREG - non-regression ==="
    echo ""
    echo "Usage:"
    echo "  nreg              tous les themes (bilan PASS/FAIL)"
    echo "  nreg <theme>      un seul theme : numero, nom ou prefixe"
    echo "                    ex : nreg 4 | nreg mem | nreg wifi"
    echo "  nreg HELP         cette aide"
    echo ""
    echo "Themes (cf. docs/NON-REG.md) :"
    echo "   1 deploiement     6 reseau"
    echo "   2 outils          7 wifi (wireless/bt)"
    echo "   3 configuration   8 diagnostic"
    echo "   4 memoire         9 sd (carte SD)"
    echo "   5 boot           10 traces"
}

# reference : valeurs issues de la configuration (calculees une fois)
setup_refs()
{
    CFG_IP="$(config_get IP 192.168.50.20)"
    CFG_SWAP="$(config_get MEM_SWAPPINESS 60)"
    IFACE="$(config_get INTERFACE eth0)"

    USB_FOUND=""
    for d in /mnt/media_rw/*; do
        if [ -f "$d/deploy.sh" ]; then
            USB_FOUND="$d"
            break
        fi
    done
}

# --- themes ---------------------------------------------------------------

th_deploiement()
{
    section 1 Deploiement

    VER_F=""
    for F in /data/scripts/VERSION "$(dirname "$BASE")/VERSION"; do
        [ -f "$F" ] && VER_F="$F" && break
    done
    if [ -n "$VER_F" ] && grep -q '^version' "$VER_F" 2>/dev/null; then
        t_ok "fichier VERSION lisible ($(grep '^version' "$VER_F" | head -n 1))"
    else
        t_ko "fichier VERSION lisible" "absent ou illisible"
    fi

    DEPLOY_F=""
    for F in /data/scripts/deploy.sh "$(dirname "$BASE")/deploy.sh"; do
        [ -f "$F" ] && DEPLOY_F="$F" && break
    done
    if [ -n "$DEPLOY_F" ]; then
        t_ok "deploy.sh present ($DEPLOY_F)"
    else
        t_ko "deploy.sh present" "introuvable"
    fi

    FOUND=0
    for B in "$BASE/core" /data/scripts/core; do
        [ -f "$B/runlog.sh" ] && [ -f "$B/config.sh" ] && FOUND=1 && break
    done
    [ "$FOUND" -eq 1 ] && t_ok "modules core (runlog, config)" \
                       || t_ko "modules core (runlog, config)" "introuvables"

    [ -n "$USB_FOUND" ] && t_ok "cle USB detectee ($USB_FOUND)" \
                        || t_ko "cle USB detectee" "aucune"
}

th_outils()
{
    section 2 "Outils (piliers)"

    check_rc "help"      "0" sh "$BASE/help.sh"
    check_rc "menu"      "0" sh "$BASE/menu.sh"
    check_rc "run_state" "0" sh "$BASE/run_state.sh"
}

th_configuration()
{
    section 3 Configuration

    check_rc "conf_check conforme" "0" sh "$BASE/conf_check.sh"
}

th_memoire()
{
    section Memoire

    check_rc "mem_tune STATUS" "0" sh "$BASE/mem_tune.sh" STATUS
    RUN_SWAP="$(cat /proc/sys/vm/swappiness 2>/dev/null | tr -dc '0-9')"
    check_eq "swappiness runtime = conf ($CFG_SWAP)" "$CFG_SWAP" "${RUN_SWAP:-?}"
}

th_boot()
{
    section Boot

    check_rc "boot STATUS" "0 1" sh "$BASE/boot.sh" STATUS
    for K in BOOT_MEM_TUNE BOOT_CUT_SERVICES BOOT_EXPOSE; do
        V="$(config_get "$K" "")"
        case "$V" in
            1) t_ok "flag boot actif : $K=1" ;;
            *) t_ko "flag boot actif : $K" "conf='$V' (attendu 1)" ;;
        esac
    done
}

th_reseau()
{
    section Reseau

    CUR_IP="$(ip -4 addr show "$IFACE" 2>/dev/null | sed -n 's/.*inet \([0-9.]*\).*/\1/p' | head -n 1)"
    [ -z "$CUR_IP" ] && CUR_IP="$(ifconfig "$IFACE" 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1p')"
    check_eq "IP $IFACE = conf ($CFG_IP)" "$CFG_IP" "${CUR_IP:-absente}"
}

th_wifi()
{
    section "Wireless / Bluetooth"

    if ip link show wlan0 > /dev/null 2>&1 || ifconfig wlan0 > /dev/null 2>&1; then
        t_ko "Wi-Fi desactive (wlan0)" "interface presente"
    else
        t_ok "Wi-Fi desactive (wlan0 absente)"
    fi
    if ip link show hci0 > /dev/null 2>&1 || ifconfig hci0 > /dev/null 2>&1; then
        t_ko "Bluetooth desactive (hci0)" "interface presente"
    else
        t_ok "Bluetooth desactive (hci0 absent)"
    fi
}

th_diagnostic()
{
    section "Diagnostics rapides"

    check_rc "thermal STATUS" "0" sh "$BASE/thermal.sh" STATUS
    check_rc "vitals STATUS"  "0" sh "$BASE/vitals.sh" STATUS
    check_rc "hdmi STATUS"    "0" sh "$BASE/hdmi.sh" STATUS
    check_rc "media"          "0" sh "$BASE/core/media.sh"
}

th_sd()
{
    section "Carte SD"

    check_rc "sd_boot STATUS" "0" sh "$BASE/sd_boot.sh" STATUS
}

th_traces()
{
    section Traces

    LOGDIR=""
    for D in "$USB_FOUND/log/exec"; do
        [ -d "$D" ] && LOGDIR="$D" && break
    done
    NB_TRACES=0
    [ -n "$LOGDIR" ] && NB_TRACES="$(ls -1 "$LOGDIR" 2>/dev/null | wc -l | tr -dc '0-9')"
    [ "${NB_TRACES:-0}" -gt 0 ] 2>/dev/null \
        && t_ok "traces exec presentes ($NB_TRACES dans $LOGDIR)" \
        || t_ko "traces exec presentes" "aucune trace trouvee"
}

# --- selection ------------------------------------------------------------

# resout un numero/nom/prefixe en nom de fonction ; vide si inconnu
resolve_theme()
{
    T="$(printf '%s' "$1" | tr 'A-Z' 'a-z')"
    case "$T" in
        1|dep|depl|deplo*|deploy*)     echo th_deploiement ;;
        2|out|outi|outil*)             echo th_outils ;;
        3|conf*)                       echo th_configuration ;;
        4|mem*)                        echo th_memoire ;;
        5|bo*)                         echo th_boot ;;
        6|res*|net)                    echo th_reseau ;;
        7|wi*|bt|bluetooth)            echo th_wifi ;;
        8|diag*)                       echo th_diagnostic ;;
        9|carte|sd)                    echo th_sd ;;
        10|trac*|log*)                 echo th_traces ;;
        *)                             echo "" ;;
    esac
}

summary()
{
    echo ""
    echo "=== RESUME NREG ==="
    printf '  PASS : %-4s FAIL : %s\n' "$PASS" "$FAIL"
    echo ""

    if [ "$FAIL" -eq 0 ]; then
        return 0
    fi
    return 1
}

main()
{
    setup_refs

    echo ""
    echo "=== RK322X NREG - non-regression ==="

    if [ -n "$ONLY" ]; then
        FN="$(resolve_theme "$ONLY")"
        if [ -z "$FN" ]; then
            echo "[ERREUR] theme inconnu : $ONLY (voir : nreg HELP)"
            return 2
        fi
        "$FN"
    else
        th_deploiement
        th_outils
        th_configuration
        th_memoire
        th_boot
        th_reseau
        th_wifi
        th_diagnostic
        th_sd
        th_traces
    fi

    summary
}

case "$1" in
    HELP|-h|--help)
        help_show
        exit 0
        ;;
esac

ONLY="$1"

if [ "$RUNLOG_LOADED" -eq 1 ] && runlog_start "$SCRIPT_ID"; then
    main >> "$RUNLOG_FILE" 2>&1
    RC=$?
    runlog_end "$RC"
    cat "$RUNLOG_FILE"
else
    main
    RC=$?
fi

exit "$RC"
