#!/system/bin/sh
# recette - validation de bout en bout de la box, par phases ou globale.
#
#   recette                sequence complete P1..P7 + bilan + retour
#   recette P1..P7         une seule phase (enregistree dans
#                          log/recette_phases.txt pour l'IHM)
#   recette RETOUR         SEND_LOGS + message cle prete pour retour
#
# Phases :
#   P1 install      VERSION + deploy STATUS      P5 inspect_all (analyses)
#   P2 selftest     tous les outils              P6 run_state (lancements)
#   P3 conf_check   config + application         P7 expose ports/panneau/api
#   P4 mem_tune     profil optimise
#
# Traces : log/exec/recette_<TS>.log (detail)
#          log/recette_last.txt    (derniere action, lu par l'IHM)
#          log/recette_phases.txt  (etat par phase, lu par l'IHM)

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

BASE="$(cd "$(dirname "$0")" && pwd)"

for B in "$BASE" "$BASE/../scripts" /data/scripts; do
    if [ -f "$B/core/config.sh" ]; then
        . "$B/core/config.sh"
        break
    fi
done
command -v config_get >/dev/null 2>&1 || config_get() { echo "$2"; }
command -v is_root >/dev/null 2>&1 || is_root() { case "$(id -u 2>/dev/null)" in 0) return 0 ;; esac; case "$(id 2>/dev/null)" in "uid=0("*) return 0 ;; esac; return 1; }

KEY=""
for d in /mnt/media_rw/*; do
    [ -f "$d/deploy.sh" ] && { KEY="$d"; break; }
done

PASS=0
KO=0
KO_PHASES=""

verdict_phase()
{
    PID_="$1"
    LBL="$2"
    RC_="$3"
    case "$RC_" in
        0) ST="OK"  ; PASS=$((PASS+1)) ;;
        *) ST="KO"  ; KO=$((KO+1)) ; KO_PHASES="$KO_PHASES $PID_" ;;
    esac
    printf '[%s] %-34s %s\n' "$PID_" "$LBL" "$ST"

    if [ -n "$KEY" ]; then
        mkdir -p "$KEY/log" 2>/dev/null
        PF="$KEY/log/recette_phases.txt"
        grep -v "^$PID_ " "$PF" 2>/dev/null > "${PF}.tmp" 2>/dev/null
        mv -f "${PF}.tmp" "$PF" 2>/dev/null
        echo "$PID_ $ST $(date '+%Y%m%d-%H%M%S')" >> "$PF" 2>/dev/null
    fi

    return "$RC_"
}

ihm_note()
{
    D_="${KEY:-/data/local/tmp}"
    mkdir -p "$D_/log" 2>/dev/null
    printf '%s\n%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" \
        > "$D_/log/recette_last.txt" 2>/dev/null
}

require_root_or_fail()
{
    if ! is_root; then
        echo ""
        echo "[ERREUR] privileges root requis : su -c \"sh $0 $*\""
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------- phases

p_install()
{
    echo "--- [P1] INSTALL ---"
    RC=1
    if [ -f /data/scripts/VERSION ]; then
        STATUS_OUT="$(sh /data/scripts/deploy.sh STATUS 2>/dev/null)"
        MISS="$(printf '%s\n' "$STATUS_OUT" | sed -n 's/^ *manquants *: \([0-9]*\).*/\1/p')"
        if [ "${MISS:-9}" = "0" ]; then RC=0 ; fi
    fi
    verdict_phase "P1" "install (VERSION + STATUS)" "$RC"
}

p_selftest()
{
    sh "$BASE/selftest.sh" > /dev/null 2>&1
    verdict_phase "P2" "selftest" "$?"
}

p_conf()
{
    CC_OUT="$(sh "$BASE/conf_check.sh" 2>&1)"
    RC=$?
    verdict_phase "P3" "conf_check" "$RC"
    printf '%s\n' "$CC_OUT" \
        | grep -E 'APPLIQUE|PAS LANCE|N/A|optimisation' | sed 's/^/    /'
    return "$RC"
}

p_memtune()
{
    sh "$BASE/mem_tune.sh" OPTIMIZE > /dev/null 2>&1
    verdict_phase "P4" "mem_tune OPTIMIZE" "$?"
}

