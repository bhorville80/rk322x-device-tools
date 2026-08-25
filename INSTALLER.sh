#!/system/bin/sh
# INSTALLER - installation complete de la cle en UNE commande, avec
# points de validation a chaque etape (vous restez maitre de ce qui part).
#
# Depuis adb shell :
#   sh /mnt/media_rw/*/INSTALLER.sh          interactif (recommande)
#   sh /mnt/media_rw/*/INSTALLER.sh AUTO     sans questions (scripte)
# (uid non root : relance automatique via su, comme deploy.sh)
#
# Etapes :
#   1/3 deploy PKG      installe le .dpk le plus recent (+ panneau + liens)
#                       et pose d'office hook init + aliases (/system rw)
#   2/3 boot INSTALL    verifie le point de lancement persistant
#   3/3 boot TEST       applique immediatement memoire/reseau/horloge/web
#   (+ option aliases : verification des raccourcis adb shell)

H_="$(dirname "$0")"
AUTO="$1"

# auto-elevation : les etapes 2/3 (hook init -> /system rw) et aliases
# (/system/bin) exigent root ; deploy.sh PKG se re-lance seul via su mais
# pas la suite -> sans ceci l'installation finit incomplete si l'installateur
# n'a pas ete lance depuis un shell su.
is_root()
{
    case "$(id -u 2>/dev/null)" in
        0) return 0 ;;
    esac
    case "$(id 2>/dev/null)" in
        "uid=0("*) return 0 ;;
    esac
    return 1
}

if ! is_root && command -v su > /dev/null 2>&1; then
    echo "[*] uid non root : relance automatique via su (installation complete)"
    SELF_="$(cd "$H_" && pwd)/$(basename "$0")"
    exec su -c "sh $SELF_ $*"
fi

ask()
{
    # ask "question" [defaut O|N] -> rc 0 si valide
    Q="$1"
    D="${2:-O}"
    if [ "$AUTO" = "AUTO" ]; then
        echo "$Q [auto:$D]"
        [ "$D" = "O" ]
        return $?
    fi
    if [ -r /dev/tty ]; then
        printf '%s [o/N, defaut=%s] : ' "$Q" "$D"
        IFS= read -r A_ < /dev/tty || A_=""
    else
        echo "[i] pas de terminal : $Q -> defaut $D"
        [ "$D" = "O" ]
        return $?
    fi
    case "${A_:-$D}" in
        o|O|y|Y|oui|OUI) return 0 ;;
        *)               return 1 ;;
    esac
}

pause()
{
    [ "$AUTO" = "AUTO" ] && return 0
    printf 'ENTREE pour continuer...'
    if [ -r /dev/tty ]; then IFS= read -r X_ < /dev/tty; fi
    echo ""
    return 0
}

echo ""
echo "###############################################"
echo "# RK322X DEVICE TOOLS - INSTALLATION COMPLETE #"
echo "#   interactive : chaque etape est validee    #"
echo "###############################################"
echo ""

# ---- [0] presentation du paquet -------------------------------------------
LATEST="$(ls -1 "$H_"/*.dpk 2>/dev/null | sort -t_ -k3 | tail -n 1)"
if [ -z "$LATEST" ]; then
    echo "[ERREUR] aucun .dpk a la racine de la cle ($H_)"
    exit 1
fi
echo "Paquet detecte : $(basename "$LATEST")"
BI="$H_/BUILD-INFO.txt"
[ -f "$BI" ] && grep -E "^(build|date|version)" "$BI" | sed 's/^/  /'
echo ""
if ! ask "Installer ce paquet sur la box ?" O; then
    echo "annule (rien installe)"
    exit 1
fi

# ---- [1/3] installation ----------------------------------------------------
pause
echo ""
echo "=== 1/3 INSTALLATION (deploy PKG) ==="
sh "$H_/deploy.sh" PKG || {
    echo "[ERREUR] installation echouee - corriger avant de continuer"
    exit 1
}

# ---- revue de la configuration avant application ---------------------------
echo ""
echo "--- Configuration qui sera appliquee (extraits) ---"
CF="/data/scripts/config/device.conf"
grep -E '^(DEVICE_NAME|IP|GATEWAY|DNS|SSH_MODE|SSH_PORT|MEM_SWAPPINESS|MEM_LMK_EARLY|BOOT_SET_NETWORK|BOOT_TIME_SYNC|BOOT_EXPOSE|WEB_RUN)=' "$CF" 2>/dev/null | sed 's/^/  /'
echo ""

if ask "Ajuster la configuration avant application (ouvre l editeur interactif) ?" N; then
    sh /data/scripts/config.sh
fi

# ---- [2/3] hook de lancement persistant -------------------------------------
echo ""
if ask "Verifier le demarrage AUTOMATIQUE au reboot (hook init, deja pose par l installation) ?" O; then
    echo "=== 2/3 POINT DE LANCEMENT PERSISTANT (boot INSTALL) ==="
    sh /data/scripts/boot.sh INSTALL
else
    echo "[ -- ] etape sautee : pour retirer le hook plus tard : boot REMOVE"
fi

# ---- [3/3] application immediate --------------------------------------------
echo ""
if ask "Appliquer les configurations MAINTENANT (mem_tune/reseau/horloge/EXPOSE) ?" O; then
    echo "=== 3/3 APPLICATION IMMEDIATE (boot TEST) ==="
    sh /data/scripts/boot.sh TEST
else
    echo "[ -- ] rien applique pour l instant ; plus tard : boot TEST ou reboot"
fi

# ---- bonus raccourcis ---------------------------------------------------------
echo ""
if ask "Verifier les raccourcis adb shell (aliases, deja poses par l installation) ?" O; then
    sh /data/scripts/aliases.sh INSTALL
fi

echo ""
echo "==============================================="
echo " TERMINE."
echo " IHM : http://<ip-box>:8000/   (6 pages)"
echo " Etat du hook : boot STATUS | Retrait : boot REMOVE"
echo " Prochains tests conseilles : reboot puis recette"
echo "==============================================="
