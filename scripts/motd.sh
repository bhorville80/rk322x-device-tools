#!/system/bin/sh
# motd - message d'accueil affiche a l'ouverture d'un shell adb interactif
# (equivalent du MOTD ssh). Le texte vit dans /data/etc/motd (modifiable
# sans remount) ; seul un petit crochet marque dans /system/etc/mkshrc est
# pose/enleve par cet outil (remount automatique via system_rw).
#
# NB : comme le MOTD ssh, le texte n'apparait que sur un shell interactif :
#      les commandes scriptees (adb shell cmd, dpk...) restent propres.
#
# Usage: motd.sh <STATUS|SHOW|SET|FILE|DEFAULT|ON|OFF>

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

for B in "$(dirname "$0")" "$(dirname "$0")/core" /data/scripts /data/scripts/core; do
    if [ -f "$B/core/config.sh" ]; then
        . "$B/core/config.sh"
        break
    fi
done

MKSHRC="${RK_MKSHRC:-/system/etc/mkshrc}"
MOTD_DIR="${RK_MOTD_DIR:-/data/etc}"
MOTD="$MOTD_DIR/motd"
MARK_B="# >>> rk322x-motd >>>"
MARK_E="# <<< rk322x-motd <<<"

hook_present()
{
    [ -f "$MKSHRC" ] && grep -q "$MARK_B" "$MKSHRC" 2>/dev/null
}

rw_system()
{
    SR="$(dirname "$0")/system_rw.sh"
    [ -f "$SR" ] || SR="/data/scripts/system_rw.sh"
    sh "$SR" "$1" > /dev/null 2>&1
}

do_status()
{
    echo ""
    echo "=== MOTD (message adb shell) ==="

    H="--"
    hook_present && H="oui"
    echo "  Crochet mkshrc : $H ($MKSHRC)"

    if [ -s "$MOTD" ]; then
        NB="$(grep -c . "$MOTD")"
        echo "  Message        : $MOTD ($NB lignes)"
    else
        echo "  Message        : vide/absent ($MOTD)"
    fi

    echo ""
    return 0
}

do_show()
{
    if [ -s "$MOTD" ]; then
        cat "$MOTD"
    else
        echo "[ -- ] aucun message defini ($MOTD)"
    fi
    return 0
}

do_set()
{
    [ -n "$*" ] || { echo "[ERREUR] usage : motd SET ligne de texte"; return 1; }
    mkdir -p "$MOTD_DIR" 2>/dev/null
    printf '%s\n' "$*" > "$MOTD" || { echo "[ERREUR] ecriture impossible"; return 1; }
    echo "[ OK ] message enregistre ($(grep -c . "$MOTD") ligne[s])"
    hook_present || echo "[ INFO ] crochet absent : lancer 'motd ON' pour l'activer"
    return 0
}

do_file()
{
    SRC="$1"
    [ -f "$SRC" ] || { echo "[ERREUR] fichier introuvable : $SRC"; return 1; }
    mkdir -p "$MOTD_DIR" 2>/dev/null
    cp -f "$SRC" "$MOTD" && echo "[ OK ] message installe depuis $SRC" \
                          || { echo "[ERREUR] copie echouee"; return 1; }
    hook_present || echo "[ INFO ] crochet absent : lancer 'motd ON'"
    return 0
}

do_default()
{
    mkdir -p "$MOTD_DIR" 2>/dev/null
    IF="$(config_get INTERFACE eth0)"
    IP=""
    IP="$(ip -4 addr show "$IF" 2>/dev/null | sed -n 's/.*inet \([0-9.]*\).*/\1/p' | head -n 1)"
    VER="$(sed -n 's/^DEPLOY_VERSION=//p' "$(dirname "$0")/../config/device.conf" 2>/dev/null | head -n 1 | tr -d '\r')"
    [ -z "$VER" ] && VER="$(sed -n 's/^DEPLOY_VERSION=//p' /data/scripts/config/device.conf 2>/dev/null | head -n 1 | tr -d '\r')"

    {
        echo "=============================================="
        echo "  $(getprop ro.product.device 2>/dev/null) - $(getprop ro.product.model 2>/dev/null)"
        echo "  Android $(getprop ro.build.version.release 2>/dev/null) / tools v${VER:-?}"
        echo "  ip      : ${IP:-inconnue} ($IF)"
        echo "  heure   : $(date '+%Y-%m-%d %H:%M:%S')"
        echo "----------------------------------------------"
        echo "  amorce          etat + commandes"
        echo "  check_state     reseau/wireless/HDMI"
        echo "  inspect_all     rapport global"
        echo "  help            aide complete"
        echo "=============================================="
    } > "$MOTD" 2>/dev/null

    echo "[ OK ] banniere par defaut generee -> $MOTD"
    hook_present || echo "[ INFO ] crochet absent : lancer 'motd ON'"
    return 0
}

do_on()
{
    if ! require_root; then
        return 1
    fi

    if [ ! -f "$MKSHRC" ]; then
        echo "[ERREUR] $MKSHRC introuvable (shell mksh attendu sur ce firmware)"
        return 1
    fi

    mkdir -p "$MOTD_DIR" 2>/dev/null
    if [ ! -s "$MOTD" ]; then
        do_default > /dev/null 2>&1
        echo "[*] aucun message defini -> banniere par defaut generee"
    fi

    if hook_present; then
        echo "[ -- ] crochet deja present"
    else
        rw_system RW
        {
            echo "$MARK_B"
            echo '[ -r '"$MOTD"' ] && cat '"$MOTD"
            echo "$MARK_E"
        } >> "$MKSHRC" 2>/dev/null
        rw_system RO

        if hook_present; then
            echo "[ OK ] crochet installe dans $MKSHRC"
        else
            echo "[ERREUR] installation du crochet echouee (voir ci-dessus)"
            return 1
        fi
    fi

    echo "[ OK ] actif : visible au prochain 'adb shell' interactif"
    return 0
}

do_off()
{
    if ! require_root; then
        return 1
    fi

    if ! hook_present; then
        echo "[ -- ] rien a desactiver"
        return 0
    fi

    rw_system RW
    sed -i "/^$MARK_B\$/,/^$MARK_E\$/d" "$MKSHRC" 2>/dev/null
    rw_system RO

    if hook_present; then
        echo "[ERREUR] crochet toujours present"
        return 1
    fi
    echo "[ OK ] crochet retire (message conserve dans $MOTD)"
    return 0
}

usage()
{
    echo ""
    echo "Usage: motd <STATUS|SHOW|SET <texte>|FILE <fichier>|DEFAULT|ON|OFF>"
    echo ""
    echo "  STATUS   crochet + message courant"
    echo "  SHOW     affiche le message"
    echo "  SET <t>  definit le message (une ligne)"
    echo "  FILE <f> definit le message depuis un fichier (adb push puis FILE)"
    echo "  DEFAULT  genere une banniere (device/ip/outils)"
    echo "  ON       active (pose le crochet dans /system/etc/mkshrc)"
    echo "  OFF      desactive (retire le crochet, garde le message)"
    echo ""
    return 1
}

case "$1" in
    ""|STATUS|status)   do_status ;;
    SHOW|show)          do_show ;;
    SET|set)            shift; do_set "$@" ;;
    FILE|file)          shift; do_file "$1" ;;
    DEFAULT|default)    do_default ;;
    ON|on)              do_on ;;
    OFF|off)            do_off ;;
    HELP|help|-h|--help) usage ;;
    *)                  usage ;;
esac
