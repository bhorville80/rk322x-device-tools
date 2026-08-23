#!/system/bin/sh
# boot - persistance au demarrage des optimisations (mem_tune, cut_services,
# expose) via un hook init.
#
# Mecanisme : Android >= 6 importe /system/etc/init/*.rc au boot -> on y
# depose rk322x_tools.rc qui lance CE script sans argument en root
# (class late_start, oneshot). Repli si /system/etc/init inaccessible :
# bloc marque dans /system/etc/install-recovery.sh (service flash_recovery).
#
#   boot                  lance les actions configurees (appele par init)
#   boot INSTALL          pose le hook init (/system remonte rw puis ro)
#   boot REMOVE           retire le hook + le bloc install-recovery
#   boot STATUS           mecanisme actif, actions, dernier passage
#   boot TEST             execute les actions maintenant (comme au boot)
#   boot HELP             cette aide
#
# Pilotage (config/device.conf) :
#   BOOT_MEM_TUNE=1       mem_tune OPTIMIZE a chaque boot
#   BOOT_CUT_SERVICES=1   cut_services CUT a chaque boot
#   BOOT_SET_NETWORK=1    set_network a chaque boot (route+DNS non persistants)
#   BOOT_TIME_SYNC=1      set_time AUTO a chaque boot (sortie de l'etat 1970)
#   BOOT_EXPOSE=1         pile web demarree a chaque boot (ports 8000/8080/8081)
#   BOOT_SD_LAST=1        carte SD examinee en TOUT DERNIER (sd_boot CHECK)
#   BOOT_FRONT_CLOCK=1    horloge frontale custom (front_digit CLOCK)

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

BASE="$(cd "$(dirname "$0")" && pwd)"

RC_DIR="/system/etc/init"
RC_FILE="$RC_DIR/rk322x_tools.rc"
RC_NAME="rk322x_tools"
IR_SH="/system/etc/install-recovery.sh"
MK_BEGIN="# >>> RK322X TOOLS >>>"
MK_END="# <<< RK322X TOOLS <<<"
INITD_DIR="/system/etc/init.d"
INITD_FILE="$INITD_DIR/95rk322x_tools"