p_analyses()
{
    sh "$BASE/inspect_all.sh" > /dev/null 2>&1
    verdict_phase "P5" "inspect_all (analyses completes)" "$?"
}

p_runstate()
{
    RS_OUT="$(sh "$BASE/run_state.sh" 2>&1)"
    RC=$?
    verdict_phase "P6" "run_state" "$RC"
    printf '%s\n' "$RS_OUT" | grep -E 'outils lances|silencieux|echec' | sed 's/^/    /'
    return "$RC"
}

port_listening()
{
    # $1 port decimal ; netstat sinon /proc/net/tcp (port hexa, etat 0A=LISTEN)
    if command -v netstat > /dev/null 2>&1; then
        netstat -tln 2>/dev/null | grep -q ":$1 " && return 0
    fi
    # busybox printf : %04X garanti (builtin mksh incertain sur vieux firmware)
    if command -v busybox > /dev/null 2>&1; then
        PH="$(busybox printf '%04X' "$1" 2>/dev/null)"
    else
        PH="$(printf '%04X' "$1" 2>/dev/null)"
    fi
    [ -n "$PH" ] && grep -qi ":$PH .* 0A " /proc/net/tcp 2>/dev/null && return 0
    grep -qi ":$PH .* 0A " /proc/net/tcp6 2>/dev/null && return 0
    return 1
}

p_expose()
{
    echo "--- [P7] EXPOSE ---"
    sh "$BASE/deploy.sh" STOP > /dev/null 2>&1
    EXPOSE_OUT="$(sh "$BASE/deploy.sh" EXPOSE 2>&1)"
    RC_EXPOSE=$?
    sleep 3

    PORTS=0
    for p in 8000 8080 8081; do
        port_listening "$p" && PORTS=$((PORTS+1))
    done
    IDX="$(busybox wget -qO- http://127.0.0.1:8000/index.html 2>/dev/null | grep -c RK322X)"
    API_NOTE="api CONFIG : non verifiee"
    API_OK=1
    if [ -n "$KEY" ] && [ -f "$KEY/server/token" ]; then
        API_NOTE="token actif (controle API saute)"
    else
        API_N="$(busybox wget -qO- http://127.0.0.1:8080/api/CONFIG 2>/dev/null | grep -c DEPLOY_VERSION)"
        if [ "${API_N:-0}" -gt 0 ]; then
            API_NOTE="api CONFIG repond"
            API_OK=1
        else
            API_NOTE="api CONFIG injoignable"
            API_OK=0
        fi
    fi
    echo "    ports 8000/8080/8081 : $PORTS/3, panneau:$([ "$IDX" -gt 0 ] && echo ok || echo ko), $API_NOTE"

    if [ "$RC_EXPOSE" -ne 0 ] || [ "$PORTS" -lt 3 ] || [ "${IDX:-0}" -eq 0 ]; then
        echo "    sortie deploy EXPOSE :"
        printf '%s\n' "$EXPOSE_OUT" | tail -n 8 | sed 's/^/      /'
    fi

    RC=0
    [ "$PORTS" -eq 3 ] || RC=1
    [ "${IDX:-0}" -gt 0 ] || RC=1
    [ "$API_OK" -eq 1 ] || RC=1
    verdict_phase "P7" "expose (stack web complete)" "$RC"
}

p_retour()
{
    echo "--- [RETOUR] collecte des logs ---"
    sh "$BASE/deploy.sh" SEND_LOGS > /dev/null 2>&1
    sh "$BASE/rotate_logs.sh" > /dev/null 2>&1
    return 0
}

bilan()
{
    echo ""
    echo "=== BILAN RECETTE ==="
    printf '  phases OK : %s   phases KO : %s\n' "$PASS" "$KO"
    if [ "$KO" -eq 0 ]; then
        VERDICT="GO"
    else
        VERDICT="NO-GO (phases:${KO_PHASES})"
    fi
    echo "  verdict   : $VERDICT"

    DEST="${KEY:-/data/local/tmp}"
    mkdir -p "$DEST/log" 2>/dev/null
    {
        echo "=== RECETTE $(date '+%Y-%m-%d %H:%M:%S') ==="
        echo "phases OK : $PASS   phases KO : $KO"
        echo "verdict   : $VERDICT"
        echo "trace     : log/exec/recette_*.log"
    } > "$DEST/log/recette_last.txt" 2>/dev/null

    echo ""
    return 0
}

