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

motd_avail_mo()
{
    A="$(sed -n 's/^MemAvailable: *\([0-9]*\) kB/\1/p' /proc/meminfo 2>/dev/null | head -n 1)"
    case "$A" in ''|*[!0-9]*) A="$(sed -n 's/^MemFree: *\([0-9]*\) kB/\1/p' /proc/meminfo 2>/dev/null | head -n 1)" ;; esac
    case "$A" in ''|*[!0-9]*) echo "?" ;; *) echo $((A / 1024)) ;; esac
}

motd_uptime()
{
    UP="$(cut -d' ' -f1 /proc/uptime 2>/dev/null | cut -d. -f1)"
    case "$UP" in ''|*[!0-9]*) echo "?"; return ;; esac
    printf '%dh%02dm' $((UP / 3600)) $(( (UP % 3600) / 60 ))
}

motd_recette_line()
{
    F=""
    for d in /mnt/media_rw/*; do
        [ -f "$d/log/recette_last.txt" ] && { F="$d/log/recette_last.txt"; break; }
    done
    [ -z "$F" ] && [ -f /data/local/tmp/log/recette_last.txt ] && F=/data/local/tmp/log/recette_last.txt
    [ -n "$F" ] || return 0
    V="$(grep '^verdict' "$F" 2>/dev/null | tail -n 1)"
    [ -n "$V" ] && printf '%s' "$V"
}

motd_boot_state()
{
    if [ -f /system/etc/init/rk322x_tools.rc ]; then
        echo "actif (hook init)"
    elif grep -q 'RK322X TOOLS' /system/etc/install-recovery.sh 2>/dev/null; then
        echo "actif (install-recovery)"
    else
        echo "inactif -> boot INSTALL"
    fi
}

# service en ecoute sur le port $1 ? netstat d'abord, puis /proc/net/tcp[6]
# (port hexa, etat 0A=LISTEN) : meme demarche que la sonde de la recette
motd_port_listen()
{
    P_="$1"
    if command -v netstat > /dev/null 2>&1; then
        netstat -tln 2>/dev/null | grep -q ":$P_ " && return 0
    fi
    if command -v busybox > /dev/null 2>&1; then
        PH="$(busybox printf '%04X' "$P_" 2>/dev/null)"
    else
        PH="$(printf '%04X' "$P_" 2>/dev/null)"
    fi
    [ -n "$PH" ] && grep -qi ":$PH .* 0A " /proc/net/tcp 2>/dev/null && return 0
    grep -qi ":$PH .* 0A " /proc/net/tcp6 2>/dev/null && return 0
    return 1
}

motd_port_tag()
{
    if motd_port_listen "$1"; then printf '[OK]' ; else printf '[--]' ; fi
}

# mention token si server/token protege l'API/GUI
motd_token_note()
{
    for d in /mnt/media_rw/*; do
        [ -f "$d/deploy.sh" ] || continue
        [ -f "$d/server/token" ] && { printf '/token' ; return 0 ; }
    done
    return 0
}

# ligne de cadre : texte tronque puis complete a largeur fixe, ASCII seul
MOTD_W=49
motd_row()
{
    T="$(printf '%s' "$1" | cut -c1-"$MOTD_W")"
    printf '| %s |\n' "$(printf '%-'"$MOTD_W"'s' "$T")"
}
motd_rule_eq() { printf '+%s+\n' "$(printf '%*s' 51 '' | tr ' ' '=')" ; }
motd_rule_dash() { printf '+%s+\n' "$(printf '%*s' 51 '' | tr ' ' '-')" ; }

do_default()
{
    mkdir -p "$MOTD_DIR" 2>/dev/null
    IF="$(config_get INTERFACE eth0)"
    IP="$(ip -4 addr show "$IF" 2>/dev/null | sed -n 's/.*inet \([0-9.]*\).*/\1/p' | head -n 1)"
    VER="$(sed -n 's/^DEPLOY_VERSION=//p' "$(dirname "$0")/../config/device.conf" 2>/dev/null | head -n 1 | tr -d '\r')"
    [ -z "$VER" ] && VER="$(sed -n 's/^DEPLOY_VERSION=//p' /data/scripts/config/device.conf 2>/dev/null | head -n 1 | tr -d '\r')"
    RECETTE="$(motd_recette_line)"

    DEV="$(getprop ro.product.device 2>/dev/null)"
    MODEL="$(getprop ro.product.model 2>/dev/null)"
    AND="$(getprop ro.build.version.release 2>/dev/null)"
    ID_LINE="$DEV"
    [ -n "$MODEL" ] && [ "$MODEL" != "$DEV" ] && ID_LINE="$ID_LINE / $MODEL"
    [ -n "$AND" ] && ID_LINE="$ID_LINE - Android $AND"

    if motd_port_listen 8000; then
        PANEL="http://${IP:-<ip>}:8000"
        PORTS="web $(motd_port_tag 8000)   api $(motd_port_tag 8080)$(motd_token_note)   gui $(motd_port_tag 8081)"
    else
        PANEL="arrete -> amorce EXPOSE"
        PORTS="8000 [--]   8080 [--]   8081 [--]"
    fi

    {
        motd_rule_eq
        motd_row "RK322X DEVICE TOOLS  v${VER:-?}"
        [ -n "$ID_LINE" ] && motd_row "$ID_LINE"
        motd_rule_eq
        motd_row "PANNEAU WEB : $PANEL"
        motd_row "services    : $PORTS"
        motd_rule_dash
        motd_row "ip ${IP:-inconnue} ($IF)   up $(motd_uptime)"
        motd_row "ram dispo $(motd_avail_mo) Mo   charge $(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)"
        motd_row "boot $(motd_boot_state)"
        [ -n "$RECETTE" ] && motd_row "recette $RECETTE"
        motd_rule_dash
        motd_row "aide: help   etat: amorce   global: inspect_all"
        motd_row "(genere $(date '+%m-%d %H:%M') - motd DEFAULT)"
        motd_rule_eq
    } > "$MOTD" 2>/dev/null

    echo "[ OK ] banniere generee -> $MOTD ($(grep -c . "$MOTD" 2>/dev/null) lignes)"
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
    echo "  DEFAULT  genere la banniere (panneau/ports/ip/ram/boot/recette)"
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
