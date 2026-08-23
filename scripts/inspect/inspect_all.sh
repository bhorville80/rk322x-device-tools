#!/system/bin/sh
# inspect_all - rapport global des inspections, par classes.
#
# Deux classes d'outils :
#   COEUR  verifications utiles en routine (recette P5, suivi 24/7)
#   EXPLO  outils d'exploration one-shot (afficheur frontal, IR, capacites
#          UI, utilisateurs) : deja exploites ou sans objet en routine,
#          EXCLUS du rapport standard
#
# Usage:
#   inspect_all             rapport standard (COEUR uniquement)
#   inspect_all FORCE       tout (COEUR + EXPLO) APRES confirmation :
#                           liste presentee avec raison et attentes de
#                           chaque outil, puis validation o/N
#   inspect_all FORCE YES   idem sans question (usage scripte)
#   inspect_all LIST        classification seule, rien n'est execute
#   inspect_all HELP        cette aide

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" "$(dirname "$0")/.." /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

BASE="$(cd "$(dirname "$0")" && pwd)"
[ -d "$BASE/scripts" ] && BASE="$BASE/scripts"

SUMMARY=""
FAILS=0

# catalogue : CLASSE|LIBELLE|SCRIPT ARGS|RAISON|ATTENTES
# C = coeur (routine) ; X = exploration (exclu du standard)
catalog()
{
    cat << 'CATALOG'
C|check_state|check_state.sh|verdict global boitier/reseau/wireless/hdmi|synthese OK/KO/WARN ; attendu : eth0 UP + IP conf, wifi/bt desactives
C|inspect_system|inspect_system.sh|instantane memoire/cpu/processus/kernel|MemAvailable coherent, processus lourds identifiables
C|device_info|device_info.sh|inventaire materiel (SoC/RAM/eMMC/reseaux/IR)|puces detectees, RAM ~2 Go, eMMC lisible
C|inspect_services|inspect_services.sh|services init running vs allegement applique|gms/mediacenter/launcher absents si cut_services CUT actif
C|thermal|thermal.sh STATUS|temperatures + gouverneur CPU|gouverneur conforme au profil (eco conseille 24/7), temp < 70C
C|net_diag|net_diag.sh|connectivite : ip/route/dns/ping/ports|IP = conf, passerelle joignable, DNS resolvent
C|sys_diag|sys_diag.sh|sante rapide charge/memoire/stockage|charge raisonnable, stockage suffisant
C|inspect_usb|inspect_usb.sh|cle USB visible/ecriture/adbd USB+5555|cle montee rw, adb reseau ou USB actif
C|inspect_proc|inspect_proc.sh|processus par PSS : critiques/kit/deja coupees/candidats|candidats identifies avec traitement suggere (detournement RAM)
C|sd_inspect|sd_inspect.sh|carte SD : montage/erreurs/espace|montee (ro si SD_MOUNT_RO), pas d'erreur bloc
C|cut_services|cut_services.sh STATUS|etat de l'allegement services/paquets|listes coupees conformes a la configuration
C|front_led|front_led.sh STATUS|LED frontale|etat reporte (informatif)
X|inspect_gui|inspect_gui.sh STATUS|capacites UI/HDMI + SHOT/URL plein ecran|utile UNE fois pour valider l'affichage TV ; le chemin fonctionnel est assure par gui_server (8081)
X|inspect_display|inspect_display.sh|afficheur frontal 4 digits : noeuds/drivers/daemons|utile UNE fois pour choisir FD_FORMAT (front_digit PROBE) ; ensuite sans objet
X|inspect_remote|inspect_remote.sh|recepteur IR/devices input/layouts .kl|utile UNE fois pour identifier le device (rk29-keypad fait) ; apres : remote_map STATUS suffit
X|inspect_user|inspect_user.sh|methodes de creation d'utilisateurs Android|SANS OBJET sur cette box headless mono-utilisateur
CATALOG
}

run_section()
{
    TITLE="$1"; shift
    echo ""
    echo "============================================================"
    echo "  $TITLE"
    echo "============================================================"

    OUT="$(sh "$@" 2>&1)"
    RC=$?

    echo "$OUT"
    echo ""
    printf '>>> %-24s rc=%s\n' "$TITLE" "$RC"

    SUMMARY="$SUMMARY
$(printf '  %-26s rc=%s' "$TITLE" "$RC")"

    case "$RC" in
        0) ;;
        *) [ "$RC" -gt 1 ] && FAILS=$((FAILS+1)) ;;
    esac
}

