#!/system/bin/sh
# aliases - raccourcis pour l'utilisateur 2000 (adb shell).
#
# Depose un petit wrapper par outil dans /system/bin : taper `help`,
# `recette`, `manage`, `nreg`... depuis adb shell equivaut a
#   su -c "sh /data/scripts/<outil>.sh <args>"
#
# Securite :
#   - un fichier /system/bin/<nom> EXISTANT mais non genere par cet outil
#     n'est JAMAIS ecrase (binaire systeme, ex : reboot) -> signale en
#     COLLISION et laisse intact ;
#   - les wrappers portes ont une marque identifiantable (MAJ/REMOVE sur).
#
# Usage:
#   aliases INSTALL    depose/met a jour les wrappers (remount rw auto)
#   aliases REMOVE     retire tous les wrappers portes
#   aliases STATUS     installes / manquants / collisions
#   aliases LIST       mapping nom -> cible
#   aliases HELP       cette aide
#
# Note : installation unique, persistant aux reboots (ecrit dans /system).
# Limitation : les arguments a espaces ne sont pas preserves par su.

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

BIN_DIR="/system/bin"
MARKER="# rk322x-tools alias"
SCRIPTS="/data/scripts"

command -v is_root >/dev/null 2>&1 || is_root() \
    { case "$(id -u 2>/dev/null)" in 0) return 0 ;; esac; case "$(id 2>/dev/null)" in "uid=0("*) return 0 ;; esac; return 1; }

system_rw_sh()
{
    for C in "$SCRIPTS/system_rw.sh" "$(dirname "$0")/system_rw.sh"; do
        [ -f "$C" ] && { echo "$C"; return 0; }
    done
    return 1
}

tool_list()
{
    echo "deploy amorce boot reboot remote_map front_digit launcher_toggle investigate stress_ram net_watch capture inspect_usb inspect_proc inspect_dev sync_usb disable_wireless media inspect_user inspect_system inspect_services inspect_display inspect_gui inspect_remote inspect_all device_info hdmi check_state conf_check help run_state recette selftest nreg config manage hw_report show_key field_mode rotate_logs thermal vitals mem_tune cut_services system_rw front_led motd net_diag sys_diag sd_inspect sd_boot set_network set_time menu aliases"
}

is_ported()
{
    # $1 chemin : wrapper porte par cet outil ?
    [ -f "$1" ] && grep -q "^$MARKER\$" "$1" 2>/dev/null
}

wrapper_body()
{
    NAME="$1"
    echo "#!/system/bin/sh"
    echo "$MARKER"
    echo "# raccourci rk322x-device-tools (aliases INSTALL) - appelle avec su"
    echo "exec su -c \"sh $SCRIPTS/$NAME.sh \$*\""
}

do_install()
{
    if ! is_root; then
        echo "[ERREUR] privileges root requis : su -c \"sh $0 INSTALL\""
        return 1
    fi

    SRW="$(system_rw_sh)" || { echo "[ERREUR] system_rw.sh introuvable"; return 1; }
    sh "$SRW" RW > /dev/null 2>&1 || { echo "[ERREUR] /system non inscriptible (system_rw RW)"; return 1; }

    OK_=0 ; SKIP_=0 ; KO_=0
    for NAME in $(tool_list); do
        [ -f "$SCRIPTS/$NAME.sh" ] || { echo "[WARN] $NAME.sh absent de $SCRIPTS, saute"; KO_=$((KO_+1)); continue; }
        DEST="$BIN_DIR/$NAME"
        if [ -e "$DEST" ] && ! is_ported "$DEST"; then
            echo "[COLLISION] $DEST existe deja (binaire systeme) -> intact"
            SKIP_=$((SKIP_+1))
            continue
        fi
        wrapper_body "$NAME" > "$DEST" 2>/dev/null && chmod 755 "$DEST" 2>/dev/null \
            && OK_=$((OK_+1)) \
            || { echo "[ ERREUR ] ecriture $DEST"; KO_=$((KO_+1)); }
    done

    sh "$SRW" RO > /dev/null 2>&1

    echo ""
    echo "=== RESUME ALIASES ==="
    echo "  poses/mis a jour : $OK_"
    echo "  collisions       : $SKIP_ (intacts)"
    echo "  erreurs          : $KO_"
    echo ""
    echo "essai : adb shell -> help STATUS | manage | nreg"
    [ "$KO_" -eq 0 ]; return $?
}

do_remove()
{
    if ! is_root; then
        echo "[ERREUR] privileges root requis : su -c \"sh $0 REMOVE\""
        return 1
    fi

    SRW="$(system_rw_sh)" || { echo "[ERREUR] system_rw.sh introuvable"; return 1; }
    sh "$SRW" RW > /dev/null 2>&1 || { echo "[ERREUR] /system non inscriptible"; return 1; }

    N_=0
    for NAME in $(tool_list); do
        DEST="$BIN_DIR/$NAME"
        if is_ported "$DEST"; then
            rm -f "$DEST" && N_=$((N_+1))
        fi
    done

    sh "$SRW" RO > /dev/null 2>&1
    echo "[ OK ] $N_ wrapper(s) retire(s)"
    return 0
}

do_status()
{
    P_=0 ; M_=0 ; C_=0
    for NAME in $(tool_list); do
        DEST="$BIN_DIR/$NAME"
        if is_ported "$DEST"; then
            P_=$((P_+1))
        elif [ -e "$DEST" ]; then
            C_=$((C_+1))
        else
            M_=$((M_+1))
        fi
    done
    echo "=== ALIASES STATUS (uid $(id -u 2>/dev/null)) ==="
    echo "  wrappers portes      : $P_"
    echo "  collisions systemes  : $C_ (non touches)"
    echo "  pas encore installes : $M_ (aliases INSTALL)"
    [ "$M_" -eq 0 ]; return $?
}

do_list()
{
    printf '%-18s %s\n' "ALIAS" "CIBLE"
    for NAME in $(tool_list); do
        DEST="$BIN_DIR/$NAME"
        if is_ported "$DEST"; then
            printf '%-18s %s\n' "$NAME" "$SCRIPTS/$NAME.sh"
        elif [ -e "$DEST" ]; then
            printf '%-18s %s\n' "$NAME" "(collision systeme, ignore)"
        fi
    done
}

case "$1" in
    ""|HELP|-h|--help)
        echo ""
        echo "Usage: aliases <INSTALL|REMOVE|STATUS|LIST|HELP>"
        echo ""
        echo "  INSTALL   depose un wrapper /system/bin/<outil> par outil du depot"
        echo "            (depuis adb shell uid 2000 : help, manage, nreg, recette...)"
        echo "  REMOVE    retire tous les wrappers portes"
        echo "  STATUS    installes / collisions / manquants"
        echo "  LIST      mapping alias -> cible"
        echo ""
        echo "Un binaire systeme existant (ex : reboot) n'est jamais ecrase."
        echo ""
        ;;
    INSTALL|install)  do_install ;;
    REMOVE|remove)    do_remove ;;
    STATUS|status)    do_status ;;
    LIST|list)        do_list ;;
    *)
        echo "argument inconnu : $1 (voir : aliases HELP)"
        exit 1
        ;;
esac
