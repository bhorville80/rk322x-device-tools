#!/system/bin/sh

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" "$(dirname "$0")/.." /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

main()
{

USER_NAME="$1"
FOUND=0

echo ""
echo "=== INSPECTION : CREATION USER ==="

if [ -z "$USER_NAME" ]; then
    USER_NAME="mxquser"
    echo "[INFO] aucun nom fourni, exemple utilise : $USER_NAME"
fi

echo ""
echo "[1] Systeme"
printf '      %-14s : %s\n' "Modele"   "$(getprop ro.product.model 2>/dev/null)"
printf '      %-14s : %s\n' "Device"  "$(getprop ro.product.device 2>/dev/null)"
printf '      %-14s : %s\n' "Android" "$(getprop ro.build.version.release 2>/dev/null) (SDK $(getprop ro.build.version.sdk 2>/dev/null))"
printf '      %-14s : %s\n' "Build"   "$(getprop ro.build.type 2>/dev/null)"
printf '      %-14s : %s\n' "Id"      "$(id 2>/dev/null)"

echo ""
echo "[2] Utilisateurs existants"
USERS_OUT="$(pm list users 2>&1)"
if echo "$USERS_OUT" | grep -q "UserInfo"; then
    echo "$USERS_OUT" | sed 's/^/      /'
else
    echo "      [ ERREUR ] pm list users indisponible"
fi

MAX_USERS="$(pm get-max-users 2>/dev/null | tr -dc '0-9')"
if [ -z "$MAX_USERS" ]; then
    MAX_USERS="$(getprop fw.max_users 2>/dev/null | tr -dc '0-9')"
fi
if [ -n "$MAX_USERS" ]; then
    printf '      %-14s : %s\n' "Max users" "$MAX_USERS"
else
    printf '      %-14s : %s\n' "Max users" "inconnu"
fi

echo ""
echo "[3] Methodes de creation disponibles"

echo ""
echo "  * pm create-user (multi-utilisateur Android)"
PM_HELP="$(pm 2>&1)"
if echo "$PM_HELP" | grep -q "create-user"; then
    echo "      [ OK ] disponible"
    echo "$PM_HELP" | grep "create-user" | head -n 3 | sed 's/^/             /'
    FOUND=1
else
    echo "      [ -- ] absent"
fi

echo ""
echo "  * cmd user create (Android recent)"
if command -v cmd >/dev/null 2>&1; then
    CMD_OUT="$(cmd user 2>&1)"
    if echo "$CMD_OUT" | grep -q "create"; then
        echo "      [ OK ] disponible"
        FOUND=1
    else
        echo "      [ -- ] absent"
    fi
else
    echo "      [ -- ] commande cmd absente"
fi

echo ""
echo "  * busybox adduser (utilisateur linux local)"
if busybox 2>&1 | grep -q adduser; then
    echo "      [ OK ] applet presente"
    FOUND=1
else
    echo "      [ -- ] absente"
fi

echo ""
echo "  * toybox adduser/useradd (utilisateur linux local)"
if toybox 2>&1 | grep -q "adduser\|useradd"; then
    echo "      [ OK ] applet presente"
    FOUND=1
else
    echo "      [ -- ] absente"
fi

echo ""
echo "[4] Privileges / sudo"

IS_ANDROID=0
if [ -n "$(getprop ro.build.version.release 2>/dev/null)" ]; then
    IS_ANDROID=1
fi

FOUND_SUDO=0
if command -v sudo >/dev/null 2>&1; then
    printf '      %-14s : %s\n' "sudo" "$(command -v sudo)"
    FOUND_SUDO=1
else
    printf '      %-14s : %s\n' "sudo" "absent"
fi

if [ -f "/etc/sudoers" ]; then
    printf '      %-14s : %s\n' "/etc/sudoers" "present"
else
    printf '      %-14s : %s\n' "/etc/sudoers" "absent"
fi
if [ -d "/etc/sudoers.d" ]; then
    printf '      %-14s : %s\n' "/etc/sudoers.d" "present"
fi

SU_PATH="$(command -v su 2>/dev/null)"
printf '      %-14s : %s\n' "su" "${SU_PATH:-absent}"

SU_FLAVOR=""
if [ -n "$SU_PATH" ]; then
    case "$(ls -l "$SU_PATH" 2>/dev/null | tr -d '\r')" in
        *daemonsu*|*supersu*|*SuperSU*)  SU_FLAVOR="SuperSU (daemonsu)" ;;
        *magisk*)                        SU_FLAVOR="Magisk" ;;
        *)                               SU_FLAVOR="su" ;;
    esac
    if ps 2>/dev/null | grep -q "daemonsu"; then
        SU_FLAVOR="SuperSU (daemonsu actif)"
    fi
fi
printf '      %-14s : %s\n' "Gestion su" "${SU_FLAVOR:-absent}"

SELINUX="$(getprop ro.boot.selinux 2>/dev/null | tr -d '\r')"
[ -z "$SELINUX" ] && SELINUX="$(getprop ro.build.selinux 2>/dev/null | tr -d '\r')"
[ -n "$SELINUX" ] && printf '      %-14s : %s\n' "SELinux" "$SELINUX"

if [ -f "/etc/passwd" ]; then
    printf '      %-14s : %s\n' "/etc/passwd" "present"
else
    printf '      %-14s : %s\n' "/etc/passwd" "absent"
fi

echo ""
echo "[5] Resume"
if [ "$FOUND" -eq 1 ]; then
    echo "    Au moins une methode est disponible."
    echo "    Commandes suggerees :"
    echo "      pm create-user $USER_NAME"
    echo "      am switch-user <USER_ID>"
    echo "      am remove-user <USER_ID>"
else
    echo "    [ ERREUR ] aucune methode detectee sur ce systeme"
fi

echo ""
if [ "$FOUND_SUDO" -eq 1 ]; then
    echo "    Sudo detecte : ajout sudoers possible (systeme linux) :"
    echo "      adduser $USER_NAME sudo"
    echo "      ou : echo \"$USER_NAME ALL=(ALL) NOPASSWD: ALL\" > /etc/sudoers.d/$USER_NAME"
elif [ "$IS_ANDROID" -eq 1 ]; then
    echo "    Systeme Android : pas de sudo, pas de /etc/passwd."
    echo ""
    echo "    VERDICT 'user avec role root pour l'execution' :"
    if [ -n "$SU_PATH" ]; then
        echo "      - l'execution root est DEJA disponible partout via su"
        echo "        ($SU_FLAVOR) : adb shell -> uid shell, su -> uid 0."
        echo "        Un compte dedie n'apporte rien de plus en local."
    else
        echo "      - aucun su detecte : pas de role root obtenuable ici"
    fi
    echo "      - pm create-user cree un profil Android ISOLE, SANS root"
    echo "        (UID 10xxx propre, apps separees : ce n'est pas un role root)"
    echo "      - utilisateur Linux impossible ici (pas de /etc/passwd)"
    echo "      - bonne pratique : execution root conservee pour les outils,"
    echo "        acces distant controle a la place (token API 8180, adb"
    echo "        limite au LAN, cut_services pour reduire la surface)"
else
    echo "    Ni sudo ni Android detecte : ajout sudoers manuel requis."
fi

if [ "$FOUND" -eq 1 ]; then
    return 0
fi
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

exit "$RC"

