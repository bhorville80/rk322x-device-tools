#!/system/bin/sh
# chroot_env - mini-environnements isoles type conteneur (chroot) :
# heberge un rootfs Linux armhf (Debian/Ubuntu...) sous $CHROOT_ROOT
# et y entre comme dans un conteneur (proc/sys/dev lies par bind mounts).
#
# Un env = 1 repertoire + 4 montages. Rien ne survit au reboot cote
# montages : BOOT_CHROOT=1 (device.conf) les remonte a chaque demarrage.
# Prerequis : root, busybox/toybox avec chroot, /data executable.
# Sonde sans engagement : chroot_env PROBE.
#
# Usage:
#   chroot_env PROBE                  sonde capacites kernel (rien n'installe)
#   chroot_env LIST                   environnements presents (une ligne/env)
#   chroot_env STATUS                 prerequis + etat detaille par env
#   chroot_env CREATE <nom> <archive> installe un rootfs .tar.gz/.tar.xz/
#                                     .tar.bz2/.tar (chemin absolu OU fichier
#                                     pose a la racine de la cle USB)
#   chroot_env ENTER [nom]            shell interactif dans l'env (montage auto)
#   chroot_env EXEC [nom] <cmd...>    commande ponctuelle dans l'env
#   chroot_env MOUNT [nom]            liens proc sys dev dev/pts + resolv.conf
#   chroot_env UMOUNT [nom]           depose les liens
#   chroot_env REMOVE <nom> [FORCE]   supprime un env (confirmation sauf FORCE)
#   chroot_env HELP                   cette aide (sans root)

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" "$(dirname "$0")/.." /data/scripts; do
    [ -f "$B/core/runlog.sh" ] && { . "$B/core/runlog.sh"; RUNLOG_LOADED=1; break; }
done

# librairie config : UNIQUEMENT core/config.sh
# (NE JAMAIS candidat "$(dirname)/config.sh" : c'est l'outil interactif !)
for B in "$(dirname "$0")/core" "$(dirname "$0")/../core" /data/scripts/core; do
    [ -f "$B/config.sh" ] && { . "$B/config.sh"; break; }
done

command -v config_get >/dev/null 2>&1 || config_get() { echo "$2"; }
command -v is_root >/dev/null 2>&1 || is_root() \
    { case "$(id -u 2>/dev/null)" in 0) return 0 ;; esac; case "$(id 2>/dev/null)" in "uid=0("*) return 0 ;; esac; return 1; }

CHROOTS_ROOT="$(config_get CHROOT_ROOT /data/chroots)"
DEF_NAME="$(config_get CHROOT_NAME debian)"
BIND_SUB="proc sys dev dev/pts"

have() { command -v "$1" >/dev/null 2>&1 ; }

ok_ko()  { printf '  [%s] %s\n' "$1" "$2" ; }
row()    { printf '  %-24s %s\n' "$1" "$2" ; }

# ------------------------------------------------------------------ primitives

do_chroot()
{
    # $1 racine du rootfs, $2... commande a lancer dedans
    if have chroot; then
        chroot "$@"
        return $?
    fi
    if have busybox && busybox --list 2>/dev/null | grep -q '^chroot$'; then
        busybox chroot "$@"
        return $?
    fi
    echo "[ERREUR] chroot indisponible (ni toybox ni busybox avec applet chroot)"
    return 127
}

do_bind()
{
    mount -o bind "$1" "$2" 2>/dev/null && return 0
    have busybox && busybox mount -o bind "$1" "$2" 2>/dev/null && return 0
    return 1
}

do_unbind()
{
    umount "$1" 2>/dev/null && return 0
    have busybox && busybox umount "$1" 2>/dev/null && return 0
    return 1
}

is_mounted()
{
    awk -v D="$1" '$2 == D { f=1 } END { if (f) exit 0 ; exit 1 }' /proc/mounts 2>/dev/null
}

