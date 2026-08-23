#!/system/bin/sh
# remote_map - personnalisation de la telecommande IR (remap des touches).
#
# Principe : le recepteur IR apparait dans /proc/bus/input/devices et ses
# touches sont decrites par un fichier .kl de /system/usr/keylayout
# ("key <scancode> <KEYCODE>"). Modifier ce fichier remappe la telecommande
# systeme (toutes applications). Sur rk322x le recepteur est souvent le
# device "pwm" (ex: 110b0030.pwm) ; rk29-keypad ne porte que la touche
# POWER de la face avant -> detection : pwm/remote/rc AVANT keypad.
#
#   remote_map                 etat : device cible, layout, ecart vs origine
#   remote_map STATUS          idem
#   remote_map DEVICES         liste des devices input + layout attendu
#   remote_map LEARN [s]       ecoute les appuis (defaut 15 s) et propose
#                              les commandes MAP pretes a coller
#   remote_map LIST            contenu du layout cible
#   remote_map MAP 102=BUTTON_A 158=BACK ...
#                              applique scancode=KEYCODE (backup auto)
#   remote_map RESET           restaure le layout d'origine (backup)
#
# NOTE : le remap est actif apres un REBOOT (rechargement des layouts).
# Securite : le fichier d'origine est sauvegarde au premier MAP (RESET
# le remet). Ecriture via system_rw (remount rw puis ro).
# Config : REMOTE_KL_DEVICE=<nom> pour forcer le device cible.

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" "$(dirname "$0")/.." /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

for B in "$(dirname "$0")" "$(dirname "$0")/.." /data/scripts; do
    if [ -f "$B/core/config.sh" ]; then
        . "$B/core/config.sh"
        break
    fi
done

command -v config_get >/dev/null 2>&1 || config_get() { echo "$2"; }
command -v is_root >/dev/null 2>&1 || is_root() { case "$(id -u 2>/dev/null)" in 0) return 0 ;; esac; case "$(id 2>/dev/null)" in "uid=0("*) return 0 ;; esac; return 1; }

INPUT_DEVICES="/proc/bus/input/devices"
KL_DIR="/system/usr/keylayout"
Q='"'

# ---- enumeration des devices input (sans awk : boucle sh portable) ----

input_records()
{
    # $1 fichier ; sortie : name|bus|vendor|product|handlers
    [ -r "$1" ] || return 1
    NAME="" ; BUS="" ; VEN="x" ; PRD="x" ; EVH=""
    while IFS= read -r LINE; do
        case "$LINE" in
            I:*)
                REST="${LINE#I: }"
                for W in $REST; do
                    case "$W" in
                        Bus=*)     BUS="${W#Bus=}" ;;
                        Vendor=*)  VEN="${W#Vendor=}" ;;
                        Product=*) PRD="${W#Product=}" ;;
                    esac
                done
                ;;
            N:*)
                NAME="${LINE#*Name=$Q}"
                NAME="${NAME%%$Q*}"
                ;;
            H:*)
                REST="${LINE#*Handlers=}"
                for W in $REST; do
                    case "$W" in
                        event*) [ -z "$EVH" ] && EVH="$W" ;;
                    esac
                done
                ;;
            "")
                [ -n "$NAME" ] && printf '%s|%s|%s|%s|%s\n' "$NAME" "$BUS" "$VEN" "$PRD" "$EVH"
                NAME="" ; BUS="" ; EVH=""
                ;;
        esac
    done < "$1"
    [ -n "$NAME" ] && printf '%s|%s|%s|%s|%s\n' "$NAME" "$BUS" "$VEN" "$PRD" "$EVH"
    return 0
}

