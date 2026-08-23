#!/system/bin/sh
# menu - dispatcher par sujet : un point d'entree pour piloter la box.
#
#   menu                    vue d'ensemble (sujets + etat rapide)
#   menu <sujet>            aide du sujet + etat detaille
#   menu <sujet> <action>   lance l'action
#
# Sujets :
#   install   deploy INSTALL/PKG/STATUS/VERSION/RESTORE
#   recette   validation bout-en-bout (P1..P7, RETOUR, MANIFEST)
#   optim     mem_tune, cut_services, disable_wireless
#   inspect   analyses completes ou par domaine
#   diag      check_state, net_diag, sys_diag, vitals, thermal
#   logs      SEND_LOGS, rotate_logs, run_state
#   serveur   pile web (expose/stop), ssh_server
#   cle       sync_usb, show_key

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

BASE="$(cd "$(dirname "$0")" && pwd)"
[ -d /data/scripts ] && BASE="/data/scripts"

run_tool()
{
    T="$1"; shift
    if [ -f "$BASE/$T" ]; then
        sh "$BASE/$T" "$@"
    else
        echo "[ERREUR] outil absent : $T (relancer : deploy INSTALL)"
        return 127
    fi
}

deploy_cmd()
{
    D=""
    [ -f "$BASE/deploy.sh" ] && D="$BASE/deploy.sh"
    if [ -z "$D" ]; then
        # lance depuis la cle sans installation locale : deploy.sh a la racine
        for d in /mnt/media_rw/*; do
            [ -f "$d/deploy.sh" ] && { D="$d/deploy.sh"; break; }
        done
    fi
    if [ -n "$D" ]; then
        sh "$D" "$@"
    else
        echo "[ERREUR] deploy.sh absent (ni local ni sur cle)"
        return 127
    fi
}

first_line()
{
    sed -n "$2p" "$1" 2>/dev/null
}

# ------------------------------------------------------------- etats rapides

st_install()
{
    V="$(first_line /data/scripts/VERSION 1)"
    printf '  %-10s %s\n' "install" "${V:-absente (deploy INSTALL)}"
}

st_recette()
{
    R=""
    for d in /mnt/media_rw/*; do
        [ -f "$d/log/recette_last.txt" ] || continue
        R="$(sed -n '2p' "$d/log/recette_last.txt" 2>/dev/null)"
        break
    done
    printf '  %-10s %s\n' "recette" "${R:-jamais lancee}"
}

st_optim()
{
    SW="$(cat /proc/sys/vm/swappiness 2>/dev/null)"
    ZS="$(cat /sys/block/zram0/disksize 2>/dev/null)"
    NBSWAP="$(sed -n '2,$p' /proc/swaps 2>/dev/null | grep -cv '^$')"
    ZNOTE=""
    case "$ZS" in
        ''|*[!0-9]*) ;;
        *) [ "$ZS" -gt 0 ] && ZNOTE=" (zram $((ZS / 1048576)) Mo)" ;;
    esac
    printf '  %-10s swappiness=%s  swaps actifs=%s%s\n' "memoire" "${SW:-?}" "${NBSWAP:-0}" "$ZNOTE"
}

st_serveur()
{
    ALIVE=0
    for P in /mnt/media_rw/*/server/*.pid; do
        [ -f "$P" ] || continue
        PID="$(cat "$P" 2>/dev/null)"
        kill -0 "$PID" 2>/dev/null && ALIVE=$((ALIVE+1))
    done
    printf '  %-10s %s serveur(s) actif(s)\n' "serveurs" "$ALIVE"
}

menu_overview()
{
    echo ""
    echo "=== RK322X MENU ==="
    echo "sujets : install recette optim inspect diag logs serveur cle"
    echo ""
    st_install
    st_recette
    st_optim
    st_serveur
    echo ""
    echo "detail : menu <sujet>"
    echo "lancement : menu <sujet> <action>"
    echo ""
}

# ------------------------------------------------------------- sujets

help_install()
{
    cat << 'EOF'
install - deploiement des outils
  status            etat du deploiement (deploy STATUS)
  version           version installee vs cle
  usb               installer depuis la cle (deploy INSTALL)
  pkg [fichier]     installer depuis un .dpk (racine cle ou chemin)
  restore           restaurer la derniere sauvegarde
EOF
}

do_install()
{
    case "$1" in
        ""|help|-h) help_install ;;
        status)     deploy_cmd STATUS ;;
        version)    deploy_cmd VERSION ;;
        usb)        deploy_cmd INSTALL ;;
        pkg)        deploy_cmd PKG "$2" ;;
        restore)    deploy_cmd RESTORE ;;
        *) echo "action inconnue : $1 (voir menu install)" ; return 1 ;;
    esac
}

help_recette()
{
    cat << 'EOF'
recette - validation bout-en-bout de la box
  tout              sequence complete P1..P7 + bilan + retour
  p1..p7            une phase seule (install/selftest/conf/mem/inspect/runstate/expose)
  retour            collecte des logs sur la cle
  manifest          snapshot certifie (phases completes requises)
  phases            dernier etat par phase (log/recette_phases.txt)
EOF
}

do_recette()
{
    A="$1"
    case "$A" in
        ""|help|-h) help_recette ;;
        phases)
            for d in /mnt/media_rw/*; do
                [ -f "$d/log/recette_phases.txt" ] || continue
                sort "$d/log/recette_phases.txt"
                return 0
            done
            echo "[ -- ] aucun etat de phase sur la cle"
            ;;
        tout)       run_tool recette.sh ;;
        p1|p2|p3|p4|p5|p6|p7)
                    run_tool recette.sh "$(echo "$A" | tr 'a-z' 'A-Z')" ;;
        retour)     run_tool recette.sh RETOUR ;;
        manifest)   run_tool recette.sh MANIFEST ;;
        *)          echo "action inconnue : $A (voir menu recette)" ; return 1 ;;
    esac
}

help_optim()
{
    cat << 'EOF'
optim - optimisation memoire / allegement
  mem               applique le profil memoire (mem_tune OPTIMIZE)
  mem-status        etat memoire (zram, swap disque, vm, lmk)
  mem-restore       valeurs d'origine (mem_tune RESTORE)
  cut               allegement services/paquets (cut_services CUT)
  cut-status        ce que cut_services couperait
  wireless-off      coupe wifi/bt (disable_wireless OFF)
  wireless-on       retablit wifi/bt (disable_wireless ON)
  wireless-status   etat radio
EOF
}

do_optim()
{
    case "$1" in
        ""|help|-h)     help_optim ;;
        mem)            run_tool mem_tune.sh OPTIMIZE ;;
        mem-status)     run_tool mem_tune.sh STATUS ;;
        mem-restore)    run_tool mem_tune.sh RESTORE ;;
        cut)            run_tool cut_services.sh CUT ;;
        cut-status)     run_tool cut_services.sh STATUS ;;
        wireless-off)   run_tool disable_wireless.sh OFF ;;
        wireless-on)    run_tool disable_wireless.sh ON ;;
        wireless-status) run_tool disable_wireless.sh STATUS ;;
        *)              echo "action inconnue : $1 (voir menu optim)" ; return 1 ;;
    esac
}

help_inspect()
{
    cat << 'EOF'
inspect - analyses de la box
  all               analyses coeur (inspect_all ; FORCE = tout
                    avec presentation raison/attentes + confirmation)
  device            puces/materiel (device_info)
  system            systeme (inspect_system)
  services          services init (inspect_services)
  display           ecran/hdmi (inspect_display)
  gui               interface android (inspect_gui STATUS)
  user              apps utilisateur (inspect_user)
  remote            telecommande IR (inspect_remote)
EOF
}

do_inspect()
{
    case "$1" in
        ""|help|-h) help_inspect ;;
        all)        run_tool inspect_all.sh ;;
        device)     run_tool device_info.sh ;;
        system)     run_tool inspect_system.sh ;;
        services)   run_tool inspect_services.sh ;;
        display)    run_tool inspect_display.sh ;;
        gui)        run_tool inspect_gui.sh STATUS ;;
        user)       run_tool inspect_user.sh ;;
        remote)     run_tool inspect_remote.sh ;;
        *)          echo "action inconnue : $1 (voir menu inspect)" ; return 1 ;;
    esac
}

help_diag()
{
    cat << 'EOF'
diag - diagnostics ponctuels
  state             etat cible reseau/wireless/hdmi (check_state)
  net               reseau (net_diag)
  sys               systeme complet (sys_diag)
  vitals            signes vitaux (vitals STATUS)
  thermal           temperatures (thermal STATUS)
  sd                carte SD (sd_inspect)
EOF
}

do_diag()
{
    case "$1" in
        ""|help|-h) help_diag ;;
        state)      run_tool check_state.sh ;;
        net)        run_tool net_diag.sh ;;
        sys)        run_tool sys_diag.sh ;;
        vitals)     run_tool vitals.sh STATUS ;;
        thermal)    run_tool thermal.sh STATUS ;;
        sd)         run_tool sd_inspect.sh ;;
        *)          echo "action inconnue : $1 (voir menu diag)" ; return 1 ;;
    esac
}

help_logs()
{
    cat << 'EOF'
logs - traces et historique
  send              collecte logcat/dmesg/getprop/... sur la cle
  rotate            purge/rotation des logs exec
  runstate          quels outils ont tourne, echecs (run_state)
EOF
}

do_logs()
{
    case "$1" in
        ""|help|-h) help_logs ;;
        send)       deploy_cmd SEND_LOGS ;;
        rotate)     run_tool rotate_logs.sh ;;
        runstate)   run_tool run_state.sh ;;
        *)          echo "action inconnue : $1 (voir menu logs)" ; return 1 ;;
    esac
}

help_serveur()
{
    cat << 'EOF'
serveur - pile web de la cle (8000 panneau / 8080 api / 8081 gui)
  expose            demarre toute la pile (httpd + gui + control + watcher)
  stop              arrete les serveurs
  ssh-status        dropbear (ssh_server STATUS)
EOF
}

do_serveur()
{
    case "$1" in
        ""|help|-h)  help_serveur ;;
        expose)      deploy_cmd EXPOSE ;;
        stop)        deploy_cmd STOP ;;
        ssh-status)
            SSH_SH="$BASE/server/ssh_server.sh"
            [ -f "$SSH_SH" ] || SSH_SH="/data/scripts/server/ssh_server.sh"
            if [ -f "$SSH_SH" ]; then
                sh "$SSH_SH" STATUS
            else
                echo "[ERREUR] ssh_server.sh non installe (deploy INSTALL)"
                return 1
            fi
            ;;
        *)           echo "action inconnue : $1 (voir menu serveur)" ; return 1 ;;
    esac
}

help_cle()
{
    cat << 'EOF'
cle - gestion de la cle USB
  sync              synchronise /data/scripts -> cle (sync_usb)
  show              paquets .dpk presents vs installe (show_key)
EOF
}

do_cle()
{
    case "$1" in
        ""|help|-h) help_cle ;;
        sync)       run_tool sync_usb.sh "$2" ;;
        show)       run_tool show_key.sh ;;
        *)          echo "action inconnue : $1 (voir menu cle)" ; return 1 ;;
    esac
}

help_pilotage()
{
    cat << 'EOF'
pilotage - vues d'ensemble et configuration
  manage            etat services/web/ports + actions (manage HELP)
  nreg              non-regression : 10 themes, un seul possible
                    (nreg 4 | nreg mem ; liste : nreg HELP)
  config            config interactive : page complete puis
                    modification par numero (config SET pour scripts)
EOF
}

do_pilotage()
{
    case "$1" in
        manage)     shift ; run_tool manage.sh "$@" ;;
        nreg)       shift ; run_tool nreg.sh "$@" ;;
        config)     shift ; run_tool config.sh "$@" ;;
        ""|help|-h) help_pilotage ;;
        *)          echo "action inconnue : $1 (voir menu pilotage)" ; return 1 ;;
    esac
}

# ------------------------------------------------------------- dispatch

main()
{
    case "$1" in
        ""|overview)         menu_overview ;;
        install)             shift ; do_install "$@" ;;
        recette)             shift ; do_recette "$@" ;;
        optim|optimize)      shift ; do_optim "$@" ;;
        inspect)             shift ; do_inspect "$@" ;;
        diag|diagnostic)     shift ; do_diag "$@" ;;
        logs|log)            shift ; do_logs "$@" ;;
        serveur|server|web)  shift ; do_serveur "$@" ;;
        cle|usb|key)         shift ; do_cle "$@" ;;
        manage|nreg|config|pilotage)
                             shift ; do_pilotage "$@" ;;
        help|-h|--help)
            sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
            ;;
        *)
            echo "Sujet inconnu : $1"
            echo "sujets : install recette optim inspect diag logs serveur cle pilotage"
            return 1
            ;;
    esac
}

if [ "$RUNLOG_LOADED" -eq 1 ] && runlog_start "$SCRIPT_ID"; then
    main "$@" >> "$RUNLOG_FILE" 2>&1
    RC=$?
    runlog_end "$RC"
    cat "$RUNLOG_FILE"
else
    main "$@"
    RC=$?
fi

exit "$RC"
