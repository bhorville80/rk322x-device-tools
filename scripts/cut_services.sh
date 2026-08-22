#!/system/bin/sh
# cut_services - allegement box pour exploitation 24/7 :
# coupe les services init inutiles et desactive les paquets usine,
# avec mesure du gain RAM. RESTORE remet l'etat (voir notes en fin).
#
# Usage: cut_services.sh <STATUS|CUT|RESTORE|help>

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
    if [ -f "$B/config.sh" ]; then
        . "$B/config.sh"
        break
    fi
done

# --- listes par defaut ---

# services init sans role sur une box sans ecran
# (stop non persistant : reviennent au reboot)
SVC_SAFE_DEFAULT="perfprofd bootanim cameraserver debuggerd console"

# phase 2 (CUT FULL) : services coupables si AUCUNE lecture media/audio
# sur la box elle-meme (serveur de fichiers pur)
SVC_FULL_EXTRA="audioserver drm mediadrm mediacodec mediaextractor media"

# services init optionnels : coupables, impact fonctionnel possible
SVC_OPT="audioserver drm mediadrm mediacodec mediaextractor media gatekeeperd"

# paquets usine inutiles hors chaine de production
# (desactivation persistante, survit au reboot)
PKG_SAFE_DEFAULT="com.cghs.stresstest com.rockchip.devicetest android.rockchip.update.service com.google.android.katniss"

# paquets optionnels : gros gains mais impact fonctionnel possible
PKG_OPT="com.google.android.gms com.android.vending com.rockchips.dlna com.rockchips.mediacenter com.Swelb.zonglaunher com.example.changeled com.android.systemui com.android.inputmethod.latin"

# preset "finalite serveur sans ecran" : applique par la commande APPS.
# Garantis conserves : launcher, systemui, tv settings, clavier,
# et les apps utilisateur (kodi/netflix/youtube) : a ajouter
# manuellement via PACKAGES_DISABLE si voulu.
PKG_SERVER_PRESET="com.google.android.gms com.android.vending com.google.android.katniss com.google.android.ext.services com.rockchips.mediacenter com.rockchips.dlna com.example.changeled com.cghs.stresstest com.rockchip.devicetest android.rockchip.update.service"

# phase 2 (APPS MAX) : coupe AUSSI l'interface TV. La box devient
# purement headless : plus d'ecran utile avant RESTORE/reboot.
PKG_UI_MAX="com.Swelb.zonglaunher com.android.systemui com.android.tv.settings com.android.inputmethod.latin"

effective_svcs()
{
    L="$(config_get SERVICES_CUT "")"
    [ -z "$L" ] && L="$SVC_SAFE_DEFAULT"
    KEEP="$(config_get SERVICES_CUT_KEEP "")"
    for S in $L; do
        case " $KEEP " in *" $S "*) continue ;; esac
        printf '%s\n' "$S"
    done
}

extra_pkgs()
{
    config_get PACKAGES_DISABLE ""
}

kept_pkgs()
{
    config_get PACKAGES_DISABLE_KEEP ""
}

server_pkgs()
{
    KEEP="$(kept_pkgs)"
    for P in $PKG_SERVER_PRESET; do
        case " $KEEP " in *" $P "*) continue ;; esac
        printf '%s\n' "$P"
    done
}

ui_pkgs()
{
    KEEP="$(kept_pkgs)"
    for P in $PKG_UI_MAX; do
        case " $KEEP " in *" $P "*) continue ;; esac
        printf '%s\n' "$P"
    done
}

effective_svcs_full()
{
    effective_svcs
    for S in $SVC_FULL_EXTRA; do
        KEEP="$(config_get SERVICES_CUT_KEEP "")"
        case " $KEEP " in *" $S "*) continue ;; esac
        printf '%s\n' "$S"
    done
}

safe_pkgs()
{
    BASE="$PKG_SAFE_DEFAULT $(extra_pkgs)"
    KEEP="$(kept_pkgs)"
    for P in $BASE; do
        case " $KEEP " in *" $P "*) continue ;; esac
        printf '%s\n' "$P"
    done
}

pkg_installed()
{
    pm list packages 2>/dev/null | grep -q "^package:$1\$"
}

