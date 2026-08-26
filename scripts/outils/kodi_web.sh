#!/system/bin/sh
# kodi_web - serveur HTTP integre de Kodi (port 8080) vs API du kit (port 8180).
#
# La telecommande web de Kodi ("Allow remote control via HTTP") ecoute PAR
# DEFAUT sur le port 8080. L'API du kit est desormais sur 8180, donc plus
# de conflit direct, mais Kodi peut quand meme monopoliser des ressources.
# Cet outil neutralise le conflit COTE CONFIG, sans desinstaller Kodi.
#
# Usage: kodi_web [STATUS|OFF|ON|HELP]
#
#   STATUS   etat setting + processus Kodi + port 8080 (defaut)
#   OFF      force-stop Kodi puis retire l'override services.webserver
#            -> Kodi retombe sur son defaut (webserver=false) ; libere 8080
#   ON       reactive la telecommande web de Kodi (port 8080)
#
# Sauvegarde unique avant modification : guisettings.xml.kitbak

PKG="org.xbmc.kodi"
GS="/data/$PKG/.kodi/userdata/guisettings.xml"

# auto-elevation : /data/data/<pkg> + am sont root-only
if [ "$(id -u 2>/dev/null)" != "0" ] && \
   [ "$(id 2>/dev/null | cut -d: -f1)" != "uid=0" ] && \
   command -v su > /dev/null 2>&1; then
    echo "[*] uid non root : relance automatique via su..."
    exec su -c "sh '$0' $*"
fi

kodi_pid()
{
    for D in /proc/[0-9]*; do
        P="${D#/proc/}"
        [ "$P" = "$$" ] && continue
        C="$(tr '\0' ' ' < "$D/cmdline" 2>/dev/null)"
        case "$C" in
            *$PKG*) printf '%s' "$P" ; return 0 ;;
        esac
    done
    return 1
}

web_val()
{
    # valeur courante du setting (vide si absent -> defaut Kodi = false)
    [ -f "$GS" ] || return 1
    sed -n 's#^.*<setting id="services\.webserver"[^>]*>\([^<]*\)</setting>.*$#\1#p' \
        "$GS" 2>/dev/null | head -n 1 | tr -d '\r'
}

port8080()
{
    if netstat -tln 2>/dev/null | grep -q ":8080 "; then
        printf 'OCCUPE'
        return 0
    fi
    if grep -qi ":1F90 .* 0A " /proc/net/tcp 2>/dev/null; then
        printf 'OCCUPE'
        return 0
    fi
    printf 'libre'
}

do_status()
{
    echo ""
    echo "=== KODI WEB vs API 8080 ==="
    if kodi_pid; then
        echo "  kodi     : tourne (PID $(kodi_pid))"
    else
        echo "  kodi     : arrete"
    fi
    V="$(web_val)"
    case "$V" in
        true)  echo "  setting  : services.webserver = true (telecommande web ACTIVEE)" ;;
        false) echo "  setting  : services.webserver = false" ;;
        "")    echo "  setting  : absent -> defaut Kodi = false" ;;
        *)     echo "  setting  : inattendu ($V)" ;;
    esac
    echo "  port8080 : $(port8080)"
    echo ""
    echo "remedes : kodi_web OFF (libere l'API), net_diag PORTS (qui tient quoi)"
    return 0
}

do_set()
{
    WANT="$1"

    [ -f "$GS" ] || {
        echo "[ERREUR] $GS introuvable (Kodi installe ?)"
        exit 1
    }

    if [ "$WANT" = "false" ]; then
        # stopper Kodi AVANT : il reecrit guisettings.xml en quittant
        if kodi_pid; then
            echo "[*] force-stop $PKG (PID $(kodi_pid))..."
            am force-stop "$PKG" > /dev/null 2>&1
            sleep 1
        fi
    fi

    [ -f "$GS.kitbak" ] || cp -f "$GS" "$GS.kitbak" 2>/dev/null \
        && echo "[i] sauvegarde : $GS.kitbak"

    if [ "$WANT" = "true" ]; then
        # insertion avant </settings> (absent = defaut false chez Kodi)
        OUT_T="/data/local/tmp/kodi_web.$$.xml"
        awk 'BEGIN{d=0}
             /<\/settings>/ && !d {
                 print "  <setting id=\"services.webserver\" default=\"false\">true</setting>"
                 d=1
             }
             { print }' "$GS" > "$OUT_T" 2>/dev/null \
            && mv -f "$OUT_T" "$GS" \
            || { rm -f "$OUT_T"; echo "[ERREUR] ecriture impossible dans $GS"; exit 1; }
        echo "[WARN] telecommande web Kodi activee (port 8080)"
    else
        # retirer l'override -> Kodi retombe sur son defaut (webserver=false)
        OUT_T="/data/local/tmp/kodi_web.$$.xml"
        grep -v 'setting id="services\.webserver"' "$GS" > "$OUT_T" 2>/dev/null \
            && mv -f "$OUT_T" "$GS" \
            || { rm -f "$OUT_T"; echo "[ERREUR] ecriture impossible dans $GS"; exit 1; }
    fi

    V="$(web_val)"
    case "$WANT:$V" in
        false:|false:"")
            echo "[ OK ] services.webserver -> defaut (desactive : port 8080 libere)"
            ;;
        false:*)
            echo "[ERREUR] override toujours present ($V)"
            exit 1
            ;;
        true:true)
            echo "[ OK ] services.webserver = true"
            ;;
        *)
            echo "[ERREUR] valeur finale inattendue ($V)"
            exit 1
            ;;
    esac
    echo "port 8080 : $(port8080)"
    return 0
}

case "$1" in
    ""|STATUS|status) do_status ;;
    OFF|off)          do_set false ;;
    ON|on)            do_set true ;;
    HELP|help|-h|--help)
        sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
        ;;
    *)
        echo "argument inconnu : $1 (voir : kodi_web HELP)"
        exit 1
        ;;
esac

exit 0