# support init.d ? (service sysinit/run-parts dans les rc, ou dossier deja la)
detect_initd()
{
    [ -d "$INITD_DIR" ] && return 0
    grep -qlsE 'run-parts|sysinit|init\.d' \
        /system/etc/init.rc "$RC_DIR"/*.rc /system/etc/*.rc 2>/dev/null
}

write_initd()
{
    mkdir -p "$INITD_DIR" 2>/dev/null || return 1
    {
        echo "#!/system/bin/sh"
        echo "# genere par rk322x-device-tools (boot INSTALL) - $(date '+%Y-%m-%d %H:%M:%S')"
        echo "# retire via : sh /data/scripts/boot.sh REMOVE"
        echo "/system/bin/sh /data/scripts/boot.sh > /dev/null 2>&1 &"
    } > "$INITD_FILE" 2>/dev/null || return 1
    chmod 755 "$INITD_FILE" 2>/dev/null
    [ -s "$INITD_FILE" ]
}

remove_initd()
{
    [ -f "$INITD_FILE" ] || return 0
    rm -f "$INITD_FILE" 2>/dev/null
}

flag()
{
    V="$(config_get "$1" "")"
    [ "$V" = "1" ]
}

run_tool()
{
    # $1 label, $2 script, $3... args ; absent -> note et continue
    LBL="$1"; shift
    SH_="$1"; shift
    if [ -f "$SH_" ]; then
        echo "[boot] $LBL..."
        sh "$SH_" "$@" > /dev/null 2>&1 \
            && echo "[boot] $LBL OK" \
            || echo "[boot] $LBL ECHEC (rc=$?)"
    else
        echo "[boot] $LBL : $SH_ absent, saute"
    fi
}

# le port 8000 ecoute-t-il ? (netstat, sinon /proc/net/tcp hexa)
panel_up()
{
    netstat -tln 2>/dev/null | grep -q ":8000 " && return 0
    grep -qi ":1F40 .* 0A " /proc/net/tcp 2>/dev/null && return 0
    return 1
}

do_run()
{
    echo ""
    echo "=== RK322X BOOT - $(date '+%Y-%m-%d %H:%M:%S') ==="

    W="$(config_get BOOT_WAIT_BOOT 120)"
    case "$W" in ''|*[!0-9]*) W=120 ;; esac
    if [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ]; then
        echo "[boot] attente fin de boot (max ${W}s)..."
        I=0
        while [ "$I" -lt "$W" ]; do
            [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ] && break
            sleep 3
            I=$((I+3))
        done
        [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ] \
            && echo "[boot] boot termine (${I}s)" \
            || echo "[boot] timeout ${W}s, poursuite quand meme"
    fi

    # la cle USB peut s'enumerer LONGTEMPS apres boot_completed sur ce
    # socle : sans elle aucun script n'est disponible -> attente bornee
    KW="$(config_get BOOT_WAIT_KEY 150)"
    case "$KW" in ''|*[!0-9]*) KW=150 ;; esac
    if ! ls /mnt/media_rw/*/deploy.sh > /dev/null 2>&1; then
        echo "[boot] attente de la cle USB (max ${KW}s)..."
        I=0
        while [ "$I" -lt "$KW" ]; do
            ls /mnt/media_rw/*/deploy.sh > /dev/null 2>&1 && break
            sleep 3
            I=$((I+3))
        done
        if ls /mnt/media_rw/*/deploy.sh > /dev/null 2>&1; then
            echo "[boot] cle presente (${I}s)"
        else
            echo "[boot] ABANDON : cle absente apres ${KW}s (retirer/reinsérer ou vérifier alimentation USB)"
            return 1
        fi
    fi

    if flag BOOT_MEM_TUNE; then
        run_tool "mem_tune OPTIMIZE" "$BASE/mem_tune.sh" OPTIMIZE
    fi
    if flag BOOT_CUT_SERVICES; then
        run_tool "cut_services CUT" "$BASE/cut_services.sh" CUT
    fi
    if flag BOOT_SET_NETWORK; then
        # route/DNS non persistants sur ce firmware : reapplication au boot
        # (sinon passerelle absente -> WARN check_state, pas de NTP possible)
        run_tool "set_network (route+DNS)" "$BASE/set_network.sh"
    fi
    if flag BOOT_TIME_SYNC; then
        # horloge : INIT sort de l'etat 1970, FILE utilise SET_HEURE de la cle,
        # le reseau affine ensuite (TIME_SYNC panneau / provision --fix)
        run_tool "set_time AUTO" "$BASE/set_time.sh" AUTO
    fi
    if flag BOOT_EXPOSE; then
        run_tool "deploy STOP"      "$BASE/deploy.sh" STOP
        run_tool "deploy EXPOSE"    "$BASE/deploy.sh" EXPOSE
        # verification effective : le panneau doit ecouter ; une seule
        # relance si le port n'est pas la (course d'arret/demarrage)
        sleep 3
        if ! panel_up; then
            echo "[boot] port 8000 absent -> relance EXPOSE..."
            sh "$BASE/deploy.sh" EXPOSE > /dev/null 2>&1
            sleep 3
        fi
        panel_up && echo "[boot] panneau OK (8000)" \
                || echo "[boot] ECHEC panneau (tester deploy EXPOSE manuel)"
    fi
    if flag BOOT_FRONT_CLOCK; then
        # horloge custom frontale : remplace le daemon usine
        # bornee par timeout si dispo : la suite du boot (sd_boot, motd)
        # ne doit jamais dependre d'un outil qui ne rend pas la main
        if [ -f "$BASE/front_digit.sh" ]; then
            echo "[boot] front_digit CLOCK..."
            if command -v timeout > /dev/null 2>&1; then
                timeout 90 sh "$BASE/front_digit.sh" CLOCK > /dev/null 2>&1
            else
                sh "$BASE/front_digit.sh" CLOCK > /dev/null 2>&1
            fi
            [ $? -eq 0 ] \
                && echo "[boot] front_digit OK" \
                || echo "[boot] front_digit ECHEC (PROBE a faire une fois ?)"
        fi
    fi

    # carte SD examinee EN TOUT DERNIER : une carte lente ou problematique
    # ne doit ni bloquer ni retarder le reste du demarrage
    if flag BOOT_SD_LAST; then
        run_tool "sd_boot CHECK" "$BASE/sd_boot.sh" CHECK
    fi

    # banniere d'accueil rafraichie avec l'etat du jour
    [ -f "$BASE/motd.sh" ] && sh "$BASE/motd.sh" DEFAULT > /dev/null 2>&1

    # rotation/purge automatique des logs et rapports anciens
    if flag BOOT_ROTATE_LOGS; then
        run_tool "rotate_logs" "$BASE/rotate_logs.sh"
    fi

    NONE=1
    for K in BOOT_MEM_TUNE BOOT_CUT_SERVICES BOOT_SET_NETWORK BOOT_TIME_SYNC BOOT_EXPOSE BOOT_FRONT_CLOCK BOOT_SD_LAST BOOT_ROTATE_LOGS; do
        flag "$K" && NONE=0 && break
    done
    [ "$NONE" -eq 1 ] && echo "[boot] aucune action active (device.conf BOOT_*)"

    echo "[boot] fini - $(date '+%H:%M:%S')"
    return 0
}

