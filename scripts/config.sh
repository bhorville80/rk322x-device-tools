#!/system/bin/sh
# config - consultation et modification interactive de la configuration.
#
#   config              affiche TOUTE la configuration en une page puis
#                       boucle interactive : numero -> modifier la cle
#   config <numero>     edite directement la cle numero N
#   config GET <CLE>    valeur effective d'une cle (script)
#   config SET <CLE> <valeur>   modification directe (validation incluse)
#   config CHECK        lance conf_check sur la configuration courante
#   config HELP         cette aide
#
# Ecriture : seule la ligne CLE=valeur est remplacee (commentaires et cles
# commentees preserves). Validation par type avant ecriture (IP, port,
# booleen, enum, numerique, texte libre).
#
# Trace : log/exec/config_<TS>.log uniquement pour les modes scriptables
# (GET/SET/CHECK/HELP) ; les sessions interactives ne sont pas tracees
# (l'affichage temps reel prime sur la trace).

SCRIPT_ID="$(basename "$0" .sh)"

# lecture interactive : tty si dispo (le stdout peut etre redirige), sinon stdin
TTY_RD="/dev/tty"
[ -r /dev/tty ] || TTY_RD=""

rd()
{
    # rd VAR "invite" -> lit une ligne dans VAR (jamais d'echec bloquant)
    printf '%s' "$2"
    if [ -n "$TTY_RD" ]; then
        IFS= read -r "$1" < "$TTY_RD" && return 0
    else
        IFS= read -r "$1" && return 0
    fi
    eval "$1=''"
    return 0
}

RUNLOG_LOADED=0
for B in "$(dirname "$0")" /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

CFG_LOADED=0
for B in "$(dirname "$0")" /data/scripts; do
    if [ -f "$B/core/config.sh" ]; then
        . "$B/core/config.sh"
        CFG_LOADED=1
        break
    fi
done

BASE="$(cd "$(dirname "$0")" && pwd)"
CONF="${CONFIG_FILE:-/data/scripts/config/device.conf}"

if [ ! -f "$CONF" ]; then
    echo "[ERREUR] device.conf introuvable ($CONF)"
    echo "         deploy INSTALL ou sync_usb a faire d'abord"
    exit 1
fi