pick_remote()
{
    # priorite : REMOTE_KL_DEVICE, nom evocateur, sinon premier bus 0019
    WANT="$(config_get REMOTE_KL_DEVICE "")"
    ALL="$(input_records "$INPUT_DEVICES")"
    [ -n "$ALL" ] || return 1

    if [ -n "$WANT" ]; then
        LINE_W="$(printf '%s\n' "$ALL" | grep "^${WANT}|" | head -n 1)"
        if [ -n "$LINE_W" ]; then
            printf '%s\n' "$LINE_W"
            return 0
        fi
        echo "[WARN] REMOTE_KL_DEVICE='$WANT' absent des devices input"
    fi

    # recepteur IR reel (pwm/remote/rc/ir) AVANT un keypad bouton physique :
    # sur rk322x le recepteur est souvent "110b0030.pwm" et rk29-keypad ne
    # porte que POWER (face avant)
    PICKED="$(printf '%s\n' "$ALL" | grep -iE '^[^|]*(pwm|remote|[.-]ir|ir[.-]|rc[0-9])[^|]*\|' | head -n 1)"
    [ -z "$PICKED" ] && PICKED="$(printf '%s\n' "$ALL" | grep -iE '^[^|]*(keypad|ir)[^|]*\|' | head -n 1)"
    [ -z "$PICKED" ] && PICKED="$(printf '%s\n' "$ALL" | grep '|0019|' | head -n 1)"
    [ -n "$PICKED" ] && { printf '%s\n' "$PICKED"; return 0; }
    return 1
}

kl_candidates()
{
    # $1 name $2 bus $3 vendor $4 product -> candidats .kl par preference
    N="$1" ; V="$3" ; P="$4"
    LOW="$(printf '%s' "$N" | tr 'A-Z ' 'a-z_')"
    printf '%s/%s.kl\n' "$KL_DIR" "$N"
    printf '%s/%s.kl\n' "$KL_DIR" "$LOW"
    printf '%s/Vendor_%s_Product_%s.kl\n' "$KL_DIR" "$V" "$P"
    printf '%s/Generic.kl\n' "$KL_DIR"
}

resolve_target()
{
    REC="$(pick_remote)" || { echo "[ERREUR] aucun device input detecte ($INPUT_DEVICES)"; return 1; }
    T_NAME="${REC%%|*}" ; R="${REC#*|}"
    T_BUS="${R%%|*}"    ; R="${R#*|}"
    T_VEN="${R%%|*}"    ; R="${R#*|}"
    T_PRD="${R%%|*}"    ; T_EVT="${R#*|}"

    KL=""
    for C in $(kl_candidates "$T_NAME" "$T_BUS" "$T_VEN" "$T_PRD"); do
        [ -f "$C" ] && { KL="$C"; break; }
    done
    if [ -z "$KL" ]; then
        echo "[ERREUR] aucun layout .kl trouve pour '$T_NAME'"
        return 1
    fi
    return 0
}