system_rw_sh()
{
    for C in "$BASE/system_rw.sh" /data/scripts/system_rw.sh; do
        [ -f "$C" ] && { echo "$C"; return 0; }
    done
    return 1
}

rw_system()
{
    SRW="$(system_rw_sh)" || { echo "[ERREUR] system_rw.sh introuvable"; return 1; }
    sh "$SRW" RW > /dev/null 2>&1 || return 1
    touch "$RC_DIR/.probe_boot_$$" 2>/dev/null || touch "/system/.probe_boot_$$" 2>/dev/null || return 1
    rm -f "$RC_DIR/.probe_boot_$$" "/system/.probe_boot_$$" 2>/dev/null
    return 0
}

ro_system()
{
    SRW="$(system_rw_sh)"
    [ -n "$SRW" ] && sh "$SRW" RO > /dev/null 2>&1
    return 0
}

write_rc_file()
{
    mkdir -p "$RC_DIR" 2>/dev/null || return 1
    {
        echo "# genere par rk322x-device-tools (boot INSTALL) - $(date '+%Y-%m-%d %H:%M:%S')"
        echo "# retire via : sh /data/scripts/boot.sh REMOVE"
        echo "service $RC_NAME /system/bin/sh /data/scripts/boot.sh"
        echo "    class late_start"
        echo "    user root"
        echo "    oneshot"
    } > "$RC_FILE" 2>/dev/null || return 1
    chmod 644 "$RC_FILE" 2>/dev/null
    [ -s "$RC_FILE" ]
}

ir_has_block()
{
    grep -q "$MK_BEGIN" "$IR_SH" 2>/dev/null
}

ir_install_block()
{
    # bloc dans install-recovery.sh (execute par init en root au boot)
    ir_remove_block
    {
        echo "$MK_BEGIN"
        echo "(sleep 30 ; /system/bin/sh /data/scripts/boot.sh) &"
        echo "$MK_END"
    } >> "$IR_SH" 2>/dev/null || return 1
    chmod 755 "$IR_SH" 2>/dev/null
    ir_has_block
}

ir_remove_block()
{
    [ -f "$IR_SH" ] || return 0
    SED_BEGIN="$(printf '%s' "$MK_BEGIN" | sed 's/[&/]/\\&/g')"
    SED_END="$(printf '%s' "$MK_END" | sed 's/[&/]/\\&/g')"
    sed "/$SED_BEGIN/,/$SED_END/d" "$IR_SH" > "${IR_SH}.new" 2>/dev/null || return 1
    mv -f "${IR_SH}.new" "$IR_SH" 2>/dev/null || { rm -f "${IR_SH}.new"; return 1; }
    chmod 755 "$IR_SH" 2>/dev/null
    return 0
}

