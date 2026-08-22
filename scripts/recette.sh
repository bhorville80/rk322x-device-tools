#!/system/bin/sh
# recette - validation de bout en bout de la box, en une commande
# (ou depuis le panneau web : page Commandes -> LANCER LA RECETTE).
#
#   P1 install      : VERSION + deploy STATUS (outils/links)
#   P2 selftest     : tous les outils repondent
#   P3 conf_check   : configuration validee + etat d'application
#   P4 mem_tune     : profil optimise applique (zram/lmk/logd)
#   P5 inspect_all  : toutes les analyses materiel/systeme/reseau
#   P6 run_state    : etat de lancement des outils
#   P7 expose       : STOP + EXPOSE, ports 8000/8080/8081, panneau+API
#   BILAN           : tableau des phases + verdict GO / NO-GO
#   RETOUR          : SEND_LOGS sur la cle puis message
#                     "CLE PRETE POUR ANALYSE RETOUR"
#
# Trace complete : log/exec/recette_<TS>.log
# Bilan pour l'IHM : log/recette_last.txt

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
        0) ST="OK"      ; PASS=$((PASS+1)) ;;
        *) ST="KO"      ; KO=$((KO+1)) ; KO_PHASES="$KO_PHASES $PID_" ;;
    esac
    printf '[%s] %-34s %s\n' "$PID_" "$LBL" "$ST"
}

main()
{

echo ""
echo "=== RECETTE BOX - $(date '+%Y-%m-%d %H:%M:%S') ==="
echo "cle : ${KEY:-absente}"

if [ "$(id -u 2>/dev/null)" != "0" ]; then
    echo ""
    echo "[ERREUR] privileges root requis : su -c \"sh $0\""
    return 2
fi

# ---------------------------------------------------------------- P1 install
echo ""
echo "--- [P1] INSTALL ---"
RC=1
if [ -f /data/scripts/VERSION ]; then
    STATUS_OUT="$(sh /data/scripts/deploy.sh STATUS 2>/dev/null)"
    MISS="$(printf '%s\n' "$STATUS_OUT" | sed -n 's/^ *manquants *: \([0-9]*\).*/\1/p')"
    if [ "${MISS:-9}" = "0" ]; then RC=0 ; fi
fi
verdict_phase "P1" "install (VERSION + STATUS)" "$RC"

# ---------------------------------------------------------------- P2 selftest
sh "$BASE/selftest.sh" > /dev/null 2>&1
verdict_phase "P2" "selftest" "$?"

# ---------------------------------------------------------------- P3 conf_check
CC_OUT="$(sh "$BASE/conf_check.sh" 2>&1)"
verdict_phase "P3" "conf_check" "$?"
printf '%s\n' "$CC_OUT" | grep -E '^\[ *(APPLIQUE|PAS LANCE|N/A)|optimisation' | sed 's/^/    /'

# ---------------------------------------------------------------- P4 mem_tune
sh "$BASE/mem_tune.sh" OPTIMIZE > /dev/null 2>&1
verdict_phase "P4" "mem_tune OPTIMIZE" "$?"

# ---------------------------------------------------------------- P5 analyses
sh "$BASE/inspect_all.sh" > /dev/null 2>&1
verdict_phase "P5" "inspect_all (analyses completes)" "$?"

# ---------------------------------------------------------------- P6 run_state
RS_OUT="$(sh "$BASE/run_state.sh" 2>&1)"
verdict_phase "P6" "run_state" "$?"
printf '%s\n' "$RS_OUT" | grep -E 'outils lances|silencieux|echec' | sed 's/^/    /'

# ---------------------------------------------------------------- P7 expose
echo ""
echo "--- [P7] EXPOSE ---"
sh "$BASE/deploy.sh" STOP > /dev/null 2>&1
sh "$BASE/deploy.sh" EXPOSE > /dev/null 2>&1
sleep 3

PORTS=0
for p in 8000 8080 8081; do
    netstat -tln 2>/dev/null | grep -q ":$p " && PORTS=$((PORTS+1))
done
IDX="$(busybox wget -qO- http://127.0.0.1:8000/index.html 2>/dev/null | grep -c RK322X)"
API_NOTE="token actif (controle API saute)"
API_OK=1
if [ -n "$KEY" ] && [ ! -f "$KEY/server/token" ]; then
    API_NOTE="api CONFIG repond"
    API_N="$(busybox wget -qO- http://127.0.0.1:8080/api/CONFIG 2>/dev/null | grep -c DEPLOY_VERSION)"
    [ "${API_N:-0}" -gt 0 ] && API_OK=1 || API_OK=0
fi
echo "    ports 8000/8080/8081 : $PORTS/3, panneau:$([ "$IDX" -gt 0 ] && echo ok || echo ko), $API_NOTE"

RC=0
[ "$PORTS" -eq 3 ] || RC=1
[ "${IDX:-0}" -gt 0 ] || RC=1
[ "$API_OK" -eq 1 ] || RC=1
verdict_phase "P7" "expose (stack web complete)" "$RC"

# ---------------------------------------------------------------- BILAN
echo ""
echo "=== BILAN RECETTE ==="
printf '  phases OK : %s   phases KO : %s\n' "$PASS" "$KO"
if [ "$KO" -eq 0 ]; then
    VERDICT="GO"
else
    VERDICT="NO-GO (phases:${KO_PHASES})"
fi
echo "  verdict   : $VERDICT"
echo ""

# ---------------------------------------------------------------- RETOUR
echo "--- [RETOUR] collecte des logs ---"
sh "$BASE/deploy.sh" SEND_LOGS > /dev/null 2>&1
sh "$BASE/rotate_logs.sh" > /dev/null 2>&1

DEST="${KEY:-/data/local/tmp}"
mkdir -p "$DEST/log" 2>/dev/null

cat > "$DEST/log/recette_last.txt" 2>/dev/null <<EOF
=== RECETTE $(date '+%Y-%m-%d %H:%M:%S') ===
phases OK : $PASS   phases KO : $KO
verdict   : $VERDICT
trace complete : log/exec/$(basename "${RUNLOG_FILE:-recette.log}")
logs retour    : deploy SEND_LOGS fait (log/log_*)
EOF

echo ""
echo "==============================================="
echo " CLE PRETE POUR ANALYSE RETOUR"
echo " cle    : ${KEY:-/data/local/tmp}"
echo " bilan  : log/recette_last.txt"
echo " trace  : log/exec/recette_*.log"
echo " cote PC: admin/windows/logpull.ps1"
echo "==============================================="
echo ""

[ "$KO" -eq 0 ] && return 0
return 1
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