show_list()
{
    ONLY="$1"
    printf '\n%-6s %-18s %-38s %s\n' "CLASSE" "OUTIL" "RAISON" "ATTENTES"
    printf '%s\n' "-----------------------------------------------------------------------------------------------"
    catalog | while IFS='|' read -r CL LBL ARGS RAISON ATT; do
        case "$ONLY" in
            COEUR) [ "$CL" = "C" ] || continue ;;
            EXPLO) [ "$CL" = "X" ] || continue ;;
        esac
        case "$CL" in
            C) CS="COEUR" ;;
            *) CS="EXPLO" ;;
        esac
        printf '%-6s %-18s %-38s %s\n' "$CS" "$LBL" "$RAISON" "$ATT"
    done
}

confirm_force()
{
    echo ""
    echo "=== INSPECT_ALL FORCE - outils qui vont tourner ==="
    echo ""
    show_list
    echo ""
    echo "Les outils EXPLO sont des analyses one-shot deja exploitees"
    echo "(ou sans objet) : leur sortie sert uniquement d'archive."
    printf 'Executer quand meme les %s outils ? [o/N] ' "$(catalog | wc -l | tr -dc '0-9')"
    return 0
}

help_show()
{
    echo ""
    echo "=== INSPECT_ALL - rapport global par classes ==="
    echo ""
    echo "Usage:"
    echo "  inspect_all             standard : coeur de verification (rapide)"
    echo "  inspect_all FORCE       tout, apres presentation (raison/attentes)"
    echo "                          et confirmation interactive"
    echo "  inspect_all FORCE YES   tout, sans question (scripts)"
    echo "  inspect_all LIST        classification sans execution"
    echo "  inspect_all HELP        cette aide"
}

main()
{
    MODE="$1"
    CONFIRM="$2"

    case "$MODE" in
        ""|RUN|run|COEUR|coeur)  WANT_X=0 ; INTERACTIVE=0 ;;
        FORCE|force)             WANT_X=1 ;;
        LIST|list)
            show_list
            echo ""
            return 0
            ;;
        HELP|-h|--help)
            help_show
            return 0
            ;;
        *)
            echo "argument inconnu : $MODE (voir : inspect_all HELP)"
            return 1
            ;;
    esac

    START_S="$(cut -d. -f1 /proc/uptime 2>/dev/null | tr -dc '0-9')"

    echo ""
    echo "### INSPECT GLOBAL - $(getprop ro.product.device 2>/dev/null) - Android $(getprop ro.build.version.release 2>/dev/null)"

    if [ "$WANT_X" -eq 1 ] && [ "$CONFIRM" != "YES" ]; then
        confirm_force
        A=""
        if [ -r /dev/tty ]; then
            IFS= read -r A < /dev/tty || A=""
        else
            echo ""
            echo "[ERREUR] pas de terminal interactif : utiliser 'inspect_all FORCE YES'"
            return 1
        fi
        case "$A" in
            o|O|y|Y) echo "confirme" ;;
            *)       echo "annule (rien execute)" ; return 0 ;;
        esac
    fi

    # catalogue via fichier temp : 'while done < file' reste dans le shell
    # courant (un pipe creerait un sous-shell et perdrait SUMMARY/FAILS)
    TMP_CAT="/data/local/tmp/inspect_all_catalog.$$"
    catalog > "$TMP_CAT" 2>/dev/null || TMP_CAT="/tmp/inspect_all_catalog.$$" && catalog > "$TMP_CAT"

    while IFS='|' read -r CL LBL ARGS RAISON ATT; do
        [ "$WANT_X" -eq 0 ] && [ "$CL" != "C" ] && continue

        SH_NAME="$ARGS"
        SET_ARGS=""
        case "$ARGS" in
            *" "*) SH_NAME="${ARGS%% *}" ; SET_ARGS="${ARGS#* }" ;;
        esac

        echo ""
        echo "--- [$LBL] $RAISON"
        echo "---     attentes : $ATT"
        if [ -n "$SET_ARGS" ]; then
            # shellcheck disable=SC2086
            run_section "$LBL" "$BASE/$SH_NAME" $SET_ARGS
        else
            run_section "$LBL" "$BASE/$SH_NAME"
        fi
    done < "$TMP_CAT"
    rm -f "$TMP_CAT"

    END_S="$(cut -d. -f1 /proc/uptime 2>/dev/null | tr -dc '0-9')"
    DUREE=""
    if [ -n "$START_S" ] && [ -n "$END_S" ]; then
        DUREE=" ($((END_S - START_S))s)"
    fi

    echo ""
    echo "============================================================"
    echo "  SYNTHESE$DUREE"
    echo "============================================================"
    echo "$SUMMARY"
    echo ""
    if [ "$WANT_X" -eq 0 ]; then
        echo "  [--] excludes (exploration one-shot) : inspect_gui, inspect_display,"
        echo "       inspect_remote, inspect_user  ->  inspect_all FORCE pour les inclure"
        echo ""
    fi
    if [ "$FAILS" -gt 0 ]; then
        echo "  [WARN] $FAILS outil(s) en anomalie (rc>=2)"
    else
        echo "  [ OK ] tous les outils ont repondu"
    fi
    echo ""
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