do_install()
{
    echo ""
    echo "=== RK322X BOOT INSTALL ==="

    if ! is_root; then
        echo "[ERREUR] privileges root requis : su -c \"sh $0 INSTALL\""
        return 1
    fi

    TARGET="/data/scripts/boot.sh"
    SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    case "$SELF" in
        "$TARGET") ;;
        *)
            mkdir -p /data/scripts 2>/dev/null
            cp -f "$SELF" "$TARGET" 2>/dev/null \
                && chmod 755 "$TARGET" \
                && echo "[ OK ] runner copie -> $TARGET" \
                || { echo "[ERREUR] copie vers $TARGET impossible (deploy INSTALL d'abord ?)"; return 1; }
            ;;
    esac

    echo "[*] /system en ecriture..."
    if rw_system; then
        if write_rc_file; then
            echo "[ OK ] hook init : $RC_FILE"
            echo "       service '$RC_NAME' class late_start oneshot user root"
            ro_system
            echo ""
            echo "[ OK ] actif au PROCHAIN reboot (init lit *.rc au demarrage)"
            echo "       test immediat possible : boot TEST"
            echo "       retrait : boot REMOVE"
            return 0
        fi

        # mecanisme 2 : script init.d si le firmware les execute
        if detect_initd; then
            echo "[..] support init.d detecte, essai..."
            if write_initd; then
                echo "[ OK ] hook init.d : $INITD_FILE"
                ro_system
                echo ""
                echo "[ OK ] actif au PROCHAIN reboot (run-parts init.d)"
                return 0
            fi
            echo "[WARN] ecriture init.d impossible"
        else
            echo "[ -- ] init.d non supporte par ce firmware (pas de run-parts/sysinit)"
        fi

        echo "[WARN] $RC_DIR non accessible -> repli install-recovery.sh"
        ro_system
    else
        echo "[WARN] /system non inscriptible -> repli install-recovery.sh"
    fi

    if [ ! -f "$IR_SH" ]; then
        echo "# fallback rk322x tools" > "$IR_SH" 2>/dev/null \
            || { echo "[ERREUR] ni init.d ni install-recovery.sh possibles"; return 1; }
    fi
    if ir_install_block; then
        echo "[ OK ] bloc ajoute a $IR_SH (30s apres le boot)"
        echo "       retrait : boot REMOVE"
        return 0
    fi
    echo "[ERREUR] aucun mecanisme disponible sur ce firmware"
    return 1
}

do_remove()
{
    echo ""
    echo "=== RK322X BOOT REMOVE ==="
    if ! is_root; then
        echo "[ERREUR] privileges root requis : su -c \"sh $0 REMOVE\""
        return 1
    fi

    RC=0
    if [ -f "$RC_FILE" ]; then
        rw_system || true
        rm -f "$RC_FILE" 2>/dev/null && { echo "[ OK ] $RC_FILE supprime"; } \
            || { echo "[ ERREUR ] suppression $RC_FILE impossible"; RC=1; }
        ro_system
    else
        echo "[ -- ] pas de hook init ($RC_FILE absent)"
    fi

    if [ -f "$INITD_FILE" ]; then
        rw_system || true
        remove_initd && echo "[ OK ] $INITD_FILE supprime" \
                     || { echo "[ ERREUR ] suppression $INITD_FILE impossible"; RC=1; }
        ro_system
    else
        echo "[ -- ] pas de hook init.d"
    fi

    if ir_has_block; then
        rw_system || true
        if ir_remove_block; then
            echo "[ OK ] bloc retire de $IR_SH"
        else
            echo "[ ERREUR ] nettoyage $IR_SH impossible"
            RC=1
        fi
        ro_system
    else
        echo "[ -- ] rien dans $IR_SH"
    fi
    return "$RC"
}

