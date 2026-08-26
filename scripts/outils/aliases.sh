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
#   aliases LIST       mapping alias -> role (description courte)
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

# INSTALL/REMOVE ecrivent dans /system : elevation auto via su (deploy.sh)
case "$1" in
    INSTALL|install|REMOVE|remove)
        if ! is_root && command -v su > /dev/null 2>&1; then
            echo "[*] uid non root : relance automatique via su..."
            exec su -c "sh $(cd "$(dirname "$0")" && pwd)/$(basename "$0") $*"
        fi
        ;;
esac

system_rw_sh()
{
    for C in "$SCRIPTS/system_rw.sh" "$(dirname "$0")/system_rw.sh"; do
        [ -f "$C" ] && { echo "$C"; return 0; }
    done
    return 1
}

tool_list()
{
    echo "deploy amorce boot reboot remote_map front_digit launcher_toggle investigate stress_ram net_watch capture inspect_usb inspect_proc inspect_dev sync_usb disable_wireless media inspect_user inspect_system inspect_services inspect_display inspect_gui inspect_remote inspect_all device_info hdmi check_state conf_check help run_state recette selftest nreg config manage services hw_report show_key field_mode rotate_logs thermal vitals mem_tune cut_services system_rw front_led motd net_diag sys_diag sd_inspect sd_boot set_network set_time chroot_env busi macro tips swap_watch menu aliases"
}

is_ported()
{
    # $1 chemin : wrapper porte par cet outil ?
    [ -f "$1" ] && grep -q "^$MARKER\$" "$1" 2>/dev/null
}

# role court (6-10 mots) par outil, wording aligne sur docs/TOOLS.md ;
# sert a aliases LIST pour rendre le catalogue lisible d'un seul coup d'oeil
tool_desc()
{
    case "$1" in
        deploy)           echo "cycle de vie du kit : INSTALL, EXPOSE, logs" ;;
        amorce)           echo "bilan de demarrage et raccourcis post-boot" ;;
        boot)             echo "optimisations rejouees automatiquement a chaque demarrage" ;;
        reboot)           echo "redemarrage controle : immediat, programme, recovery, bootloader" ;;
        remote_map)       echo "remap telecommande IR via fichiers .kl" ;;
        front_digit)      echo "horloge afficheur frontal 4 digits et clignotements" ;;
        launcher_toggle)  echo "active ou coupe le lanceur TV Android" ;;
        investigate)      echo "collecte contextuelle complete pour diagnostic approfondi" ;;
        stress_ram)       echo "pression RAM controlee avec rapport memoire" ;;
        net_watch)        echo "daemon surveillance connexions avec ban iptables" ;;
        capture)          echo "captures ecran et logcat sauvegardees sur la cle" ;;
        inspect_usb)      echo "audit cle USB via adb : montage, droits" ;;
        inspect_proc)     echo "processus par PSS, candidats detournables pour RAM" ;;
        inspect_dev)      echo "capacites d'execution embarquee : runtimes, ABI, daemons" ;;
        sync_usb)         echo "synchronise le depot de la box vers cle" ;;
        disable_wireless) echo "coupe ou restaure Wi-Fi et Bluetooth" ;;
        media)            echo "inventaire des medias montes : USB, SD" ;;
        inspect_user)     echo "methodes de gestion utilisateurs Android, lecture seule" ;;
        inspect_system)   echo "RAM, CPU, processus, kernel en instantane" ;;
        inspect_services) echo "services init actifs compares a l'allegement prevu" ;;
        inspect_display)  echo "exploration de l'afficheur frontal 4 digits" ;;
        inspect_gui)      echo "capacites UI/HDMI, capture et URL plein ecran" ;;
        inspect_remote)   echo "exploration recepteur IR, input et tables .kl" ;;
        inspect_all)      echo "toutes les inspections core et exploration d'un coup" ;;
        device_info)      echo "inventaire materiel complet de la box par fonctionnalite" ;;
        hdmi)             echo "coupe ou retablit la sortie HDMI" ;;
        check_state)      echo "verdict rapide boitier, reseau, wireless, HDMI" ;;
        conf_check)       echo "valide la configuration et applique les optimisations" ;;
        help)             echo "aide complete embarquee de tous les outils" ;;
        run_state)        echo "historique des executions d'outils avec verdicts" ;;
        recette)          echo "recette fonctionnelle P1-P7 de la boite" ;;
        selftest)         echo "verifie que tous les outils repondent correctement" ;;
        nreg)             echo "non-regression executable multi-themes en un seul lancer" ;;
        config)           echo "editeur numerote de device.conf, GET/SET scriptables" ;;
        manage)           echo "services, pile web et ports en un coup" ;;
        services)         echo "demarre d'un coup web, swap, ssh, horloge" ;;
        hw_report)        echo "rapport materiel complet avec recherche constructeur web" ;;
        show_key)         echo "controle de la cle : dpk, temoins, traces" ;;
        field_mode)       echo "mode maintenance : coupe affichage et services TV" ;;
        rotate_logs)      echo "rotation et purge des traces sur la cle" ;;
        thermal)          echo "profils thermiques ECO/PERF et temperatures CPU" ;;
        vitals)           echo "releves RAM/CPU/swap instantanes, modes WATCH et CSV" ;;
        mem_tune)         echo "gere la chaine zram/swap, swappiness, LMK, logd" ;;
        cut_services)     echo "allegement des services et paquets non essentiels" ;;
        system_rw)        echo "passe /system en lecture-ecriture puis remet lecture-seule" ;;
        front_led)        echo "allume ou eteint la LED frontale" ;;
        motd)             echo "banniere personnalisee a l'ouverture de session adb" ;;
        net_diag)         echo "diagnostic reseau : ping, ports en ecoute, debit" ;;
        sys_diag)         echo "sante rapide : charge CPU, memoire, stockage" ;;
        sd_inspect)       echo "sante carte SD : montage, erreurs, espace" ;;
        sd_boot)          echo "examen de la carte SD en fin de boot" ;;
        set_network)      echo "applique IP, route et DNS sans coupure" ;;
        set_time)         echo "synchronise l'horloge depuis source AUTO ou manuelle" ;;
        chroot_env)       echo "mini-conteneurs chroot ARM isoles sous /data/chroots" ;;
        busi)             echo "busybox devoile : applets, puissances cachees, demos" ;;
        macro)            echo "sequences nommees d'actions rejouables en un coup" ;;
        tips)             echo "one-liners embarques, version executable de BEST-COMMANDES" ;;
        swap_watch)       echo "gardien resident swap/memoire : TRIM, RESCUE, THRASH" ;;
        menu)             echo "menu interactif numerote pour lancer les outils" ;;
        aliases)          echo "wrappers /system/bin : outils appelables sans su" ;;
        *)                echo "" ;;
    esac
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
    printf '%-18s %s\n' "ALIAS" "ROLE"
    for NAME in $(tool_list); do
        DEST="$BIN_DIR/$NAME"
        if is_ported "$DEST"; then
            printf '%-18s %s\n' "$NAME" "$(tool_desc "$NAME")"
        elif [ -e "$DEST" ]; then
            printf '%-18s %s\n' "$NAME" "(collision systeme, ignore)"
        fi
    done
    echo ""
    echo "cible commune des wrappers : $SCRIPTS/<alias>.sh (via su)"
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
        echo "  LIST      mapping alias -> role (description courte)"
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
