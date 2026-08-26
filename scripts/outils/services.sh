#!/system/bin/sh
# services - active ou arrete D'UN COUP tous les services du kit.
#
# Rejoue la partie RUNTIME du boot sans rebooter (equivalent des flags
# BOOT_MEM_TUNE / BOOT_SWAP_WATCH / BOOT_EXPOSE / BOOT_FRONT_CLOCK + ssh) :
#
#   services              demarre tout : memoire/swap, gardien swap_watch,
#                         pile web 8000/8180/8081 + watcher USB, ssh 2222,
#                         horloge frontale
#   services UP           idem
#   services STOP         arrete tout (avec balayage des orphelins nc/httpd)
#   services STATUS       etat synthetique par service (lecture seule)
#   services HELP         cette aide
#
# UP/STOP demandent root : relance automatique via su depuis adb shell.
# Chaque etape affiche le verdict du outil sous-jacent puis une synthese
# finale sonde les ports/processus reels (un pid vivant ne prouve pas un bind).

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" "$(dirname "$0")/.." /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

BASE="$(cd "$(dirname "$0")" && pwd)"
[ -d "$BASE/scripts" ] && BASE="$BASE/scripts"

command -v is_root >/dev/null 2>&1 || is_root() \
    { case "$(id -u 2>/dev/null)" in 0) return 0 ;; esac; case "$(id 2>/dev/null)" in "uid=0("*) return 0 ;; esac; return 1; }

# UP/STOP touchent au swap, aux settings et aux ports : root requis
case "$1" in
    ""|UP|up|STOP|stop)
        if ! is_root && command -v su > /dev/null 2>&1; then
            echo "[*] uid non root : relance automatique via su..."
            exec su -c "sh $(cd "$(dirname "$0")" && pwd)/$(basename "$0") $*"
        fi
        ;;
esac

# resolution d'un outil : installe plat d'abord, puis layout depot thematise,
# puis cle/server (memes regles que start_server.sh)
resolve()
{
    F_="$1"
    for C in "$BASE/$F_" "/data/scripts/$F_" \
             "$BASE/optim/$F_" "$BASE/boot/$F_" "$BASE/frontal/$F_" \
             "$BASE/core/$F_" \
             "$BASE/server/$F_" "/data/scripts/server/$F_"; do
        [ -f "$C" ] && { printf '%s' "$C"; return 0; }
    done
    return 1
}

# port en ecoute ? netstat, sinon /proc/net/tcp (hexa, etat 0A=LISTEN)
port_up()
{
    P_="$1"
    if command -v netstat > /dev/null 2>&1; then
        netstat -tln 2>/dev/null | grep -q ":$P_ " && return 0
    fi
    PH_="$(printf '%04X' "$P_" 2>/dev/null)"
    [ -n "$PH_" ] || return 1
    grep -qi ":$PH_ .* 0A " /proc/net/tcp  2>/dev/null && return 0
    grep -qi ":$PH_ .* 0A " /proc/net/tcp6 2>/dev/null && return 0
    return 1
}

# processus vivant dont la cmdline contient le motif $1 ?
proc_has()
{
    for D in /proc/[0-9]*; do
        [ -r "$D/cmdline" ] || continue
        C="$(tr '\0' ' ' < "$D/cmdline" 2>/dev/null)"
        case "$C" in
            *"$1"*) [ "$D" != "/proc/$$" ] && return 0 ;;
        esac
    done
    return 1
}

step()
{
    STEP_N=$((STEP_N+1))
    echo ""
    printf '=== [%d/%d] %s ===\n' "$STEP_N" "$STEP_TOTAL" "$1"
}

# lance <outil.sh> <args...> : sortie montree, verdict par rc
run_quiet()
{
    T_="$1" ; shift
    if [ -z "$T_" ]; then
        echo "[KO] outil introuvable sur cette box/cle"
        return 1
    fi
    OUT_="$(sh "$T_" "$@" 2>&1)"
    RC_=$?
    printf '%s\n' "$OUT_"
    return "$RC_"
}