backup_path()
{
    for d in /mnt/media_rw/*; do
        if [ -f "$d/deploy.sh" ]; then
            printf '%s/backup/keylayout/%s.orig' "$d" "$(basename "$KL")"
            return 0
        fi
    done
    printf '/data/backup/keylayout/%s.orig' "$(basename "$KL")"
}

rw_sh_path()
{
    for C in "/data/scripts/system_rw.sh" "$(dirname "$0")/system_rw.sh"; do
        [ -f "$C" ] && { printf '%s' "$C"; return 0; }
    done
    return 1
}

rw_system()
{
    SRW="$(rw_sh_path)" || return 1
    sh "$SRW" RW > /dev/null 2>&1
}

ro_system()
{
    SRW="$(rw_sh_path)"
    [ -n "$SRW" ] && sh "$SRW" RO > /dev/null 2>&1
    return 0
}

is_scancode() { case "$1" in ''|*[!0-9]*) return 1 ;; *) [ "$1" -le 767 ] ;; esac; }
is_keycode()
{
    case "$1" in
        ''|*[!a-zA-Z0-9_]*) return 1 ;;
        *) return 0 ;;
    esac
}

do_devices()
{
    echo ""
    echo "=== INPUT DEVICES ==="
    ALL="$(input_records "$INPUT_DEVICES")"
    if [ -z "$ALL" ]; then
        echo "  [ -- ] $INPUT_DEVICES illisible (hors box ?)"
        return 0
    fi
    printf '\n  %-24s %-8s %-14s %s\n' "NAME" "EVENT" "IDS" "LAYOUT ATTENDU"
    printf '%s\n' "$ALL" | while IFS='|' read -r N BV V P H; do
        GOT=""
        for C in $(kl_candidates "$N" "$BV" "$V" "$P"); do
            [ -f "$C" ] && { GOT="$(basename "$C")"; break; }
        done
        printf '  %-24s %-8s %-14s %s\n' "$N" "${H:-?}" "$BV:$V:$P" "${GOT:-Generic.kl (defaut)}"
    done
    echo ""
    return 0
}

do_list()
{
    resolve_target || return 1
    echo ""
    echo "=== LAYOUT TELECOMMANDE ==="
    echo "  Device : $T_NAME ($T_EVT)"
    echo "  Fichier: $KL"
    echo ""
    sed 's/^/    /' "$KL"
    echo ""
    return 0
}

do_status()
{
    echo ""
    echo "=== REMOTE MAP STATUS ==="

    if ! resolve_target; then
        echo ""
        return 1
    fi
    BK="$(backup_path)"

    echo "  Device cible : $T_NAME ($T_EVT)"
    echo "  Layout       : $KL"
    echo "  Backup       : $( [ -f "$BK" ] && echo "$BK" || echo 'aucun (layout non modifie)')"

    if [ -f "$BK" ]; then
        DIFF_L="$(diff "$BK" "$KL" 2>/dev/null | grep -c '^[<>]')"
        if [ "${DIFF_L:-0}" -eq 0 ]; then
            echo "  Etat         : identique a l'origine"
        else
            echo "  Etat         : MODIFIE ($((DIFF_L)) ligne(s) d'ecart) -> RESET pour revenir"
            diff "$BK" "$KL" 2>/dev/null | grep '^[<>]' | sed 's/^/      /'
        fi
    fi
    echo ""
    return 0
}

do_learn()
{
    DUR="${1:-15}"
    is_num "$DUR" || DUR=15
    resolve_target || return 1
    DEV="/dev/input/$T_EVT"
    [ -e "$DEV" ] || { echo "[ERREUR] $DEV absent"; return 1; }

    echo ""
    echo "=== LEARN (${DUR}s) - $DEV ==="
    echo "Appuie les touches de la telecommande maintenant..."
    echo ""

    TMP="$(mktemp /data/local/tmp/rm_learn_XXXXXX 2>/dev/null)" || TMP="/tmp/rm_learn_$$"
    if command -v timeout > /dev/null 2>&1; then
        timeout "$DUR" getevent "$DEV" > "$TMP" 2>&1
    else
        getevent "$DEV" > "$TMP" 2>&1 &
        GP=$!
        sleep "$DUR"
        kill "$GP" 2>/dev/null
    fi

    SCANS="$(sed -n 's/^\/dev.* 0001 \([0-9a-fA-F][0-9a-fA-F]*\) 00000001$/\1/p' "$TMP" | sort -u)"
    rm -f "$TMP"
    if [ -z "$SCANS" ]; then
        echo "[ -- ] aucun scancode capte (timeout ? recepteur = autre device ? cf. DEVICES)"
        return 1
    fi

    echo "  Scancodes vus -> commandes pretes (KEYCODE a adapter) :"
    printf '%s\n' "$SCANS" | while read -r HEX; do
        DEC=$((16#$HEX))
        CUR="$(grep "^key $DEC " "$KL" 2>/dev/null | tr -s ' ' | cut -d' ' -f3)"
        printf '  key %-4s actuel=%-12s -> remote_map MAP %s=KEYCODE_ICI\n' \
            "$DEC" "${CUR:-?}" "$DEC"
    done
    echo ""
    return 0
}

apply_pair()
{
    # $1 scancode decimal, $2 keycode ; reecrit KL dans un tmp puis remplace
    SC="$1" ; KC="$2"
    NEW="${KL}.new_$$"
    if grep -q "^key $SC " "$KL" 2>/dev/null; then
        sed "s/^key $SC .*/key $SC              $KC/" "$KL" > "$NEW" 2>/dev/null || return 1
    else
        cp -f "$KL" "$NEW" 2>/dev/null || return 1
        printf 'key %s              %s\n' "$SC" "$KC" >> "$NEW"
    fi
    mv -f "$NEW" "$KL" 2>/dev/null || { rm -f "$NEW"; return 1; }
    chmod 644 "$KL" 2>/dev/null
    return 0
}