valid_name()
{
    # $1 nom candidat -> echo normalise ou rien ; refus vide/. /..//-/caracteres speciaux
    N="$1"
    [ -n "$N" ] || return 1
    case "$N" in .|..|-*|*[!a-zA-Z0-9_.-]*) return 1 ;; esac
    printf '%s\n' "$N"
}

resolve_name()
{
    N="$(valid_name "${1:-$DEF_NAME}")"
    [ -n "$N" ] || { echo "[ERREUR] nom d'env invalide : '$1' (a-z A-Z 0-9 _ . -)" >&2 ; return 1 ; }
    printf '%s\n' "$N"
}

env_dir()
{
    printf '%s/%s\n' "$CHROOTS_ROOT" "$(resolve_name "$1")"
}

free_kb()
{
    df "$1" 2>/dev/null | tail -n 1 | awk '{print $4}'
}

# limite : verdict porte sur le montage de /data (racine des envs par defaut)
data_exec_ok()
{
    case "$(mount 2>/dev/null | grep ' /data ' | head -n 1)" in
        *noexec*) return 1 ;;
    esac
    return 0
}

# ------------------------------------------------------------------ montages

mount_env()
{
    NAME_="$(resolve_name "$1")" || return 1
    R="$CHROOTS_ROOT/$NAME_"
    [ -d "$R" ] || { echo "[ERREUR] env absent : $NAME_ (CREATE d'abord, voir HELP)" ; return 1 ; }
    RC_=0
    for S_ in $BIND_SUB; do
        DST="$R/$S_"
        if is_mounted "$DST"; then continue ; fi
        [ -d "$DST" ] || mkdir -p "$DST" 2>/dev/null
        if do_bind "/$S_" "$DST"; then
            echo "[ OK ] bind /$S_ -> $DST"
        else
            echo "[ ERREUR ] bind /$S_ -> $DST"
            RC_=1
        fi
    done
    # DNS : copie generee (survit mieux qu'un lien vers le resolv Android)
    DNS1="$(getprop net.dns1 2>/dev/null)"
    DNS2="$(getprop net.dns2 2>/dev/null)"
    [ -n "$DNS1" ] || DNS1="$(config_get DNS 8.8.8.8)"
    mkdir -p "$R/etc" 2>/dev/null
    {
        echo "# genere par chroot_env MOUNT - $(date '+%Y-%m-%d %H:%M:%S')"
        echo "nameserver $DNS1"
        [ -n "$DNS2" ] && echo "nameserver $DNS2"
    } > "$R/etc/resolv.conf" 2>/dev/null || RC_=1
    return "$RC_"
}

umount_env()
{
    NAME_="$(resolve_name "$1")" || return 1
    R="$CHROOTS_ROOT/$NAME_"
    [ -d "$R" ] || { echo "[ERREUR] env absent : $NAME_" ; return 1 ; }
    RC_=0
    for S_ in dev/pts dev sys proc; do
        DST="$R/$S_"
        is_mounted "$DST" || continue
        if do_unbind "$DST"; then
            echo "[ OK ] demonte $DST"
        else
            echo "[ ERREUR ] demontage $DST (un processus tourne encore dans l'env ?)"
            RC_=1
        fi
    done
    return "$RC_"
}

ensure_mounted()
{
    R="$CHROOTS_ROOT/$1"
    is_mounted "$R/proc" && return 0
    echo "[i] liens absents -> montage..."
    mount_env "$1"
}

# ------------------------------------------------------------------ commandes