# edition sous /data -> root requis (la cle USB reste accessible sans root)
case "$CONF" in
    /data/*)
        case "$(id -u 2>/dev/null)" in
            0) ;;
            *)
                case "$(id 2>/dev/null)" in
                    "uid=0("*) ;;
                    *)
                        echo "[ERREUR] privileges root requis pour editer $CONF"
                        echo "         relancer : su -c \"sh $0 $*\""
                        exit 1
                        ;;
                esac
                ;;
        esac
        ;;
esac

# ------------------------------------------------------------ validation

is_ip()
{
    case "$1" in
        *[!.0-9]*|'') return 1 ;;
    esac
    OIFS="$IFS"
    IFS=.
    set -- $1
    IFS="$OIFS"
    [ $# -eq 4 ] || return 1
    for O in "$@"; do
        case "$O" in ''|*[!0-9]*) return 1 ;; esac
        [ "$O" -le 255 ] 2>/dev/null || return 1
    done
    return 0
}

is_num()
{
    case "$1" in ''|*[!0-9]*) return 1 ;; esac
    return 0
}

# valide KEY/Valeur ; message d'erreur dans ERR si KO
validate()
{
    K="$1"
    V="$2"
    ERR=""

    case "$K" in
        IP|GATEWAY|DNS|NETMASK|HW_PATCH)
            is_ip "$V" || { ERR="adresse IPv4 attendue (a.b.c.d)" ; return 1 ; } ;;
        PREFIX|SSH_PORT|ADB_PORT|RAM_MB|MEM_ZRAM_MB|MEM_SWAPPINESS|\
        LOGD_SIZE_KB|SD_WAIT_SEC|FD_ROTATE_SEC|MEM_SWAP_MB)
            is_num "$V" || { ERR="nombre attendu" ; return 1 ; }
            case "$K" in
                SSH_PORT|ADB_PORT)
                    [ "$V" -ge 1 ] && [ "$V" -le 65535 ] 2>/dev/null \
                        || { ERR="port 1-65535" ; return 1 ; } ;;
                PREFIX)
                    [ "$V" -le 32 ] 2>/dev/null \
                        || { ERR="prefixe 0-32" ; return 1 ; } ;;
            esac ;;
        NETWORK)
            case "$V" in static|dhcp) ;; *) ERR="static|dhcp" ; return 1 ;; esac ;;
        SSH_MODE)
            case "$V" in keys|password|any) ;; *) ERR="keys|password|any" ; return 1 ;; esac ;;
        INTERFACE)
            case "$V" in eth0|wlan0) ;; *) ERR="eth0|wlan0 conseille" ; return 1 ;; esac ;;
        DEPLOY_VERSION)
            is_num "$V" || { ERR="version numerique" ; return 1 ; } ;;
        WIRELESS_AIRPLANE|MEM_LMK_EARLY|BOOT_MEM_TUNE|BOOT_CUT_SERVICES|\
        BOOT_EXPOSE|BOOT_SD_LAST|SD_MOUNT_RO|BOOT_FRONT_CLOCK)
            case "$V" in 0|1) ;; *) ERR="0 ou 1" ; return 1 ;; esac ;;
    esac
    return 0
}

# conseil post-modification selon la famille de la cle
apply_hint()
{
    case "$1" in
        MEM_ZRAM_MB|MEM_SWAPPINESS|MEM_LMK_EARLY|LOGD_SIZE_KB|MEM_SWAP_*)
            echo "[i] effet : mem_tune OPTIMIZE (ou au boot si BOOT_MEM_TUNE=1)" ;;
        BOOT_*)
            echo "[i] effet : au prochain demarrage (boot)" ;;
        SSH_PORT|SSH_MODE|SSH_BIN|SSH_PASSWORD)
            echo "[i] effet : relancer ssh_server (ou reboot)" ;;
        IP|GATEWAY|DNS|NETMASK|PREFIX|NETWORK|INTERFACE|ADB_PORT)
            echo "[i] effet : set_network APPLY puis check_state" ;;
        WIRELESS_AIRPLANE)
            echo "[i] effet : disable_wireless OFF/OFF+avion" ;;
        SERVICES_CUT*|PACKAGES_DISABLE*)
            echo "[i] effet : cut_services CUT (ou au boot si BOOT_CUT_SERVICES=1)" ;;
        FD_FORMAT|FD_ROTATE_SEC|FD_ROTATE_ITEMS|REMOTE_KL_DEVICE)
            echo "[i] effet : front_digit ROTATE / remote_map STATUS" ;;
    esac
}

# -------------------------------------------------------------- lecture

# liste des cles actives du fichier (ordre du fichier preserve)
list_keys()
{
    grep -E '^[A-Z_]+=' "$CONF" 2>/dev/null | sed 's/=.*//' | tr -d '\r'
}

key_value()
{
    sed -n "s/^$1=//p" "$CONF" 2>/dev/null | head -n 1 | tr -d '\r'
}

# --------------------------------------------------------------- ecriture

write_key()
{
    K="$1"
    V="$2"
    TMP="${CONF}.tmp.$$"

    awk -v k="$K" -v v="$V" '
        BEGIN { FS="=" ; done=0 }
        !done && $0 ~ "^"k"=" { print k "=" v ; done=1 ; next }
        { print }
        END { if (!done) exit 3 }
    ' "$CONF" > "$TMP" 2>/dev/null || { rm -f "$TMP" ; return 1 ; }

    mv -f "$TMP" "$CONF" 2>/dev/null || { rm -f "$TMP" ; return 1 ; }

    V_CHK="$(key_value "$K")"
    [ "$V_CHK" = "$V" ]
}

# ------------------------------------------------------------- affichage

show_page()
{
    echo ""
    echo "=== CONFIGURATION ACTIVE ==="
    echo "fichier : $CONF"
    echo ""

    N=0
    KEYS="$(list_keys)"
    printf '%s\n' "$KEYS" | while IFS= read -r K; do
        [ -z "$K" ] && continue
        N=$((N+1))
        V="$(key_value "$K")"
        printf '[%2s] %-22s %s\n' "$N" "$K" "${V:-<vide>}"
    done

    echo ""
    echo "modifier : entrer un numero | entree seule = quitter | HELP = aide"
}

