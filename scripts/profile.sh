#!/system/bin/sh
# profile - gestion des profils de configuration (config/profiles/*.conf).
#
# Un profil est un fichier de cles/valeurs qui SURCHARGE device.conf quand
# PROFILE=<nom> est actif (mecanisme core/config.sh : la valeur du profil
# gagne sur la valeur de base).
#
# Usage:
#   profile                  ou CURRENT : profil actif + liste disponible
#   profile LIST             profils disponibles
#   profile SHOW <nom>       valeurs du profil
#   profile DIFF <nom>       ecarts du profil vs config de base
#   profile SWITCH <nom>     active le profil (ecrit PROFILE=<nom>)
#   profile OFF              revient a la config de base (PROFILE vide)
#   profile SAVE <nom>       capture la config de base comme nouveau profil
#   profile HELP             cette aide
#
# Apres SWITCH, appliquer ce qui depend de la config :
#   set_network (reseau), mem_tune OPTIMIZE (memoire), cut_services CUT,
#   puis deploy STOP && deploy EXPOSE si les serveurs doivent repartir.

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
for B in "$(dirname "$0")/core" "$(dirname "$0")/../scripts/core" /data/scripts/core; do
    if [ -f "$B/config.sh" ]; then
        . "$B/config.sh"
        CFG_LOADED=1
        break
    fi
done

BASE="$(cd "$(dirname "$0")" && pwd)"
CONF="${CONFIG_FILE:-/data/scripts/config/device.conf}"

if [ ! -f "$CONF" ]; then
    echo "[ERREUR] device.conf introuvable ($CONF)"
    exit 1
fi

CONF_DIR="$(dirname "$CONF")"
PROF_DIR="$CONF_DIR/profiles"

cur_profile()
{
    sed -n 's/^PROFILE=//p' "$CONF" 2>/dev/null | head -n 1 | tr -d '\r'
}

valid_name()
{
    case "$1" in
        ''|*[!A-Za-z0-9_-]*) return 1 ;;
    esac
    return 0
}

list_profiles()
{
    ls -1 "$PROF_DIR"/*.conf 2>/dev/null | while IFS= read -r F; do
        basename "$F" .conf
    done
}

write_key_in_conf()
{
    # PROFILE=<valeur> dans device.conf (awk : pas d'echappement sed)
    K="PROFILE"
    V="$1"
    TMP="$CONF.tmp.$$"
    if awk -v k="$K" -v v="$V" '
        BEGIN { done=0 }
        !done && $0 ~ "^"k"=" { print k "=" v ; done=1 ; next }
        { print }
        END { if (!done) print k "=" v }
    ' "$CONF" > "$TMP" 2>/dev/null; then
        mv -f "$TMP" "$CONF" 2>/dev/null || { rm -f "$TMP"; return 1; }
    else
        rm -f "$TMP"
        return 1
    fi
}

do_show()
{
    N="$1"
    valid_name "$N" || { echo "[KO] nom invalide : $N" ; return 1 ; }
    F="$PROF_DIR/$N.conf"
    [ -f "$F" ] || { echo "[KO] profil inexistant : $N (profile LIST)" ; return 1 ; }
    echo ""
    echo "=== PROFIL $N ($F) ==="
    grep -E '^[A-Z_]+=' "$F" 2>/dev/null | sed 's/^/  /'
    echo ""
    return 0
}

do_diff()
{
    N="$1"
    valid_name "$N" || { echo "[KO] nom invalide : $N" ; return 1 ; }
    F="$PROF_DIR/$N.conf"
    [ -f "$F" ] || { echo "[KO] profil inexistant : $N" ; return 1 ; }

    CUR="$(cur_profile)"
    [ "$CUR" = "$N" ] && echo "[i] attention : ce profil est ACTIF"

    echo ""
    echo "=== DIFF profil '$N' vs base ==="
    grep -E '^[A-Z_]+=' "$F" 2>/dev/null | while IFS= read -r LINE; do
        K="${LINE%%=*}"
        V="${LINE#*=}"
        B_="$(sed -n "s/^$K=//p" "$CONF" | head -n 1 | tr -d '\r')"
        if [ "$B_" != "$V" ]; then
            printf '  %-20s base=%-18s profil=%s\n' "$K" "${B_:-<vide>}" "$V"
        fi
    done
    echo ""
    return 0
}

do_switch()
{
    N="$1"
    valid_name "$N" || { echo "[KO] nom invalide : $N" ; return 1 ; }
    [ -f "$PROF_DIR/$N.conf" ] || { echo "[KO] profil inexistant : $N" ; return 1 ; }
    if write_key_in_conf "$N"; then
        echo "[ OK ] PROFILE=$N"
        echo "[i] application selon les cles du profil :"
        echo "      set_network          (si IP/GATEWAY/DNS changes)"
        echo "      mem_tune OPTIMIZE    (si MEM_*/LOGD_* changes)"
        echo "      cut_services CUT     (si SERVICES_CUT*/PACKAGES_* changes)"
        echo "      deploy STOP ; deploy EXPOSE   (pile web avec la nouvelle conf)"
    else
        echo "[ERREUR] ecriture impossible dans $CONF"
        return 1
    fi
}