last_run_log()
{
    for D in /mnt/media_rw/*/log/exec /data/local/tmp/rk322x_logs/exec; do
        F="$(ls -1d "$D"/boot_*.log 2>/dev/null | sort | tail -n 1)"
        [ -n "$F" ] && { printf '%s' "$F"; return 0; }
    done
    return 1
}

do_status()
{
    echo ""
    echo "=== RK322X BOOT STATUS ==="

    if [ -f "$RC_FILE" ]; then
        echo "  Hook init       : $RC_FILE"
        sed 's/^/                    /' "$RC_FILE"
    else
        echo "  Hook init       : absent"
    fi

    case "$(ir_has_block && echo oui || echo non)" in
        oui) echo "  Fallback        : bloc present dans $IR_SH" ;;
        *)   echo "  Fallback        : rien dans $IR_SH" ;;
    esac
    if [ -f "$INITD_FILE" ]; then
        echo "  Hook init.d     : $INITD_FILE"
    elif detect_initd; then
        echo "  init.d          : supporte par le firmware, non utilise"
    else
        echo "  init.d          : non supporte par ce firmware"
    fi

    echo ""
    echo "  Actions (device.conf) :"
    printf '    %-18s : %s\n' BOOT_MEM_TUNE     "$(config_get BOOT_MEM_TUNE 0)"
    printf '    %-18s : %s\n' BOOT_CUT_SERVICES "$(config_get BOOT_CUT_SERVICES 0)"
    printf '    %-18s : %s\n' BOOT_SET_NETWORK "$(config_get BOOT_SET_NETWORK 0)"
    printf '    %-18s : %s\n' BOOT_TIME_SYNC   "$(config_get BOOT_TIME_SYNC 0)"
    printf '    %-18s : %s\n' BOOT_EXPOSE      "$(config_get BOOT_EXPOSE 0)"
    printf '    %-18s : %s\n' BOOT_FRONT_CLOCK "$(config_get BOOT_FRONT_CLOCK 0)"
    printf '    %-18s : %s\n' BOOT_SD_LAST     "$(config_get BOOT_SD_LAST 0)"

    LAST="$(last_run_log)"
    echo ""
    if [ -n "$LAST" ]; then
        echo "  Dernier passage : $LAST"
        tail -n 6 "$LAST" 2>/dev/null | sed 's/^/      /'
    else
        echo "  Dernier passage : aucun (jamais lance depuis l'installation du hook)"
    fi
    echo ""
    return 0
}

usage()
{
    echo ""
    echo "Usage: boot <INSTALL|REMOVE|STATUS|TEST|HELP>"
    echo ""
    echo "  INSTALL   persiste les optimisations au boot (hook /system/etc/init/*.rc,"
    echo "            repli install-recovery.sh). /system remonte rw puis ro."
    echo "  REMOVE    retire proprement le(s) mecanisme(s)"
    echo "  STATUS    mecanisme actif, actions configurees, dernier passage"
    echo "  TEST      execute les actions maintenant (identique au lancement boot)"
    echo ""
    echo "Actions pilotees par device.conf : BOOT_MEM_TUNE, BOOT_CUT_SERVICES,"
    echo "BOOT_SET_NETWORK (route+DNS au boot), BOOT_TIME_SYNC (horloge AUTO),"
    echo "BOOT_EXPOSE, BOOT_FRONT_CLOCK, BOOT_SD_LAST (0|1),"
    echo "BOOT_WAIT_BOOT (secondes, defaut 120)."
    echo ""
    return 0
}

run_boot()
{
    case "$1" in
        ""|RUN|run)                 do_run ;;
        INSTALL|install)            do_install ;;
        REMOVE|remove)              do_remove ;;
        STATUS|status)              do_status ;;
        TEST|test)                  do_run ;;
        HELP|help|-h|--help)        usage ;;
        *)                          usage ;;
    esac
}

if [ -n "$1" ] && [ "$1" != "RUN" ] && [ "$1" != "run" ]; then
    run_boot "$@"
    exit $?
fi

if [ "$RUNLOG_LOADED" -eq 1 ] && runlog_start "$SCRIPT_ID"; then
    do_run >> "$RUNLOG_FILE" 2>&1
    RC=$?
    runlog_end "$RC"
    cat "$RUNLOG_FILE"
else
    do_run
    RC=$?
fi

exit "$RC"