edit_flow()
{
    K="$1"
    CUR="$(key_value "$K")"

    echo ""
    echo "Cle     : $K"
    echo "Actuel  : ${CUR:-<vide>}"
    rd V "Nouvelle valeur (entree seule = annuler) : "
    case "$V" in
        '') echo "annule" ; return 0 ;;
    esac

    validate "$K" "$V" || { echo "[KO] $ERR" ; return 1 ; }

    rd OK "Enregistrer $K=$V ? [o/N] "
    case "$OK" in
        o|O|y|Y) ;;
        *) echo "annule" ; return 0 ;;
    esac

    if write_key "$K" "$V"; then
        echo "[ OK ] $K=$V"
        apply_hint "$K"
    else
        echo "[ ERREUR ] ecriture impossible ($CONF)"
        return 1
    fi
}

help_show()
{
    echo ""
    echo "=== CONFIG - configuration interactive ==="
    echo ""
    echo "Usage:"
    echo "  config                page complete puis boucle interactive"
    echo "  config <numero>       edite la cle numero N directement"
    echo "  config GET <CLE>      valeur effective"
    echo "  config SET <CLE> <valeur>   modification directe validee"
    echo "  config CHECK          conf_check sur la configuration"
    echo "  config HELP           cette aide"
    echo ""
    echo "Notes:"
    echo "  - seules les cles actives (CLE=valeur) sont listees ; les cles"
    echo "    commentees (#CLE=...) restent documentees dans le fichier"
    echo "  - validation par type : IPv4, ports, booleens 0/1, enums,"
    echo "    numeriques ; le reste en texte libre"
    echo "  - apres modification, un rappel indique comment appliquer"
}

# ------------------------------------------------------------------ main

main()
{
    case "$1" in
        ""|SHOW|show)
            while true; do
                show_page
                rd N "> "
                case "$N" in
                    '')             echo "" ; return 0 ;;
                    HELP|help|-h)   help_show ; continue ;;
                    CHECK|check)    sh "$BASE/conf_check.sh" ; continue ;;
                esac
                case "$N" in
                    ''|*[!0-9]*) echo "[KO] numero attendu ($N)" ; continue ;;
                esac
                K="$(printf '%s\n' "$(list_keys)" | sed -n "${N}p")"
                if [ -z "$K" ]; then
                    echo "[KO] pas de cle numero $N"
                    continue
                fi
                edit_flow "$K"
            done
            ;;
        GET|get)
            [ -n "$2" ] || { echo "usage : config GET <CLE>" ; return 1 ; }
            V="$(key_value "$2")"
            if [ -z "$V" ] && ! printf '%s' "$(list_keys)" | grep -qx "$2"; then
                echo "[KO] cle inconnue : $2"
                return 1
            fi
            echo "${V:-}"
            ;;
        SET|set)
            [ -n "$2" ] && [ -n "$3" ] || {
                echo "usage : config SET <CLE> <valeur>" ; return 1 ;
            }
            K="$2"
            V="$3"
            printf '%s' "$(list_keys)" | grep -qx "$K" \
                || { echo "[KO] cle absente/inactive : $K" ; return 1 ; }
            validate "$K" "$V" || { echo "[KO] $ERR" ; return 1 ; }
            if write_key "$K" "$V"; then
                echo "[ OK ] $K=$V"
                apply_hint "$K"
                return 0
            fi
            echo "[ ERREUR ] ecriture impossible ($CONF)"
            return 1
            ;;
        CHECK|check)
            sh "$BASE/conf_check.sh"
            return $?
            ;;
        HELP|-h|--help)
            help_show
            return 0
            ;;
        *)
            case "$1" in
                *[!0-9]*|'')
                    echo "argument inconnu : $1 (voir : config HELP)"
                    return 1
                    ;;
            esac
            K="$(printf '%s\n' "$(list_keys)" | sed -n "$1p")"
            [ -n "$K" ] || { echo "[KO] pas de cle numero $1" ; return 1 ; }
            edit_flow "$K"
            return $?
            ;;
    esac
}

# trace uniquement les modes scriptables ; interactif = affichage temps reel
case "$1" in
    ""|SHOW|show|[0-9]*) INTERACTIVE=1 ;;
    *)                   INTERACTIVE=0 ;;
esac

if [ "$INTERACTIVE" -eq 0 ] && [ "$RUNLOG_LOADED" -eq 1 ] && runlog_start "$SCRIPT_ID"; then
    main "$@" >> "$RUNLOG_FILE" 2>&1
    RC=$?
    runlog_end "$RC"
    cat "$RUNLOG_FILE"
else
    main "$@"
    RC=$?
fi
exit "$RC"