do_off()
{
    if write_key_in_conf ""; then
        echo "[ OK ] PROFILE= (config de base active)"
    else
        echo "[ERREUR] ecriture impossible"
        return 1
    fi
}

do_save()
{
    N="$1"
    valid_name "$N" || { echo "[KO] nom invalide (A-Za-z0-9._-) : $N" ; return 1 ; }
    mkdir -p "$PROF_DIR" 2>/dev/null || { echo "[ERREUR] $PROF_DIR inaccessible" ; return 1 ; }
    F="$PROF_DIR/$N.conf"
    [ -f "$F" ] && { echo "[KO] existe deja : $F (editer ou choisir un autre nom)" ; return 1 ; }
    {
        echo "# profil '$N' capture depuis la config de base le $(date '+%Y-%m-%d %H:%M:%S')"
        grep -E '^[A-Z_]+=' "$CONF" 2>/dev/null | grep -v '^PROFILE='
    } > "$F" || { echo "[ERREUR] ecriture impossible" ; return 1 ; }
    echo "[ OK ] profil cree : $F"
    echo "[i] editer les valeurs a surcharger, puis : profile SWITCH $N"
    return 0
}

help_show()
{
    echo ""
    echo "=== PROFILE - profils de configuration ==="
    echo ""
    echo "Usage:"
    echo "  profile                actif + disponibles"
    echo "  profile LIST           profils disponibles"
    echo "  profile SHOW <nom>     valeurs du profil"
    echo "  profile DIFF <nom>     ecarts vs config de base"
    echo "  profile SWITCH <nom>   active (PROFILE=<nom>)"
    echo "  profile OFF            retour config de base"
    echo "  profile SAVE <nom>     capture la base comme nouveau profil"
    echo ""
    echo "Repertoire : $PROF_DIR/"
}

case "$1" in
    ""|CURRENT|current)
        C="$(cur_profile)"
        echo "profil actif : ${C:-<aucun, config de base>}"
        echo "disponibles  :"
        list_profiles | sed 's/^/  - /'
        [ -z "$(list_profiles)" ] && echo "  (aucun - profile SAVE <nom> pour creer)"
        ;;
    LIST|list)      list_profiles | sed 's/^/  - /' ;;
    SHOW|show)      shift ; do_show "$1" ;;
    DIFF|diff)      shift ; do_diff "$1" ;;
    SWITCH|switch)  shift ; do_switch "$1" ;;
    OFF|off)        do_off ;;
    SAVE|save)      shift ; do_save "$1" ;;
    HELP|-h|--help) help_show ;;
    *)
        echo "argument inconnu : $1 (voir : profile HELP)"
        exit 1
        ;;
esac
