#!/system/bin/sh
# crowdsec - evaluation et mise a dispo d'un IDS comportemental.
#
# Verdict technique sur cette box : Crowdsec officiel = binaire glibc
# armhf -> ne tourne PAS nativement sur Android (bionic). Deux voies :
#   A) proot + rootfs Debian armhf (sans toucher au systeme, mais lourd)
#   B) equivalent minimal 100% natif : net_watch LOGSCAN + BAN iptables
#      (deja inclus dans net_watch, zero dependance)
#
#   crowdsec STATUS     binaries/proot/rootfs detectes + verdict
#   crowdsec GUIDE      pas a pas des deux voies
#   crowdsec NATIVE     rappel du mode natif (net_watch)

SCRIPT_ID="$(basename "$0" .sh)"

for B in "$(dirname "$0")" /data/scripts; do
    [ -f "$B/core/runlog.sh" ] && . "$B/core/runlog.sh" && break
done

key_dir()
{
    for d in /mnt/media_rw/*; do
        [ -f "$d/deploy.sh" ] && { printf '%s' "$d"; return 0; }
    done
    return 1
}

find_first()
{
    for C in "$@"; do
        [ -x "$C" ] && { printf '%s' "$C"; return 0; }
        [ -f "$C" ] && { printf '%s' "$C"; return 0; }
    done
    return 1
}

do_status()
{
    echo ""
    echo "=== CROWDSEC STATUS ==="

    CS="$(find_first /data/local/tmp/crowdsec/crowdsec \
                     /data/local/tmp/cscli \
                     "$(key_dir 2>/dev/null)/server/crowdsec")"
    case "${CS:-}" in
        "") echo "  Binaires crowdsec : absents" ;;
        *)  echo "  Binaires crowdsec : $CS (present MAIS glibc -> inutilisable tel quel)" ;;
    esac

    PROOT="$(find_first /data/local/tmp/proot /data/local/tmp/.nettools/proot /system/xbin/proot)"
    echo "  proot              : ${PROOT:-absent}"

    ROOTFS=""
    for D in /data/local/tmp/debian /data/local/tmp/linux-debian-* ; do
        [ -f "$D/bin/bash" ] && { ROOTFS="$D"; break; }
    done
    echo "  Rootfs Debian      : ${ROOTFS:-absent}"

    MEM="$(sed -n 's/^MemAvailable: *\([0-9]*\) kB/\1/p' /proc/meminfo 2>/dev/null | head -n 1)"
    case "$MEM" in
        ''|*[!0-9]*) echo "  RAM disponible     : ?" ;;
        *)           echo "  RAM disponible     : $((MEM / 1024)) Mo (crowdsec agent ~80-150 Mo)" ;;
    esac

    echo ""
    case "${PROOT}${ROOTFS}" in
        "") echo "  VERDICT : voie A possible apres depots (proot+rootfs ~300 Mo disque),"
            echo "            voie B recommandee ici (natif, deja operationnel) :"
            echo "            net_watch LOGSCAN puis net_watch BAN <ip>"
            ;;
        *"proot"*) echo "  VERDICT : elements voie A presents -> cf. crowdsec GUIDE" ;;
    esac
    echo ""
    return 0
}

do_guide()
{
    cat <<'GUIDE'
=== VOIE A - Crowdsec dans Debian/proot (isole, sans toucher au systeme) ===

  1. PC : recuperer proot statique armhf + un rootfs debian armhf (rootfs.tar)
  2. adb push proot          /data/local/tmp/.nettools/proot
     adb push rootfs.tar     /data/local/tmp/
     adb shell chmod 755 /data/local/tmp/.nettools/proot
  3. box :
       mkdir -p /data/local/tmp/debian
       cd /data/local/tmp
       sh -c 'gzip -dc rootfs.tar | busybox tar -x -C debian'
       ./.nettools/proot -r debian -b /dev -b /proc -b /sys /bin/sh
  4. dans le chroot :
       apt update && apt install -y wget curl
       (installer crowdsec armhf selon la doc officielle)
     NB : pas de systemd sous proot -> lancer crowdsec en foreground.

=== VOIE B - Natif immediat (recommande sur cette box) =====================

  Surveillance comportementale sans aucun paquet :

    net_watch DAEMON 5         # echantillonne les connexions en continu
    net_watch LOGSCAN 20       # IP agressives vues dans les logs serveurs
    net_watch BAN <ip>         # blocage iptables instantane
    net_watch STATUS           # vue temps reel

  Equivalence fonctionnelle :
    crowdsec parser  ~  LOGSCAN (analyse des logs http/gui/control)
    crowdsec ban     ~  BAN/UNBAN iptables
    cscli decisions  ~  net_watch BANS
============================================================================
GUIDE
    return 0
}

case "$1" in
    ""|STATUS|status) do_status ;;
    GUIDE|guide)      do_guide ;;
    NATIVE|native)
        echo "[INFO] mode natif = outils net_watch (LOGSCAN/BAN/BANS/DAEMON)"
        sh "$(dirname "$0")/net_watch.sh" HELP 2>/dev/null || true
        ;;
    HELP|help|-h|--help)
        echo ""
        echo "Usage: crowdsec <STATUS|GUIDE|NATIVE>"
        echo ""
        ;;
    *) echo "Usage: crowdsec <STATUS|GUIDE|NATIVE>" ;;
esac