pkg_disabled()
{
    pm list packages -d 2>/dev/null | grep -q "^package:$1\$"
}

svc_state()
{
    getprop "init.svc.$1" 2>/dev/null | tr -d '\r'
}

mem_avail_kb()
{
    sed -n 's/MemAvailable: *\([0-9]*\) kB/\1/p' /proc/meminfo 2>/dev/null \
        | head -n 1 | tr -dc '0-9'
}

proc_count()
{
    ps 2>/dev/null | tail -n +2 | wc -l | tr -dc '0-9'
}

in_list()
{
    ITEM="$1"
    LIST="$2"
    echo "$LIST" | grep -qx "$ITEM"
}

tag_svc()
{
    if in_list "$1" "$(effective_svcs)"; then echo "CUT"; return; fi
    case " $SVC_SAFE_DEFAULT $SVC_OPT " in *" $1 "*) ;;
        *) echo "--" ; return ;;
    esac
    case " $SVC_SAFE_DEFAULT " in *" $1 "*) echo "safe" ;; esac
    case " $SVC_OPT "          in *" $1 "*) echo "opt"  ;; esac
}

all_pkgs()
{
    printf '%s\n' "$PKG_SAFE_DEFAULT" "$PKG_OPT"
    extra_pkgs
}

tag_pkg()
{
    SAFE_LIST="$(safe_pkgs)"
    if in_list "$1" "$SAFE_LIST"; then echo "CUT"; return; fi
    case " $PKG_SAFE_DEFAULT $PKG_OPT " in *" $1 "*) ;;
        *) echo "--" ; return ;;
    esac
    case " $PKG_SAFE_DEFAULT " in *" $1 "*) echo "safe" ;; esac
    case " $PKG_OPT "          in *" $1 "*) echo "opt"  ;; esac
}

disable_pkg()
{
    P="$1"
    pm disable-user --user 0 "$P" > /dev/null 2>&1
    if pkg_disabled "$P"; then
        return 0
    fi
    pm disable "$P" > /dev/null 2>&1
    pkg_disabled "$P"
}

snapshot()
{
    MEM_BEFORE="$(mem_avail_kb)"
    PROC_BEFORE="$(proc_count)"
}

report_gain()
{
    MEM_AFTER="$(mem_avail_kb)"
    PROC_AFTER="$(proc_count)"

    echo ""
    echo "--- GAIN MESURE ---"
    echo "  RAM dispo     : avant ${MEM_BEFORE:-?} Ko -> apres ${MEM_AFTER:-?} Ko"

    if [ -n "$MEM_BEFORE" ] && [ -n "$MEM_AFTER" ]; then
        DELTA=$((MEM_AFTER - MEM_BEFORE))
        if [ "$DELTA" -ge 0 ]; then
            echo "  Gain memoire  : +$((DELTA / 1024)) Mo"
        else
            NEG=$(( -DELTA ))
            echo "  Gain memoire  : -$((NEG / 1024)) Mo"
        fi
    fi

    echo "  Processus     : avant ${PROC_BEFORE:-?} -> apres ${PROC_AFTER:-?}"
}

do_status()
{
    echo ""
    echo "=== CUT SERVICES STATUS ==="

    echo ""
    echo "--- RAM / processus ---"
    echo "  RAM disponible : $(mem_avail_kb) Ko"
    echo "  Processus      : $(proc_count)"

    echo ""
    echo "--- Services init (etat actuel) ---"
    printf '  %-18s %-9s %s\n' "SERVICE" "ETAT" "TAG"
    for S in $SVC_SAFE_DEFAULT $SVC_OPT; do
        ST="$(svc_state "$S")"
        [ -z "$ST" ] && ST="absent"
        printf '  %-18s %-9s [%s]\n' "$S" "$ST" "$(tag_svc "$S")"
    done

    echo ""
    echo "--- Paquets (present / desactive) ---"
    printf '  %-38s %-8s %s\n' "PACKAGE" "ETAT" "TAG"
    SEEN=""
    for P in $(all_pkgs); do
        if in_list "$P" "$SEEN"; then continue; fi
        SEEN="$SEEN $P"
        if pkg_disabled "$P"; then
            ST="off"
        elif pkg_installed "$P"; then
            ST="on"
        else
            ST="absent"
        fi
        printf '  %-38s %-8s [%s]\n' "$P" "$ST" "$(tag_pkg "$P")"
    done

    echo ""
    echo "Tags : [CUT]=coupe par CUT  [safe]=dispo sur demande  [opt]=impact possible"
    echo "Config : SERVICES_CUT / SERVICES_CUT_KEEP / PACKAGES_DISABLE /"
    echo "         PACKAGES_DISABLE_KEEP dans config/device.conf"
    echo ""
    return 0
}