cmd_probe()
{
    echo ""
    echo "=== CHROOT ENV PROBE - capacites de la box ==="
    row racine "$CHROOTS_ROOT"

    if is_root; then ok_ko OK "root actif (requis pour chroot/bind)" ;
    else ok_ko !! "sans root (relancer via su -c) - PROBE partiel" ; fi

    if have chroot; then
        ok_ko OK "chroot systeme present ($(command -v chroot))"
    elif have busybox && busybox --list 2>/dev/null | grep -q '^chroot$'; then
        ok_ko OK "busybox fournit l'applet chroot"
    else
        ok_ko KO "aucun chroot disponible -> installer un busybox complet sur la cle"
    fi

    T="/data/local/tmp/chprobe.$$"
    CLEAN_PROBE=1
    end_probe() { [ -n "$CLEAN_PROBE" ] && rm -rf "$T" 2>/dev/null ; }
    trap 'end_probe' EXIT INT TERM
    mkdir -p "$T/a" "$T/b" 2>/dev/null
    if do_bind "$T/a" "$T/b" && is_mounted "$T/b"; then
        ok_ko OK "bind mounts supportes par ce kernel"
        do_unbind "$T/b" >/dev/null 2>&1
    else
        ok_ko KO "bind mount refuse -> ENTER/EXEC impossibles (MOUNT echouera)"
    fi
    CLEAN_PROBE=""
    rm -rf "$T" 2>/dev/null
    trap - EXIT INT TERM

    if data_exec_ok; then
        ok_ko OK "/data executable -> binaires du rootfs admis"
    else
        ok_ko KO "/data noexec -> binaires du rootfs refuses, chroot inutilisable"
    fi

    case "$(grep -c devpts /proc/mounts 2>/dev/null)" in
        ''|0) ok_ko !! "devpts absent des montages hotes (shells interactifs limites)" ;;
        *)    ok_ko OK "devpts hote present (partage pour les pts du rootfs)" ;;
    esac

    KB="$(free_kb "$CHROOTS_ROOT")"
    case "$KB" in ''|*[!0-9]*) row espace "illisible" ;;
                   *)          row espace "$((KB / 1024)) Mo libres sur la partition cible" ;; esac
    row taille_conseillee "300-500 Mo pour un rootfs Debian minimal (var/lib en premier)"

    echo ""
    echo "  Recette type : poser debian-armhf.tar.gz a la racine de la cle,"
    echo "  puis : chroot_env CREATE deb debian-armhf.tar.gz ; chroot_env ENTER deb"
    echo ""
    echo "=== FIN PROBE ==="
    return 0
}

