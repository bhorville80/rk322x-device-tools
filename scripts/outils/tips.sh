#!/system/bin/sh
# tips - golden one-liners embarques SUR la box : les meilleures commandes
# internes pretes a copier, sans cle ni depot. Version executable de
# docs/BEST-COMMANDES.md ; $BB est resolu en direct (busybox detecte).
#
# Usage:
#   tips                     apercu + les 5 plus rentables
#   tips <categorie>         reseau | ram | stockage | web | secours | divers
#   tips FIND <motif>        recherche dans tous les tips
#   tips ALL                 tout afficher
#   tips HELP                cette aide

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" "$(dirname "$0")/.." /data/scripts; do
    [ -f "$B/core/runlog.sh" ] && { . "$B/core/runlog.sh"; RUNLOG_LOADED=1; break; }
done

command -v config_get >/dev/null 2>&1 || config_get() { echo "$2"; }

BB="busybox"
find_bb()
{
    C="$(config_get BUSYBOX_BIN "")"
    if [ -n "$C" ] && [ -x "$C" ]; then BB="$C" ; return 0 ; fi
    if command -v busybox >/dev/null 2>&1; then BB="busybox" ; return 0 ; fi
    for P in /system/xbin/busybox /data/local/tmp/busybox /data/local/bin/busybox; do
        [ -x "$P" ] && { BB="$P" ; return 0 ; }
    done
    return 1
}
find_bb || BB="busybox"   # hors box : exemples restent lisibles

CATS="reseau ram stockage web secours divers"

tip() { printf '  $ %s\n    %s\n' "$2" "$1" ; }

sec()  { echo "" ; echo "--- [$1] ---" ; }

body_reseau()
{
    sec "RESEAU"
    tip "tester un port distant sans nmap" \
        "$BB nc -z IP PORT && echo ouvert"
    tip "recevoir du TCP brut (debug daemon/API)" \
        "$BB nc -l -p 9000"
    tip "qui parle sur le reseau (top connexions)" \
        "$BB watch -n 5 \"awk 'NR>2{print \$3}' /proc/net/tcp | sort | uniq -c | sort -nr | head\""
    tip "mon IP + etat des interfaces" \
        "netcfg ; ip addr show"
    tip "transfert rapide LAN sans HTTP (recevoir: tftp -r fic IP)" \
        "$BB tftp -g -r fichier IP"
}

body_ram()
{
    sec "RAM"
    tip "% RAM libre instantane (moteur de vitals)" \
        "$BB awk '/MemAvail/{a=\$2}/MemTotal/{t=\$2}END{printf \"%d%%\\n\", a*100/t}' /proc/meminfo"
    tip "top 5 processus par memoire" \
        "ps | head -1 ; ps | grep -v PID | sort -k6 -n -r | head -5"
    tip "purger les caches apps (pic d'espace /data)" \
        "pm trim-caches 999G"
    tip "pression continue sur la swap (test tenue)" \
        "stress_ram 200"
}

body_stockage()
{
    sec "STOCKAGE"
    tip "top gros fichiers d'un repertoire" \
        "$BB find DIR -type f | xargs du -k | sort -nr | head"
    tip "espace libre partition /data (Mo)" \
        "df -k /data | tail -1 | awk '{print \$4/1024}'"
    tip "fabriquer un fichier de swap de 512 Mo sur la cle" \
        "dd if=/dev/zero of=swap.bin bs=1M count=512"
    tip "integrite d'un fichier (pattern dpk.sha256)" \
        "$BB sha256sum fichier"
    tip "archives a la volee (mecanisme .dpk)" \
        "$BB tar -czf out.tgz DIR"
}

body_web()
{
    sec "WEB"
    tip "servir un repertoire entier au LAN (PC: http://IP:8181)" \
        "cd DIR && $BB httpd -f -p 8181 -h ."
    tip "page servie = mecanisme exact du panneau :8000" \
        "$BB httpd -f -p 8137 -h /data/local/tmp & sleep 1 ; $BB wget -qO- http://127.0.0.1:8137/"
    tip "telecharger un fichier HTTP (absent d'Android stock)" \
        "$BB wget -q -O sortie URL"
    tip "recuperer un rapport vers le PC sans adb pull" \
        "$BB httpd -f -p 8181 -h /data/local/tmp/rk322x_logs"
}

body_secours()
{
    sec "SECOURS"
    tip "mini-conteneur Debian (cf chroot_env ENTER)" \
        "$BB chroot /data/chroots/deb /bin/sh -i"
    tip "shell distant de repli sans SSH (telnet brut)" \
        "$BB telnetd -p 2323 -l /system/bin/sh"
    tip "planifier une commande (repli du hook BOOT_*)" \
        "$BB crond -b -c /data/etc/crontabs"
    tip "relancer toute la pile web apres une casse" \
        "deploy STOP && deploy EXPOSE"
    tip "etat express avant tout diagnostic" \
        "sys_diag ; check_state"
}

body_divers()
{
    sec "DIVERS"
    tip "extraire une cle du device.conf" \
        "$BB sed -n 's/^IP=//p' /data/scripts/config/device.conf"
    tip "surveiller une valeur qui bouge" \
        "$BB watch -n 3 'date ; cat /sys/class/thermal/thermal_zone0/temp'"
    tip "transport texte d'un binaire (coller via adb)" \
        "$BB base64 fic > fic.b64"
    tip "analyse binaire/log illisible" \
        "$BB hexdump -C fic | head"
    tip "edition directe sur la box (sans push PC)" \
        "$BB vi /data/scripts/config/device.conf"
    tip "lancer une applet meme sans symlink" \
        "busi RUN <applet> [args...]"
}

show_cat()
{
    case "$1" in
        reseau)   body_reseau ;;
        ram)      body_ram ;;
        stockage) body_stockage ;;
        web)      body_web ;;
        secours)  body_secours ;;
        divers)   body_divers ;;
        *) return 1 ;;
    esac
    return 0
}

cmd_find()
{
    M="$1"
    [ -n "$M" ] || { echo "[ERREUR] usage : tips FIND <motif>" ; return 1 ; }
    ALL="$(show_cat reseau ; show_cat ram ; show_cat stockage
           show_cat web ; show_cat secours ; show_cat divers)"
    echo ""
    echo "=== TIPS contenant '$M' ==="
    HITS="$(printf '%s\n' "$ALL" | grep -i -A1 -- "$M" | sed 's/^$//')"
    if [ -n "$HITS" ]; then
        printf '%s\n' "$HITS"
    else
        echo "  (aucun resultat)"
    fi
    echo ""
    return 0
}

usage()
{
    sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
}

main()
{
    case "$1" in
        ""|HELP|-h|--help)
            usage
            echo ""
            echo "categories : $CATS"
            echo ""
            echo "=== LES 5 LES PLUS RENTABLES ==="
            show_cat web
            show_cat ram
            return 0 ;;
        ALL|all)
            for C in $CATS; do show_cat "$C" ; done
            echo ""
            return 0 ;;
        FIND|find) shift ; cmd_find "$@" ;;
        *) if show_cat "$1"; then echo "" ; else
               echo "categorie inconnue : '$1' ($CATS ou ALL/FIND)"
               return 1
           fi ;;
    esac
    return 0
}

if [ "$RUNLOG_LOADED" -eq 1 ] && runlog_start "$SCRIPT_ID"; then
    main "$@" >> "$RUNLOG_FILE" 2>&1 ; RC=$?
    runlog_end "$RC" ; cat "$RUNLOG_FILE"
else
    main "$@" ; RC=$?
fi
exit "$RC"