do_cut()
{
    MODE="${1:-SAFE}"

    if ! require_root; then
        return 1
    fi

    case "$MODE" in FULL) EFF="$(effective_svcs_full)" ;; *) EFF="$(effective_svcs)" ; MODE="SAFE" ;; esac

    echo ""
    echo "=== CUT SERVICES ($MODE) ==="
    snapshot

    echo ""
    echo "[1] Services init..."
    for S in $EFF; do
        ST="$(svc_state "$S")"
        case "$ST" in
            stopped) echo "    [ -- ] $S deja stopped" ;;
            "")
                echo "    [ -- ] $S inconnu d'init (peut-etre deja coupe)"
                ;;
            *)
                stop "$S" > /dev/null 2>&1
                ST2="$(svc_state "$S")"
                if [ "$ST2" = "stopped" ]; then
                    echo "    [ OK ] $S stopped (etait $ST)"
                else
                    echo "    [ WARN ] $S reste '$ST2'"
                fi
                ;;
        esac
    done

    echo ""
    echo "[2] Paquets..."
    for P in $(safe_pkgs); do
        if ! pkg_installed "$P"; then
            echo "    [ -- ] $P absent"
        elif pkg_disabled "$P"; then
            echo "    [ -- ] $P deja desactive"
        elif disable_pkg "$P"; then
            echo "    [ OK ] $P desactive"
        else
            echo "    [ WARN ] $P non desactive (refus pm ?)"
        fi
    done

    report_gain

    echo ""
    echo "[ NOTES ]"
    echo "  - services init : non persistants (reviennent au reboot)"
    echo "  - paquets       : desactivation persistante (survit au reboot)"
    echo "  - pour reappliquer apres boot : cut_services CUT"
    echo "    ou ajouter les services dans SERVICES_STOP (field_mode OFF)"
    if [ "$MODE" = "FULL" ]; then
        echo "  - mode FULL : services media/audio coupes (aucune lecture locale)"
        echo "    RESTORE les redemarre"
    fi
    echo ""
    return 0
}

do_restore()
{
    if ! require_root; then
        return 1
    fi

    echo ""
    echo "=== RESTORE SERVICES ==="

    echo ""
    echo "[1] Services init..."
    for S in $(effective_svcs); do
        ST="$(svc_state "$S")"
        case "$ST" in
            running) echo "    [ -- ] $S deja running" ;;
            stopped|"")
                start "$S" > /dev/null 2>&1
                ST2="$(svc_state "$S")"
                if [ "$ST2" = "running" ]; then
                    echo "    [ OK ] $S redemarre"
                else
                    echo "    [ WARN ] $S etat '$ST2' (service d'origine ?)"
                fi
                ;;
            *) echo "    [ WARN ] $S etat inattendu '$ST'" ;;
        esac
    done

    echo ""
    echo "[2] Paquets..."
    for P in $(safe_pkgs) $(server_pkgs) $(ui_pkgs); do
        if pkg_installed "$P" && pkg_disabled "$P"; then
            pm enable "$P" > /dev/null 2>&1
            if pkg_disabled "$P"; then
                echo "    [ WARN ] $P toujours desactive"
            else
                echo "    [ OK ] $P reactive"
            fi
        fi
    done

    echo ""
    echo "[ INFO ] un reboot restaure aussi tout l'etat d'origine"
    echo ""
    return 0
}

