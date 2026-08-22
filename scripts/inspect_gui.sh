#!/system/bin/sh
# inspect_gui - capacites de l'interface graphique (ecran HDMI / Android UI)
# inventaire en lecture seule de ce qu'il est possible d'afficher sur la TV,
# + deux actions explicites : SHOT (capture d'ecran) et URL <u> (plein ecran).

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

usage()
{
    echo ""
    echo "Usage: inspect_gui.sh [STATUS|SHOT|URL <adresse>|help]"
    echo ""
    echo "  STATUS        inventaire des capacites graphiques (defaut)"
    echo "  SHOT          capture d'ecran -> cle USB ou /data/local/tmp"
    echo "  URL <adresse> ouvre l'adresse dans le navigateur (plein ecran TV)"
    echo "                ex : inspect_gui.sh URL http://192.168.50.20:8000"
    echo ""
}

find_usb_dir()
{
    for d in /mnt/media_rw/*; do
        [ -d "$d" ] || continue
        [ -f "$d/deploy.sh" ] || continue
        USB_DIR="$d"
        return 0
    done
    return 1
}

do_shot()
{
    OUT=""
    TS="$(date '+%Y%m%d-%H%M%S')"
    NAME="gui_shot_$TS.png"

    if find_usb_dir; then
        mkdir -p "$USB_DIR/log/gui_shots" 2>/dev/null && OUT="$USB_DIR/log/gui_shots/$NAME"
    fi
    [ -z "$OUT" ] && { mkdir -p /data/local/tmp 2>/dev/null; OUT="/data/local/tmp/$NAME"; }

    if ! command -v screencap >/dev/null 2>&1; then
        echo "[ERREUR] screencap indisponible sur ce firmware"
        return 1
    fi

    echo "[*] capture -> $OUT ..."
    screencap -p "$OUT" 2>/dev/null || { echo "[ERREUR] capture echouee"; return 1; }
    SIZE="$(ls -l "$OUT" 2>/dev/null | awk '{print $5}')"
    echo "[ OK ] $OUT ($SIZE octets)"
    case "$OUT" in
        /data/local/tmp/*) echo "[ -- ] recuperation : adb pull $OUT" ;;
    esac
    return 0
}

do_url()
{
    U="$1"
    [ -n "$U" ] || { usage; return 1; }
    echo "[*] affichage plein ecran de : $U"
    am start -a android.intent.action.VIEW -d "$U" > /dev/null 2>&1 \
        && echo "[ OK ] intent VIEW envoye (voir la TV)" \
        || echo "[ERREUR] aucune activite resolve (navigateur absent ? voir STATUS [4])"
    return 0
}

main()
{

echo ""
echo "=== INSPECTION INTERFACE GRAPHIQUE ==="

echo ""
echo "[1] Stack affichage (fb / sysfs)"
for F in /dev/graphics/fb*; do
    [ -e "$F" ] || continue
    N="$(basename "$F")"
    VS="$(cat /sys/class/graphics/$N/virtual_size 2>/dev/null | tr '\n' ' ')"
    BP="$(cat /sys/class/graphics/$N/bits_per_pixel 2>/dev/null)"
    NM="$(cat /sys/class/graphics/$N/name 2>/dev/null)"
    printf '      %-8s %-14s %sx%s %s\n' "$N" "${NM:-?}" "${VS%% *}" "${VS##* }" "${BP:+(${BP}bpp)}"
done
BLANK="$(cat /sys/class/graphics/fb0/blank 2>/dev/null)"
case "$BLANK" in
    1) echo "      etat   : fb0 blank (ecran coupe, field mode)" ;;
    0) echo "      etat   : fb0 actif" ;;
    *) echo "      etat   : blank illisible (${BLANK:-absent})" ;;
esac
echo "      note   : ecriture directe possible -> dd/if=<img> of=/dev/graphics/fb0 (brut, sans UI Android)"

echo ""
echo "[2] Fenetres / activite au premier plan"
wm size 2>/dev/null | sed 's/^/      /'
wm density 2>/dev/null | sed 's/^/      /'
FOCUS="$(dumpsys window 2>/dev/null | grep -E 'mCurrentFocus|mFocusedWindow' | head -n 2)"
if [ -n "$FOCUS" ]; then
    echo "$FOCUS" | sed 's/^/      /'
else
    echo "      [ -- ] focus window illisible"
fi
NBWIN="$(dumpsys window windows 2>/dev/null | grep -c '^  Window #')"
echo "      fenetres ouvertes : ${NBWIN:-?}"

echo ""
echo "[3] Rendu sans ecran (screencap)"
if command -v screencap >/dev/null 2>&1; then
    T="/data/local/tmp/.probe_gui_$$.png"
    if screencap -p "$T" 2>/dev/null && [ -s "$T" ]; then
        S="$(ls -l "$T" | awk '{print $5}')"
        echo "      [ OK ] screencap fonctionne meme ecran coupe (${S:-?} octets)"
        echo "             -> boucle de controle visuel a distance possible (inspect_gui.sh SHOT)"
        rm -f "$T"
    else
        rm -f "$T"
        echo "      [ KO ] screencap present mais capture vide"
    fi
else
    echo "      [ -- ] screencap absent de ce firmware"
fi

echo ""
echo "[4] Applications capables d'afficher"
TOTAL="$(pm list packages 2>/dev/null | wc -l)"
echo "      paquets installes : ${TOTAL:-?}"
for KW in launcher browser chrome webview kodi xbmc tv; do
    P="$(pm list packages 2>/dev/null | grep -i "$KW" | head -n 4)"
    [ -z "$P" ] && continue
    echo "      '$KW' :"
    echo "$P" | sed 's/^package://;s/^/        /'
done
echo "      -> am start -a android.intent.action.VIEW -d <url> affiche une page plein ecran si un navigateur existe"

echo ""
echo "[5] Injection d'entrees (pilotage a distance de l'UI)"
if command -v input >/dev/null 2>&1; then
    echo "      [ OK ] commande input disponible"
    echo "             ex : input keyevent KEYCODE_DPAD_RIGHT | input tap <x> <y>"
else
    echo "      [ -- ] commande input absente"
fi
NBIN="$(ls -1 /dev/input 2>/dev/null | grep -c event)"
echo "      peripheriques /dev/input : ${NBIN:-0}"

echo ""
echo "[6] Visuels de demarrage (personnalisation possible ?)"
if [ -f /system/media/bootanimation.zip ]; then
    echo "      bootanimation.zip : present $(ls -l /system/media/bootanimation.zip | awk '{print $1, $5}')"
else
    echo "      bootanimation.zip : absent"
fi
SYST_RW="$(mount 2>/dev/null | grep ' /system ' | grep -c '(rw')"
[ "$SYST_RW" -eq 0 ] && echo "      /system : monte en lecture seule (remount requis pour personnaliser)"
LOGO=0
for B in /dev/block/platform/*/by-name; do
    [ -d "$B" ] || continue
    L="$(ls -1 "$B" 2>/dev/null | grep -icE '^(logo|boot_logo)$')"
    LOGO=$((LOGO+L))
    [ "$L" -gt 0 ] && ls -1 "$B" | grep -iE '^(logo|boot_logo)$' | sed "s|^      |      partition logo : $B/|"
done
[ "$LOGO" -eq 0 ] && echo "      partition logo dediee : non detectee (logo kernel/parametre)"

echo ""
echo "[7] Synthese : que peut-on ajouter au visuel ?"
echo "      1. Page de controle plein ecran : inspect_gui.sh URL http://IP:8000 (index.html du serveur)"
echo "         + pilotage sans telecommande : input keyevent/tap"
echo "      2. Controle visuel a distance : inspect_gui.sh SHOT (fonctionne ecran coupe)"
echo "      3. Dessin brut sans Android : ecriture directe fb0 (images RGB pre-calculees)"
echo "      4. Boot visuel personnalise : bootanimation.zip / partition logo (si /system inscriptible)"
echo "      5. Toasts/overlays systeme : necessite une app dediee (hors perimetre scripts shell)"

echo ""
return 0
}

case "$1" in
    ""|STATUS|status) main ;;
    SHOT|shot)        do_shot ;;
    URL|url)          shift; do_url "$1" ;;
    HELP|help|-h|--help) usage ;;
    *)                usage; exit 1 ;;
esac

exit "$?"