do_map()
{
    [ $# -ge 1 ] || { usage; return 1; }
    if ! is_root; then
        echo "[ERREUR] privileges root requis : su -c \"sh $0 MAP ...\""
        return 1
    fi
    resolve_target || return 1
    BK="$(backup_path)"

    for PAIR in "$@"; do
        case "$PAIR" in
            *=*) ;;
            *) echo "[ERREUR] format attendu scancode=KEYCODE : '$PAIR'"; return 1 ;;
        esac
        SC="${PAIR%%=*}" ; KC="${PAIR#*=}"
        is_scancode "$SC" || { echo "[ERREUR] scancode invalide : '$SC' (0..767)"; return 1; }
        is_keycode "$KC" || { echo "[ERREUR] keycode invalide : '$KC' (ex BACK, HOME, BUTTON_A)"; return 1; }
    done

    rw_system || { echo "[ERREUR] /system non inscriptible (system_rw RW refuse)"; return 1; }

    RC=0
    if [ ! -f "$BK" ]; then
        BDIR="$(dirname "$BK")"
        mkdir -p "$BDIR" 2>/dev/null
        cp -f "$KL" "$BK" 2>/dev/null \
            && echo "[ OK ] origine sauvegardee -> $BK" \
            || echo "[WARN] backup impossible (RESET ne sera pas possible)"
    fi

    for PAIR in "$@"; do
        SC="${PAIR%%=*}" ; KC="${PAIR#*=}"
        OLD="$(grep "^key $SC " "$KL" 2>/dev/null | tr -s ' ' | cut -d' ' -f3)"
        if apply_pair "$SC" "$KC"; then
            printf '[ OK ] scancode %-4s : %-12s -> %s\n' "$SC" "${OLD:-<ajoute>}" "$KC"
        else
            printf '[ ERREUR ] ecriture scancode %-4s\n' "$SC"
            RC=1
        fi
    done

    ro_system
    echo ""
    if [ "$RC" -eq 0 ]; then
        echo "[ OK ] remap applique - effectif apres reboot (reboot)"
    else
        echo "[ ERREUR ] remap partiel - verifier : remote_map STATUS"
    fi
    echo ""
    return "$RC"
}

do_reset()
{
    if ! is_root; then
        echo "[ERREUR] privileges root requis : su -c \"sh $0 RESET\""
        return 1
    fi
    resolve_target || return 1
    BK="$(backup_path)"
    if [ ! -f "$BK" ]; then
        echo "[ -- ] aucun backup : layout jamais modifie"
        return 0
    fi
    rw_system || { echo "[ERREUR] /system non inscriptible"; return 1; }
    if cp -f "$BK" "$KL" 2>/dev/null && chmod 644 "$KL" 2>/dev/null; then
        ro_system
        echo "[ OK ] layout d'origine restaure - effectif apres reboot"
        return 0
    fi
    ro_system
    echo "[ ERREUR ] restauration impossible ($BK -> $KL)"
    return 1
}

usage()
{
    echo ""
    echo "Usage: remote_map <STATUS|DEVICES|LIST|LEARN [s]|MAP sc=CODE ...|RESET>"
    echo ""
    echo "  STATUS             device cible, layout, modifications actives"
    echo "  DEVICES            devices input + layout associe"
    echo "  LIST               contenu du layout cible"
    echo "  LEARN [s]          capte les appuis IR et propose les MAP"
    echo "  MAP 102=HOME ...   applique les remaps (effectif au reboot)"
    echo "  RESET              restaure le layout d'origine"
    echo ""
    echo "Keycodes courants : HOME BACK MENU VOLUME_UP VOLUME_DOWN POWER"
    echo "DPAD_UP DPAD_DOWN DPAD_LEFT DPAD_RIGHT ENTER BUTTON_A BUTTON_B"
    echo "TV_INPUT MEDIA_PLAY_PAUSE SEARCH NOTIFICATION"
    echo ""
    return 0
}

case "$1" in
    ""|STATUS|status)     do_status ;;
    DEVICES|devices)      do_devices ;;
    LIST|list)            do_list ;;
    LEARN|learn)          shift; do_learn "$@" ;;
    MAP|map)              shift; do_map "$@" ;;
    RESET|reset)          do_reset ;;
    HELP|help|-h|--help)  usage ;;
    *)                    usage ;;
esac