fin_retour()
{
    echo ""
    echo "==============================================="
    echo " CLE PRETE POUR ANALYSE RETOUR"
    echo " cle    : ${KEY:-/data/local/tmp}"
    echo " bilan  : log/recette_last.txt"
    echo " trace  : log/exec/recette_*.log"
    echo " cote PC: admin/windows/logpull.ps1"
    echo "==============================================="
    ihm_note "CLE PRETE POUR ANALYSE RETOUR ($(date '+%H:%M:%S'))"
}

p_manifest()
{
    echo "--- [M] MANIFEST ---"
    if [ -z "$KEY" ]; then
        echo "[ERREUR] cle absente : manifest impossible"
        return 1
    fi

    PF="$KEY/log/recette_phases.txt"
    OKN=0
    i=1
    while [ "$i" -le 7 ]; do
        grep -q "^P$i OK" "$PF" 2>/dev/null && OKN=$((OKN+1))
        i=$((i+1))
    done
    if [ "$OKN" -ne 7 ]; then
        echo "[ERREUR] phases completes requises ($OKN/7 OK)"
        echo "         lancer les phases manquantes puis regenerer"
        return 1
    fi

    MD="$KEY/manifests/recette"
    mkdir -p "$MD" 2>/dev/null || { echo "[ERREUR] $MD inaccessible"; return 1; }
    if [ -f "$MD/latest.manifest" ]; then
        cp -f "$MD/latest.manifest" "$MD/previous.manifest" 2>/dev/null
    fi
    TS="$(date '+%Y%m%d-%H%M%S')"
    M="$MD/recette_$TS.manifest"

    SUM=""
    if command -v sha256sum > /dev/null 2>&1; then
        SUM="sha256sum"
    elif command -v busybox > /dev/null 2>&1 && busybox sha256sum 2>/dev/null | grep -q .; then
        SUM="busybox sha256sum"
    fi

    {
        echo "manifest : recette certifiee"
        echo "date     : $(date '+%Y-%m-%d %H:%M:%S')"
        echo "device   : $(getprop ro.product.device 2>/dev/null) / Android $(getprop ro.build.version.release 2>/dev/null)"
        echo "ip       : $(config_get IP 2>/dev/null)"
        echo "version  : $(sed -n 's/^version *: *//p' /data/scripts/VERSION 2>/dev/null | head -n 1)"
        echo "--- phases ---"
        cat "$PF" 2>/dev/null | sort
        echo "--- conf_check ---"
        sh "$BASE/conf_check.sh" 2>/dev/null \
            | grep -E 'APPLIQUE|PAS LANCE|N/A|conforme|invalide' | sed 's/^ */  /'
        echo "--- empreintes /data/scripts ---"
        if [ -n "$SUM" ] && [ -d /data/scripts ]; then
            cd /data/scripts 2>/dev/null && $SUM *.sh core/*.sh config/device.conf 2>/dev/null \
                | sed 's/^/  /'
        else
            echo "  (sha256sum indisponible sur cette box)"
        fi
    } > "$M" 2>/dev/null

    cp -f "$M" "$MD/latest.manifest" 2>/dev/null

    if [ -s "$M" ]; then
        echo "[ OK ] manifest -> $(basename "$M") (+ latest.manifest)"
        ihm_note "MANIFEST genere : $(basename "$M")"
        p_snapshot "$MD"
        return 0
    fi
    echo "[ ERREUR ] manifest non ecrit"
    return 1
}

p_snapshot()
{
    MD="$1"
    echo "--- [M2] SNAPSHOT DEVICE + ALL CONF ---"

    TS="$(date '+%Y%m%d-%H%M%S')"
    A="$MD/allconf_$TS.conf"

    ZS="$(cat /sys/block/zram0/disksize 2>/dev/null)"
    SW="$(cat /proc/sys/vm/swappiness 2>/dev/null)"
    GOV="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)"

    {
        echo "# snapshot device + configuration effective"
        echo "# genere par recette MANIFEST le $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        echo "# --- identite ---"
        echo "DEVICE_ID=$(getprop ro.product.device 2>/dev/null)"
        echo "DEVICE_NAME=$(getprop ro.product.model 2>/dev/null)"
        echo "HW_ANDROID=$(getprop ro.build.version.release 2>/dev/null)"
        echo "HW_SDK=$(getprop ro.build.version.sdk 2>/dev/null)"
        echo "HW_PATCH=$(getprop ro.build.version.security_patch 2>/dev/null)"
        echo "HW_BUILD=$(getprop ro.build.version.incremental 2>/dev/null)"
        echo "RAM_MB=$(( $(sed -n 's/^MemTotal: *\([0-9]*\) kB/\1/p' /proc/meminfo 2>/dev/null | head -n 1) / 1024 ))"
        echo ""
        echo "# --- reseau effectif ---"
        IF="$(config_get INTERFACE eth0)"
        echo "INTERFACE=$IF"
        echo "IP=$(ifconfig "$IF" 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p')"
        echo "GATEWAY=$(ip route 2>/dev/null | sed -n 's/^default via \([0-9.]*\).*/\1/p')"
        echo "DNS=$(getprop net.dns1 2>/dev/null)"
        echo ""
        echo "# --- memoire appliquee ---"
        echo "MEM_ZRAM_MB=${ZS:+$((ZS / 1048576))}"
        echo "MEM_SWAPPINESS=${SW:-?}"
        echo "MEM_LMK_MINFREE=$(cat /sys/module/lowmemorykiller/parameters/minfree 2>/dev/null)"
        echo "LOGD_SIZE_KB=$(getprop persist.logd.size 2>/dev/null | tr -d 'Kk')"
        echo ""
        echo "# --- cpu / thermique ---"
        echo "GOVERNOR=$GOV"
        echo ""
        echo "# --- services running ---"
        getprop 2>/dev/null \
            | sed -n 's/^\[init\.svc\.\([^]]*\)\]: *\[\(running\)\]/\1/p' \
            | sort | tr '\n' ' '
        echo ""
        echo ""
        echo "# --- puces detectees (device_info) ---"
        sh "$BASE/device_info.sh" 2>/dev/null \
            | sed -n '/SYNTHESE PUCES/,$p' | grep '^  - ' | sed 's/^  //'
    } > "$A" 2>/dev/null

    if [ -s "$A" ]; then
        cp -f "$A" "$MD/latest_allconf.conf" 2>/dev/null
        echo "[ OK ] snapshot -> $(basename "$A") (+ latest_allconf.conf)"
        if [ -f "$MD/previous.manifest" ]; then
            diff -u "$MD/previous.manifest" "$MD/latest.manifest" \
                > "$MD/diff_previous.txt" 2>/dev/null \
                && echo "[ -- ] aucune derive vs manifest precedent" \
                || echo "[ OK ] derive vs precedent : diff_previous.txt"
        fi
        return 0
    fi
    echo "[ ERREUR ] snapshot non ecrit"
    return 1
}

main()
{

echo ""
echo "=== RECETTE BOX - $(date '+%Y-%m-%d %H:%M:%S') ==="
echo "cle : ${KEY:-absente}"

require_root_or_fail "$@" || return 2

case "$1" in
    P1) p_install ;;
    P2) p_selftest ;;
    P3) p_conf ;;
    P4) p_memtune ;;
    P5) p_analyses ;;
    P6) p_runstate ;;
    P7) p_expose ;;
    RETOUR)
        p_retour
        fin_retour
        return 0
        ;;
    MANIFEST)
        p_manifest
        return $?
        ;;
    *)
        p_install
        p_selftest
        p_conf
        p_memtune
        p_analyses
        p_runstate
        p_expose
        bilan
        p_retour
        fin_retour
        ;;
esac

echo ""
if [ "$KO" -ne 0 ]; then
    return 1
fi
return 0
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