cmd_list()
{
    [ -d "$CHROOTS_ROOT" ] || return 0
    FOUND=0
    for D in "$CHROOTS_ROOT"/*/; do
        [ -d "$D" ] || continue
        FOUND=1
        N="$(basename "$D")"
        if is_mounted "$D/proc"; then M="monte" ; else M="-" ; fi
        KB="$(du -sk "$D" 2>/dev/null | awk '{print $1}')"
        case "$KB" in ''|*[!0-9]*) KB="" ;; *) KB=" $((KB / 1024)) Mo" ;; esac
        printf '%s%s [%s]\n' "$N" "${KB:-}" "$M"
    done
    [ "$FOUND" -eq 1 ] || echo "(aucun environnement - CREATE d'abord)"
    return 0
}

cmd_status()
{
    echo ""
    echo "=== CHROOT ENV STATUS ==="
    row config "$CHROOTS_ROOT (defaut : $DEF_NAME)"
    row BOOT_CHROOT "$(config_get BOOT_CHROOT 0) (remontage des liens au boot)"

    if is_root; then row privileges "root" ; else row privileges "NON root (ENTER/EXEC/MOUNT requis)" ; fi

    if have chroot; then row chroot "systeme : $(command -v chroot)"
    elif have busybox && busybox --list 2>/dev/null | grep -q '^chroot$'; then row chroot "busybox applet"
    else row chroot "[ -- ] indisponible" ; fi

    if data_exec_ok; then row "/data exec" "OK" ; else row "/data exec" "noexec (bloquant)" ; fi

    echo ""
    echo "Environnements :"
    cmd_list
    echo ""
    return 0
}

cmd_create()
{
    NAME_="$(resolve_name "$1")" || return 1
    ARC="$2"
    if [ -z "$ARC" ]; then
        echo "[ERREUR] archive manquante : CREATE $NAME_ <fichier.tar.gz>"
        return 1
    fi
    require_root || return 1
    DEST="$CHROOTS_ROOT/$NAME_"
    if [ -e "$DEST" ]; then
        echo "[ERREUR] existe deja : $DEST (REMOVE d'abord ou choisir un autre nom)"
        return 1
    fi

    SRCF=""
    if [ -f "$ARC" ]; then
        SRCF="$ARC"
    else
        for d in /mnt/media_rw/*; do
            [ -f "$d/$ARC" ] && { SRCF="$d/$ARC" ; break ; }
        done
    fi
    [ -n "$SRCF" ] || { echo "[ERREUR] archive introuvable : $ARC (ni chemin direct ni racine cle USB)" ; return 1 ; }

    case "$SRCF" in
        *.tar.gz|*.tgz)         TARF="-z" ;;
        *.tar.xz|*.txz)         TARF="-J" ;;
        *.tar.bz2|*.tbz|*.tbz2) TARF="-j" ;;
        *.tar)                  TARF="" ;;
        *) echo "[ERREUR] format non supporte : $SRCF (attendu : tar.gz/tar.xz/tar.bz2/tar)" ; return 1 ;;
    esac

    if have busybox; then TARCMD="busybox tar"
    elif have tar; then TARCMD="tar"
    else echo "[ERREUR] tar indisponible (busybox requis)" ; return 127 ; fi

    if ! data_exec_ok; then
        echo "[ERREUR] /data noexec : les binaires du rootfs ne s'executeront pas (cf. PROBE)"
        return 1
    fi

    KB="$(free_kb "$CHROOTS_ROOT")"
    case "$KB" in ''|*[!0-9]*) ;;
        *) echo "[i] espace dispo avant extraction : $((KB / 1024)) Mo" ;;
    esac

    STAGE="$CHROOTS_ROOT/.stage.$$"
    clean_stage() { rm -rf "$STAGE" 2>/dev/null ; }
    trap 'clean_stage' EXIT INT TERM
    mkdir -p "$CHROOTS_ROOT" "$STAGE" 2>/dev/null || { echo "[ERREUR] mkdir $STAGE impossible" ; clean_stage ; trap - EXIT INT TERM ; return 1 ; }

    echo "[*] extraction de $SRCF ..."
    if ! $TARCMD $TARF -xf "$SRCF" -C "$STAGE"; then
        echo "[ ERREUR ] extraction (archive corrompue ? tar sans support $TARF ?)"
        clean_stage ; trap - EXIT INT TERM
        return 1
    fi

    # archive contenant un dossier racine unique (style tarball github/debootstrap)
    NENT="$(ls -A "$STAGE" 2>/dev/null | wc -l | tr -d ' ')"
    TOP=""
    if [ "$NENT" = "1" ]; then
        CAND="$(ls -A "$STAGE" 2>/dev/null)"
        [ -d "$STAGE/$CAND" ] && TOP="$CAND"
    fi
    if [ -n "$TOP" ]; then
        mv "$STAGE/$TOP" "$DEST" && rmdir "$STAGE" 2>/dev/null
    else
        mv "$STAGE" "$DEST"
    fi
    trap - EXIT INT TERM
    clean_stage

    if [ ! -e "$DEST/bin/sh" ] && [ ! -e "$DEST/usr/bin/sh" ]; then
        echo "[WARN] bin/sh absent de $DEST : rootfs incomplet ou layout inhabituel ?"
        echo "       (CREATE garde l'env mais ENTER echouera probablement)"
    fi
    chmod 755 "$DEST" 2>/dev/null

    echo "[ OK ] env cree : $DEST"
    echo "       suite conseillee : chroot_env ENTER $NAME_"
    return 0
}

inside_shell_for()
{
    R="$1"
    SHELL_IN="/bin/sh"
    [ -x "$R/bin/bash" ] && SHELL_IN="/bin/bash"
    HOME=/root ; TERM="${TERM:-linux}" ; export HOME TERM
    PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" ; export PATH
    do_chroot "$R" "$SHELL_IN" $2
}

cmd_enter()
{
    NAME_="$(resolve_name "$1")" || return 1
    R="$CHROOTS_ROOT/$NAME_"
    [ -d "$R" ] || { echo "[ERREUR] env absent : $NAME_ (CREATE d'abord)" ; return 1 ; }
    require_root || return 1
    ensure_mounted "$NAME_" || return 1
    echo "[i] entree dans '$NAME_' (exit pour sortir)"
    inside_shell_for "$R" "-i"
}

cmd_exec()
{
    # EXEC [nom] cmd... : si $2 (non vide) designe un env existant il sert
    # de nom, sinon toute la fin est la commande dans l'env par defaut.
    if [ -n "$2" ] && [ -d "$CHROOTS_ROOT/$2" ]; then
        NAME_="$(resolve_name "$2")" || return 1
        shift 2
    else
        NAME_="$(resolve_name "")" || return 1
        shift
    fi
    [ -n "$1" ] || { echo "[ERREUR] commande manquante : EXEC [$NAME_] <cmd...>" ; return 1 ; }
    R="$CHROOTS_ROOT/$NAME_"
    [ -d "$R" ] || { echo "[ERREUR] env absent : $NAME_ (CREATE d'abord)" ; return 1 ; }
    require_root || return 1
    ensure_mounted "$NAME_" || return 1
    do_chroot "$R" "$@"
    RC=$?
    echo "[i] rc=$RC"
    return "$RC"
}

cmd_remove()
{
    NAME_="$(resolve_name "$1")" || return 1
    FORCE="$2"
    R="$CHROOTS_ROOT/$NAME_"
    [ -d "$R" ] || { echo "[ERREUR] env absent : $NAME_" ; return 1 ; }
    require_root || return 1
    umount_env "$NAME_" >/dev/null 2>&1
    if [ "$FORCE" != "FORCE" ] && [ "$FORCE" != "YES" ]; then
        printf 'Supprimer %s et son contenu ? (oui/NON) ' "$R"
        read ANS
        case "$ANS" in oui|OUI|oui*) ;; *) echo "annule" ; return 1 ;; esac
    fi
    if rm -rf "$R" 2>/dev/null && [ ! -d "$R" ]; then
        echo "[ OK ] env supprime : $NAME_"
        return 0
    fi
    echo "[ ERREUR ] suppression incomplete : $R"
    return 1
}

usage()
{
    sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
}

main()
{
    case "$1" in
        ""|HELP|-h|--help) usage ;;
        PROBE|probe)        cmd_probe ;;
        LIST|list)          cmd_list ;;
        STATUS|status)      cmd_status ;;
        CREATE|create)      shift ; cmd_create "$@" ;;
        ENTER|enter)        shift ; cmd_enter "$@" ;;
        EXEC|exec)          shift ; cmd_exec "$@" ;;
        MOUNT|mount)        shift ; mount_env "$@" ;;
        UMOUNT|umount)      shift ; umount_env "$@" ;;
        REMOVE|remove)      shift ; cmd_remove "$@" ;;
        *) echo "option inconnue : $1 (voir chroot_env HELP)" ; return 1 ;;
    esac
}

if [ "$RUNLOG_LOADED" -eq 1 ] && runlog_start "$SCRIPT_ID"; then
    main "$@" >> "$RUNLOG_FILE" 2>&1 ; RC=$?
    runlog_end "$RC" ; cat "$RUNLOG_FILE"
else
    main "$@" ; RC=$?
fi
exit "$RC"
