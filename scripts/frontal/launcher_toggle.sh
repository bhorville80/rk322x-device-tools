#!/system/bin/sh
# launcher_toggle - active/desactive le lanceur d'applications (UI TV).
#
# La box est exploitee headless : le launcher Swelb fait partie des paquets
# coupes par cut_services (PACKAGES_DISABLE). Pour rendre des applications
# VISIBLES sur l'ecran TV (voie A/B de inspect_dev), ce tool :
#   ON    retire le launcher des paquets coupes, le reactive (pm enable)
#         et verifie qu'il repond ; les apps installees apparaissent.
#   OFF   remet l'etat headless : launcher arrete + desactive via
#         cut_services CUT (la liste PACKAGES_DISABLE du device.conf reste
#         la source de verite - rien n'est code en dur ici).
#   STATUS  etat courant : launcher actif ? quel paquet ? apps tierces ?
#
# Usage:
#   launcher_toggle STATUS | ON | OFF | HELP
#
# Prerequis : root (su) pour pm enable/disable/am. Lecture seule sinon.
# NOTE : apres ON, un appui HOME sur la telecommande affiche le lanceur.

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" "$(dirname "$0")/.." /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

for B in "$(dirname "$0")/core" "$(dirname "$0")/../core" /data/scripts/core; do
    [ -f "$B/config.sh" ] && { . "$B/config.sh"; break; }
done

BASE="$(cd "$(dirname "$0")" && pwd)"

ok()   { printf '  [ OK ] %s\n' "$1"; }
warn() { printf '  [WARN] %s\n' "$1"; }

is_root() { case "$(id -u 2>/dev/null)" in 0) return 0 ;; esac; return 1; }

LAUNCHERS="com.Swelb.zonglaunher com.android.launcher3 com.google.android.tvlauncher"

enabled_pkgs()
{
    pm list packages -e 2>/dev/null | sed 's/^package://' | sort
}

disabled_list()
{
    config_get PACKAGES_DISABLE ""
}

find_launcher()
{
    # echo le premier launcher present sur la box, rc 1 si aucun
    for L_ in $LAUNCHERS; do
        if enabled_pkgs | grep -qx "$L_" || \
           pm list packages -d 2>/dev/null | grep -q "^package:$L_$"; then
            echo "$L_"
            return 0
        fi
    done
    return 1
}


list_has_word()  # $1=liste espace  $2=mot -> rc
{
    printf '%s\n' "$1" | tr -s ' ' '\n' | grep -qx "$2"
}

list_del_word()  # $1=liste  $2=mot -> liste sans le mot (normalisee)
{
    printf '%s\n' "$1" | tr -s ' ' '\n' | grep -vx "$2" \
        | grep -v '^$' | tr '\n' ' '
}

do_status()
{
    echo ""
    echo "=== LAUNCHER TOGGLE ==="
    L_="$(find_launcher)"
    if [ -z "$L_" ]; then
        warn "aucun launcher connu present sur la box"
        echo "       installer un APK launcher ou ajouter le paquet a"
        echo "       LAUNCHERS dans launcher_toggle.sh"
        echo ""
        return 1
    fi
    row_pkg() { printf '  %-22s %s\n' "$1" "$2"; }
    row_pkg "paquet" "$L_"
    if enabled_pkgs | grep -qx "$L_"; then
        row_pkg "etat pm" "ENABLED"
    else
        row_pkg "etat pm" "DISABLED (headless)"
    fi
    if disabled_list | grep -qw "$L_"; then
        row_pkg "PACKAGES_DISABLE" "contient le launcher -> CUT le retabira OFF"
    else
        row_pkg "PACKAGES_DISABLE" "n'y figure pas -> CUT laissera ON"
    fi
    NB_="$(pm list packages -3 2>/dev/null | wc -l)"
    row_pkg "apps tierces" "${NB_:-0}"
    echo ""
    return 0
}

do_on()
{
    L_="$(find_launcher)" || { warn "aucun launcher connu present" ; return 1 ; }
    echo "[*] activation du launcher : $L_"
    pm enable "$L_" > /dev/null 2>&1 || { warn "pm enable refuse (root ?)" ; return 1 ; }

    # retirer de PACKAGES_DISABLE pour que cut_services CUT ne recoupe pas :
    # edition device.conf cote box uniquement si la cle y figure
    CF="${CONFIG_FILE:-/data/scripts/config/device.conf}"
    if [ -f "$CF" ]; then
        CUR="$(sed -n 's/^PACKAGES_DISABLE=//p' "$CF" | head -n 1 | tr -d '\r')"
        if list_has_word "$CUR" "$L_"; then
            NEW="$(list_del_word "$CUR" "$L_")"
            sed -i "s|^PACKAGES_DISABLE=.*|PACKAGES_DISABLE=$NEW|" "$CF" 2>/dev/null
            ok "retire de PACKAGES_DISABLE ($CF)"
        fi
    fi

    # relancer maintenant sans attendre un reboot
    am start -a android.intent.action.MAIN -c android.intent.category.HOME \
        > /dev/null 2>&1 && ok "intent HOME envoye : le lanceur doit s'afficher sur la TV" \
        || warn "am start refuse (root ?) - appuyer HOME sur la telecommande"
    ok "launcher ON"
    echo ""
    return 0
}

do_off()
{
    L_="$(find_launcher)" || { warn "aucun launcher connu present" ; return 1 ; }
    echo "[*] retour headless : $L_"
    am force-stop "$L_" > /dev/null 2>&1 && ok "force-stop"
    CF="${CONFIG_FILE:-/data/scripts/config/device.conf}"
    if [ -f "$CF" ]; then
        CUR="$(sed -n 's/^PACKAGES_DISABLE=//p' "$CF" | head -n 1 | tr -d '\r')"
        if ! list_has_word "$CUR" "$L_"; then
            sed -i "s|^PACKAGES_DISABLE=.*|PACKAGES_DISABLE=$CUR $L_|" "$CF" 2>/dev/null
            ok "ajoute a PACKAGES_DISABLE ($CF)"
        fi
    fi
    pm disable-user --user 0 "$L_" > /dev/null 2>&1 \
        && ok "pm disable-user" \
        || warn "pm disable refuse (root ?)"
    sh "$BASE/cut_services.sh" CUT > /dev/null 2>&1 \
        && ok "cut_services CUT rejoue (etat coherent)" \
        || warn "cut_services indisponible (rejouer manuellement)"
    echo ""
    return 0
}

case "$1" in
    HELP|-h|--help)
        sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
        exit 0 ;;
esac

main()
{
    case "$1" in
        ""|STATUS|status) do_status ;;
        ON|on)   is_root || { echo "[ERREUR] root requis (su -c \"sh $0 ON\")" ; return 1 ; } ; do_on ;;
        OFF|off) is_root || { echo "[ERREUR] root requis (su -c \"sh $0 OFF\")" ; return 1 ; } ; do_off ;;
        *) echo "option inconnue : $1 (voir launcher_toggle HELP)" ; return 1 ;;
    esac
}

if [ "$RUNLOG_LOADED" -eq 1 ] && runlog_start "$SCRIPT_ID"; then
    main "$@" >> "$RUNLOG_FILE" 2>&1 ; RC=$?
    runlog_end "$RC" ; cat "$RUNLOG_FILE"
else
    main "$@" ; RC=$?
fi
exit "$RC"