do_up()
{
    STEP_N=0 ; STEP_TOTAL=5

    step "memoire / swap (mem_tune OPTIMIZE)"
    M_="$(resolve mem_tune.sh)"
    run_quiet "$M_" OPTIMIZE
    RC_M=$?

    step "gardien memoire (swap_watch START)"
    W_="$(resolve swap_watch.sh)"
    run_quiet "$W_" START
    RC_W=$?

    step "pile web (deploy EXPOSE : 8000/8180/8081 + watcher USB)"
    D_="$(resolve deploy.sh)"
    run_quiet "$D_" EXPOSE
    RC_D=$?

    step "serveur ssh (dropbear 2222)"
    S_="$(resolve ssh_server.sh)"
    run_quiet "$S_" START
    RC_S=$?

    step "horloge frontale (front_digit CLOCK)"
    F_="$(resolve front_digit.sh)"
    if [ -n "$F_" ]; then
        # meme comportement que le boot : CLOCK borne a 90 s si timeout dispo
        if command -v timeout > /dev/null 2>&1; then
            timeout 90 sh "$F_" CLOCK > /dev/null 2>&1
        else
            sh "$F_" CLOCK > /dev/null 2>&1
        fi
        RC_F=$?
        [ "$RC_F" -eq 0 ] && echo "[OK] horloge frontale jouee" \
                          || echo "[KO] front_digit CLOCK rc=$RC_F (PROBE a faire une fois ?)"
    else
        echo "[ -- ] front_digit.sh introuvable (optionnel)"
        RC_F=0
    fi

    echo ""
    echo "=== SYNTHESE SERVICES ==="
    UP_=0
    for P_ in 8000 8180 8081; do
        port_up "$P_" && { echo "  [OK] port $P_ en ecoute" ; UP_=$((UP_+1)) ; } \
                      || echo "  [KO] port $P_ absent"
    done
    proc_has "swap_watch.sh"  && echo "  [OK] gardien swap_watch resident" || echo "  [--] gardien swap_watch absent"
    port_up 2222              && echo "  [OK] ssh dropbear (2222)"            || echo "  [--] ssh inactif"
    proc_has "front_digit.sh" && echo "  [OK] front_digit actif"                || echo "  [--] front_digit inactif"
    [ "$RC_M" -eq 0 ] && echo "  [OK] profil memoire applique" || echo "  [KO] mem_tune rc=$RC_M"

    [ "$UP_" -eq 3 ] && [ "$RC_M" -eq 0 ]; return $?
}

do_stop()
{
    STEP_N=0 ; STEP_TOTAL=4

    step "pile web (deploy STOP, orphelins nc/httpd inclus)"
    D_="$(resolve deploy.sh)"
    run_quiet "$D_" STOP
    RC_D=$?

    step "gardien memoire (swap_watch STOP)"
    W_="$(resolve swap_watch.sh)"
    run_quiet "$W_" STOP
    RC_W=$?

    step "serveur ssh (dropbear)"
    S_="$(resolve ssh_server.sh)"
    run_quiet "$S_" STOP
    RC_S=$?

    step "afficheur frontal (front_digit STOP)"
    F_="$(resolve front_digit.sh)"
    [ -n "$F_" ] && run_quiet "$F_" STOP || echo "[ -- ] front_digit.sh introuvable (optionnel)"

    echo ""
    echo "=== SYNTHESE SERVICES ==="
    HELD=0
    for P_ in 8000 8180 8081 2222; do
        if port_up "$P_"; then
            echo "  [WARN] port $P_ encore en ecoute"
            HELD=$((HELD+1))
        fi
    done
    [ "$HELD" -eq 0 ] && echo "  [OK] plus aucun port kit en ecoute"
    [ "$RC_D" -eq 0 ] && [ "$HELD" -eq 0 ]; return $?
}

do_status()
{
    echo "=== SERVICES STATUS ==="

    WEB=0
    for P_ in 8000 8180 8081; do
        port_up "$P_" && WEB=$((WEB+1))
    done
    case "$WEB" in
        3) echo "  [OK] pile web     : 8000/8180/8081 en ecoute" ;;
        0) echo "  [KO] pile web     : arretee (services UP pour demarrer)" ;;
        *) echo "  [WARN] pile web   : $WEB/3 ports seulement" ;;
    esac

    if proc_has "swap_watch.sh"; then
        echo "  [OK] gardien swap : resident"
    else
        echo "  [--] gardien swap : absent (swap_watch START)"
    fi

    SW_="$(sed -n '2,$p' /proc/swaps 2>/dev/null | grep -c .)"
    case "${SW_:-0}" in
        0) echo "  [--] swap actif   : aucun" ;;
        *) sed -n '2,$p' /proc/swaps 2>/dev/null | while IFS=' ' read -r DEV TYPE SZ _; do
               echo "  [OK] swap actif   : $DEV ($SZ Ko)"
           done ;;
    esac

    port_up 2222 && echo "  [OK] ssh          : dropbear (2222)" \
                 || echo "  [--] ssh          : inactif (ssh-start)"

    if proc_has "front_digit.sh"; then
        echo "  [OK] front digit  : resident"
    else
        echo "  [--] front digit  : inactif (BOOT_FRONT_CLOCK ou manual CLOCK)"
    fi
    return 0
}

usage()
{
    echo ""
    echo "Usage: services <UP|STOP|STATUS|HELP>"
    echo ""
    echo "  UP       tout demarrer : memoire/swap, gardien, pile web,"
    echo "           ssh, horloge frontale (defaut sans argument)"
    echo "  STOP     tout arreter (orphelins nc/httpd balayes)"
    echo "  STATUS   etat synthetique par service (lecture seule)"
    echo ""
    echo "Equivalent runtime des flags BOOT_* sans rebooter."
    echo ""
}

main()
{
    case "${1:-}" in
        ""|UP|up)         do_up ;;
        STOP|stop)        do_stop ;;
        STATUS|status)    do_status ;;
        HELP|help|-h|--help) usage ;;
        *)
            echo "argument inconnu : $1 (voir : services HELP)"
            return 1
            ;;
    esac
}

if [ "$RUNLOG_LOADED" -eq 1 ] && runlog_start "$SCRIPT_ID"; then
    main "$@" >> "$RUNLOG_FILE" 2>&1 ; RC=$?
    runlog_end "$RC" ; cat "$RUNLOG_FILE"
else
    main "$@" ; RC=$?
fi

exit "$RC"
