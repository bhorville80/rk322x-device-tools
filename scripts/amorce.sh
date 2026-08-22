#!/system/bin/sh
# amorce - point d'entree unique sur la box apres le premier INSTALL.
# Localise la cle, compare les versions et rappelle/execute les
# commandes utiles. Les actions sensibles s'elevent seules via su.
#
# Usage: amorce [INSTALL|EXPOSE|STOP|SEND_LOGS|SELFTEST|VERSION|help]

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

find_key()
{
    for d in /mnt/media_rw/*; do
        [ -d "$d" ] || continue
        [ -f "$d/deploy.sh" ] || continue
        KEY="$d"
        return 0
    done
    return 1
}

conf_ver()
{
    sed -n 's/^DEPLOY_VERSION=//p' "$1/config/device.conf" 2>/dev/null | head -n 1 | tr -d '\r'
}

is_root()
{
    [ "$(id -u 2>/dev/null)" = "0" ]
}

run_priv()
{
    # $@ : chemin script + args ; elevation su si necessaire
    if is_root; then
        sh "$@"
    else
        echo "[*] elevation su..."
        su -c "sh $*"
    fi
}

do_status()
{
    echo ""
    echo "=== RK322X AMORCE ==="
    echo "  device   : $(getprop ro.product.device 2>/dev/null) / Android $(getprop ro.build.version.release 2>/dev/null)"
    echo "  uid      : $(id -u 2>/dev/null)$(is_root && echo ' (root)')"
    echo ""

    INSTALLED=""
    [ -f /data/scripts/deploy.sh ] && INSTALLED="oui v$(conf_ver /data/scripts)"
    printf '  %-10s : %s\n' "Installe" "${INSTALLED:-non (voir AMORCE a la racine de la cle)}"

    if find_key; then
        echo "  Cle       : $KEY (v$(conf_ver "$KEY"))"
        case "$(conf_ver "$KEY")" in
            "") ;;
            *)
                case "$INSTALLED" in
                    *"v$(conf_ver "$KEY")") echo "  Etat      : a jour" ;;
                    *)                      echo "  Etat      : difference -> amorce INSTALL" ;;
                esac
                ;;
        esac
    else
        echo "  Cle       : absente (deploy.sh introuvable dans /mnt/media_rw/*)"
    fi

    echo ""
    echo "Commandes :"
    echo "  amorce INSTALL     installe/met a jour depuis la cle"
    echo "  amorce EXPOSE      HTTP 8000 sur la cle (+ GUI 8081)"
    echo "  amorce SELFTEST    tous les outils repondent ?"
    echo "  amorce STOP        arrete les serveurs"
    echo "  amorce SEND_LOGS   collecte des logs sur la cle"
    echo "  amorce VERSION     versions detaillees"
    echo ""
    return 0
}

case "$1" in
    ""|HELP|help|-h|--help)
        do_status
        ;;
    INSTALL)
        find_key || { echo "[ERREUR] aucune cle : inserer la cle puis reessayer"; exit 1; }
        run_priv "$KEY/deploy.sh" INSTALL
        ;;
    EXPOSE)
        find_key || { echo "[ERREUR] aucune cle"; exit 1; }
        run_priv "$KEY/deploy.sh" EXPOSE
        ;;
    STOP)
        run_priv /data/scripts/deploy.sh STOP 2>/dev/null || \
        { find_key && run_priv "$KEY/deploy.sh" STOP; }
        ;;
    SEND_LOGS)
        run_priv /data/scripts/deploy.sh SEND_LOGS 2>/dev/null || \
        { find_key && run_priv "$KEY/deploy.sh" SEND_LOGS; }
        ;;
    SELFTEST)
        if [ -f /data/scripts/selftest.sh ]; then
            run_priv /data/scripts/selftest.sh
        elif find_key; then
            run_priv "$KEY/scripts/selftest.sh"
        else
            echo "[ERREUR] selftest introuvable (ni installe ni sur cle)"
            exit 1
        fi
        ;;
    VERSION|version)
        if [ -f /data/scripts/deploy.sh ]; then
            run_priv /data/scripts/deploy.sh VERSION
        else
            do_status
        fi
        ;;
    *)
        echo "Usage: amorce [INSTALL|EXPOSE|STOP|SEND_LOGS|SELFTEST|VERSION]"
        exit 1
        ;;
esac
