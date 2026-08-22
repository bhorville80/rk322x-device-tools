#!/system/bin/sh
# run_state - etat de lancement des outils, par analyse des logs exec.
#
# Chaque outil ecrit log/exec/<outil>_<TS>.log (rotation : 5 retenus
# par outil). run_state croise cette trace avec la liste des scripts
# installes pour distinguer :
#
#   [LANCE]     deja execute - nombre de lancements, dernier horodatage,
#               dernier code retour rc (0 = ok)
#   [JAMAIS]    script installe mais jamais lance
#
#   run_state            rapport sur la cle (log/exec) sinon fallback box
#   run_state help       cette aide

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
[ -d "$BASE/scripts" ] && BASE="$BASE/scripts"

main()
{

echo ""
echo "=== RUN STATE - executions des outils ==="

LOG_DIRS=""
for D_ in /mnt/media_rw/*/log/exec /data/local/tmp/rk322x_logs/exec \
         "${TMPDIR:-/tmp}/rk322x_logs/exec"; do
    [ -d "$D_" ] && LOG_DIRS="$LOG_DIRS $D_"
done

if [ -z "$LOG_DIRS" ]; then
    echo ""
    echo "[ -- ] aucun repertoire log/exec trouve"
    echo "       les outils ecrivent leur trace au premier lancement"
    return 0
fi

echo "[1] Sources :$LOG_DIRS"

INVENT=""
for D_ in $LOG_DIRS; do
    for F in "$D_"/*.log; do
        [ -f "$F" ] || continue
        NAME="$(basename "$F" .log)"
        TOOL="${NAME%_*}"
        TS="${NAME##*_}"
        RC="$(sed -n 's/^rc *: *//p' "$F" 2>/dev/null | tail -n 1)"
        case "$RC" in ''|*[!0-9]*) RC="?" ;; esac
        INVENT="$INVENT$TOOL|$TS|$RC
"
    done
done

if [ -z "$INVENT" ]; then
    echo "[ -- ] aucun log d'execution present"
    return 0
fi
INVENT="$(printf '%s\n' "$INVENT" | sort -u)"

echo ""
echo "[2] Outils deja lances (sur les 5 dernieres traces retenues/outil)"
printf '  %-22s %5s  %-17s %-8s %s\n' "OUTIL" "FOIS" "DERNIER" "RC" "VERDICT"
LANCED=0 ; KO_TOT=0
for T in $(printf '%s\n' "$INVENT" | sed 's/|.*//' | sort -u); do
    NB=0 ; LAST="" ; LAST_RC="?" ; KO=0
    for L in $(printf '%s\n' "$INVENT" | grep "^$T|" | cut -d'|' -f2 | sort); do
        NB=$((NB+1))
        LAST="$L"
    done
    for L in $(printf '%s\n' "$INVENT" | grep "^$T|$LAST|" | cut -d'|' -f3); do
        LAST_RC="$L"
    done
    KO_N_="$(printf '%s\n' "$INVENT" | grep "^$T|" | grep -cv '|0$')"
    VERDICT="ok"
    if [ "$KO_N_" -gt 0 ]; then
        VERDICT="$KO_N_ echec(s)"
        KO_TOT=$((KO_TOT+KO_N_))
    fi
    printf '  %-22s %5s  %-17s %-8s %s\n' "$T" "$NB" "$LAST" "$LAST_RC" "$VERDICT"
    LANCED=$((LANCED+1))
done

echo ""
echo "[3] Installes jamais lances"
MISS=0
for S in "$BASE"/*.sh; do
    [ -f "$S" ] || continue
    N="$(basename "$S" .sh)"
    case "$N" in run_state) continue ;; esac
    if ! printf '%s\n' "$INVENT" | grep -q "^$N|"; then
        printf '  [JAMAIS] %s\n' "$N"
        MISS=$((MISS+1))
    fi
done
[ "$MISS" -eq 0 ] && echo "  (aucun)"

echo ""
echo "[4] Synthese"
echo "  outils lances      : $LANCED"
echo "  installs silencieux: $MISS"
echo "  executions en echec: $KO_TOT (toutes traces)"
echo ""

return 0
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