do_apps()
{
    MAX="$1"

    if ! require_root; then
        return 1
    fi

    echo ""
    echo "=== CUT SERVICES APPS (finalite serveur sans ecran) ==="
    snapshot

    if [ "$MAX" = "MAX" ]; then
        echo ""
        echo "[WARN] mode MAX : l'interface TV est coupee aussi (launcher,"
        echo "       systemui, settings, clavier). Plus d'affichage utile"
        echo "       avant RESTORE ou reboot. Assure-toi d'avoir adb/ssh."
        echo ""
    fi

    echo ""
    echo "[*] Coupe GMS/Play/katniss/DLNA/mediacenter/changeled/tests/OTA"
    echo "    conserves exprès : launcher, systemui, tv settings, clavier,"
    echo "    apps utilisateur (kodi/netflix/youtube...)"
    echo ""
    for P in $(server_pkgs); do
        if ! pkg_installed "$P"; then
            echo "    [ -- ] $P absent"
        elif pkg_disabled "$P"; then
            echo "    [ -- ] $P deja desactive"
        else
            am force-stop "$P" > /dev/null 2>&1
            if disable_pkg "$P"; then
                echo "    [ OK ] $P desactive (+ force-stop)"
            else
                echo "    [ WARN ] $P non desactive (refus pm ?)"
            fi
        fi
    done

    if [ "$MAX" = "MAX" ]; then
        echo ""
        echo "[*] Mode MAX : interface TV..."
        for P in $(ui_pkgs); do
            if ! pkg_installed "$P"; then
                echo "    [ -- ] $P absent"
            elif pkg_disabled "$P"; then
                echo "    [ -- ] $P deja desactive"
            else
                am force-stop "$P" > /dev/null 2>&1
                if disable_pkg "$P"; then
                    echo "    [ OK ] $P desactive (+ force-stop)"
                else
                    echo "    [ WARN ] $P non desactive (refus pm ?)"
                fi
            fi
        done
    fi

    report_gain

    echo ""
    echo "[ NOTES ]"
    echo "  - persistant : survit au reboot ; RESTORE ou reboot usine pour revenir"
    echo "  - exclure un paquet du preset : PACKAGES_DISABLE_KEEP dans device.conf"
    echo "  - en couper davantage (apps perso) : PACKAGES_DISABLE=paquet1 paquet2"
    echo ""
    return 0
}

usage()
{
    echo ""
    echo "Usage: cut_services <STATUS|CUT [SAFE|FULL]|APPS [MAX]|RESTORE>"
    echo ""
    echo "  STATUS   inventaire services/paquets + candidats + RAM (lecture seule)"
    echo "  CUT      coupe la liste SAFE (services init + paquets usine),"
    echo "           mesure le gain RAM"
    echo "  CUT FULL phase 2 : ajoute les services media/audio (aucune lecture"
    echo "           locale : serveur de fichiers pur)"
    echo "  APPS     preset finalite serveur sans ecran : GMS/Play/katniss/"
    echo "           DLNA/mediacenter/changeled/tests usine/OTA desactives"
    echo "           (launcher/UI/clavier/apps perso conserves)"
    echo "  APPS MAX phase 2 extreme : coupe AUSSI l'interface TV (launcher/"
    echo "           systemui/settings/clavier) -> headless total jusqu'a RESTORE"
    echo "  RESTORE  redemarre/reactive ce qui avait ete coupe"
    echo ""
    echo "Personnalisation (config/device.conf) :"
    echo "  SERVICES_CUT          remplace la liste services par defaut"
    echo "  SERVICES_CUT_KEEP     exclut des services de la liste"
    echo "  PACKAGES_DISABLE      ajoute des paquets a desactiver"
    echo "  PACKAGES_DISABLE_KEEP exclut des paquets"
    echo ""
    echo "Liste par defaut : $SVC_SAFE_DEFAULT"
    echo "Paquets par defaut : $PKG_SAFE_DEFAULT"
    echo ""
    return 1
}

case "$1" in
    ""|STATUS|status) do_status ;;
    CUT|cut)          do_cut "$2" ;;
    RESTORE|restore)  do_restore ;;
    APPS|apps)        do_apps "$2" ;;
    HELP|help|-h|--help) usage ;;
    *)                usage ;;
esac
