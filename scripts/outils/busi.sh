#!/system/bin/sh
# busi - busybox devoile : inventaire, verdicts et DEMONSTRATIONS vivantes
# de sa puissance sur la box. Un seul binaire statique remplace des
# dizaines d'outils absents d'Android stock (wget, httpd, nc, tar, crond,
# chroot...) - ce kit en depend partout (panneau, dpk, swap, replis).
#
# Usage:
#   busi                 inventaire express (version, applets, indice puissance)
#   busi INFO            idem, detail complet
#   busi LIST [motif]    tous les applets (ou filtre grep), tries
#   busi WHERE <applet>  autonome dans le PATH ? via busybox ? absent ?
#   busi CHECK           applets requis par le kit + applets "puissance"
#   busi POWERS          demos reelles : serveur HTTP une ligne, compression
#                        a la volee, calculs awk, plus gros fichiers...
#   busi RUN <applet> [args...]   lance l'applet via busybox meme sans symlink
#   busi WHO [racine]    qui fournit /system/bin : liens toolbox/toybox/
#                        busybox/mksh vs binaires autonomes (defaut /system)
#   busi HELP            cette aide (sans root)

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" "$(dirname "$0")/.." /data/scripts; do
    [ -f "$B/core/runlog.sh" ] && { . "$B/core/runlog.sh"; RUNLOG_LOADED=1; break; }
done

# librairie config : UNIQUEMENT core/config.sh
# (NE JAMAIS candidat "$(dirname)/config.sh" : c'est l'outil interactif !)
for B in "$(dirname "$0")/core" "$(dirname "$0")/../core" /data/scripts/core; do
    [ -f "$B/config.sh" ] && { . "$B/config.sh"; break; }
done

command -v config_get >/dev/null 2>&1 || config_get() { echo "$2"; }

have() { command -v "$1" >/dev/null 2>&1 ; }

ok_ko()  { printf '  [%s] %s\n' "$1" "$2" ; }
row()    { printf '  %-12s %s\n' "$1" "$2" ; }

# ------------------------------------------------------------------ detection

BB=""
find_busybox()
{
    C="$(config_get BUSYBOX_BIN "")"
    if [ -n "$C" ] && [ -x "$C" ]; then BB="$C" ; return 0 ; fi
    if have busybox; then BB="busybox" ; return 0 ; fi
    for P in /system/xbin/busybox /system/bin/busybox \
             /data/local/tmp/busybox /data/local/bin/busybox \
             /data/busybox /data/media/0/busybox; do
        [ -x "$P" ] && { BB="$P" ; return 0 ; }
    done
    return 1
}

APPLETS=""
applet_list()
{
    if [ -z "$APPLETS" ]; then
        APPLETS="$("$BB" --list 2>/dev/null)"
    fi
    printf '%s\n' "$APPLETS"
}

has_applet()
{
    applet_list | grep -qx "$1"
}

# applets qui font la difference sur cette box (remplacements concrets)
POWER_LIST="httpd nc wget telnetd tftp crond crontab chroot tar gzip gunzip \
xz bzip2 dd awk sed grep find sort watch top ps free netstat ip route \
sha256sum md5sum base64 vi less hexdump timeout nohup setsid flock swapon"

# applets reellement appeles par les outils du kit
KIT_LIST="nc dd wget tar mkfifo sed awk sort tr cut grep find mount umount \
chroot netstat df du free ps sha256sum gzip"

# ------------------------------------------------------------------ commandes

cmd_info()
{
    echo ""
    echo "=== BUSI - BUSYBOX EN VEILLE ==="
    if ! find_busybox; then
        ok_ko KO "busybox introuvable (PATH + emplacements standards)"
        echo ""
        echo "  Remede : poser un binaire busybox arm (statique) a la racine"
        echo "  de la cle ou en /data/local/tmp, puis relancer busi."
        echo "  Sans lui : pas de panneau HTTP, pas de dpk, pas de swap."
        echo ""
        echo "=== FIN BUSI ==="
        return 0
    fi
    row chemin "$(command -v "$BB" 2>/dev/null || echo "$BB")"
    row version "$("$BB" 2>&1 | head -n 1)"

    NA="$(applet_list | grep -c . )"
    case "$NA" in ''|0)
        row applets "[ -- ] --list indisponible sur ce build"
        echo ""
        echo "=== FIN BUSI ==="
        return 0 ;;
    esac
    row applets "$NA applets embarques"

    TOT=0 ; GOT=0 ; MISSP=""
    for A in $POWER_LIST; do
        TOT=$((TOT+1))
        if has_applet "$A"; then GOT=$((GOT+1)) ; else MISSP="$MISSP $A" ; fi
    done
    PCT=$((GOT * 100 / TOT))
    row "indice puissance" "$PCT% ($GOT/$TOT applets a fort effet presentes)"
    case "$PCT" in
        80|9[0-9]|100) ok_ko OK "un binaire = une distribution d'outils complete" ;;
        5[0-9]|6[0-9]|7[0-9]) ok_ko !! "couverture moyenne -> completer le binaire si besoin" ;;
        *) ok_ko KO "build minimal : beaucoup de puissances endormies$MISSP" ;;
    esac
    echo "  detail : busi CHECK (besoins kit) / busi POWERS (demos vivantes)"
    echo ""
    echo "=== FIN BUSI ==="
    return 0
}

cmd_list()
{
    if ! find_busybox; then
        echo "[ERREUR] busybox introuvable (voir busi INFO)" ; return 1
    fi
    MOTIF="$1"
    L="$(applet_list | sort)"
    if [ -n "$MOTIF" ]; then
        printf '%s\n' "$L" | grep -i -- "$MOTIF"
        return $?
    fi
    # colonnes lisibles meme sur ecran TV (3 x ~25 car.)
    printf '%s\n' "$L" | awk '{ a[NR]=$1 } END { for (i=1;i<=NR;i+=3) printf "%-14s %-14s %s\n", a[i], a[i+1], a[i+2] }'
    return 0
}

cmd_where()
{
    if [ -z "$1" ]; then
        echo "[ERREUR] usage : busi WHERE <applet>" ; return 1
    fi
    A="$1"
    if have "$A"; then
        ok_ko OK "$A : autonome -> $(command -v "$A")"
        find_busybox && has_applet "$A" && echo "         (doublon possible avec busybox : verifier la version)" 
        return 0
    fi
    if find_busybox && has_applet "$A"; then
        ok_ko OK "$A : via busybox -> \"$BB $A ...\" (pas de symlink necessaire)"
        return 0
    fi
    ok_ko KO "$A : absent (ni PATH ni applets busybox)"
    return 1
}

cmd_check()
{
    echo ""
    echo "=== BUSI CHECK - besoins reels du kit ==="
    if ! find_busybox; then
        ok_ko KO "busybox introuvable" ; return 1
    fi
    MINK="" ; NKIT=0
    for A in $KIT_LIST; do
        has_applet "$A" || MINK="$MINK $A"
        NKIT=$((NKIT+1))
    done
    if [ -z "$MINK" ]; then
        ok_ko OK "$NKIT/$NKIT applets utilises par les outils du kit : presents"
    else
        ok_ko KO "manquants pour le kit:$MINK"
        echo "         impact selon outil : voir docs/TOOLS.md + preflight"
    fi
    echo ""
    echo "  Puissances endormies (absentes ici, effets possibles) :"
    SHOWN=0
    for A in $POWER_LIST; do
        has_applet "$A" && continue
        SHOWN=$((SHOWN+1))
        [ "$SHOWN" -gt 8 ] && { echo "  ... (+autres, busi LIST pour tout voir)" ; break ; }
        case "$A" in
            httpd)  E="serveur web integre (panneau :8000)" ;;
            nc)     E="couteau suisse reseau (client/serveur TCP-UDP)" ;;
            wget)   E="telechargements HTTP (absent d'Android stock)" ;;
            telnetd) E="shell distant de repli (sans dropbear)" ;;
            crond)  E="planification type cron (ici : hook BOOT_*)" ;;
            chroot) E="environnements isoles (cf chroot_env)" ;;
            xz|bzip2) E="compression forte pour archives/logs" ;;
            vi)     E="edition de fichiers sur la box" ;;
            *)      E="" ;;
        esac
        [ -n "$E" ] && printf '    %-8s %s\n' "$A" "$E" || printf '    %s\n' "$A"
    done
    [ "$SHOWN" -eq 0 ] && ok_ko OK "aucune : tout est deja disponible"
    echo ""
    echo "=== FIN BUSI CHECK ==="
    return 0
}

# ------------------------------------------------------------------ demos POWERS

demo_httpd()
{
    echo ""
    echo "  [DEMO 1] Serveur HTTP complet en UNE ligne (celui du panneau :8000)..."
    PORT=8137
    if netstat -tln 2>/dev/null | grep -q ":$PORT "; then
        echo "           port $PORT occupe -> demo sautee"
        return 0
    fi
    DIR="/data/local/tmp/busi_demo_$$"
    mkdir -p "$DIR" 2>/dev/null || DIR="/tmp/busi_demo_$$"
    mkdir -p "$DIR" 2>/dev/null || return 0
    echo "busi demo $(date '+%H:%M:%S')" > "$DIR/index.html" 2>/dev/null
    HPID=""
    clean_httpd() { [ -n "$HPID" ] && kill "$HPID" 2>/dev/null ; rm -rf "$DIR" 2>/dev/null ; }
    trap 'clean_httpd' EXIT INT TERM
    "$BB" httpd -f -p "$PORT" -h "$DIR" >/dev/null 2>&1 &
    HPID=$!
    sleep 1
    PAGE="$("$BB" wget -q -T 2 -O - "http://127.0.0.1:$PORT/" 2>/dev/null)"
    kill "$HPID" 2>/dev/null ; wait "$HPID" 2>/dev/null ; HPID=""
    rm -rf "$DIR" ; trap - EXIT INT TERM
    if [ -n "$PAGE" ]; then
        ok_ko OK "\"$BB httpd\" sert des pages -> c'est exactement le mecanisme du panneau"
    else
        ok_ko !! "page non recue (busybox sans httpd/wget ?) - cf CHECK"
    fi
    return 0
}

demo_tar()
{
    echo ""
    echo "  [DEMO 2] Compression a la volee en streaming (mecanisme des .dpk)..."
    SRCD="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
    [ -d "$SRCD" ] || return 0
    FILES="$("$BB" find "$SRCD" -maxdepth 1 -type f -name '*.sh' 2>/dev/null | head -n 60)"
    [ -n "$FILES" ] || { echo "           rien a compresser ici -> demo sautee" ; return 0 ; }
    RAW=0
    for F_ in $FILES; do
        NB="$("$BB" wc -c < "$F_" 2>/dev/null | tr -d ' ')"
        case "$NB" in ''|*[!0-9]*) continue ;; esac
        RAW=$((RAW + NB))
    done
    case "$RAW" in 0) echo "           rien a compresser -> demo sautee" ; return 0 ;; esac
    # $FILES non quote : separation de mots voulue (chemins sans espaces)
    GZ="$("$BB" tar -cf - $FILES 2>/dev/null | "$BB" gzip 2>/dev/null | wc -c | tr -d ' ')"
    case "$GZ" in ''|*[!0-9]*|0) ok_ko !! "gzip indisponible sur ce build" ; return 0 ;; esac
    PCT=$(( (RAW - GZ) * 100 / RAW ))
    ok_ko OK "scripts du repertoire : $((RAW / 1024)) Ko -> $((GZ / 1024)) Ko gzip (-${PCT}%), zero fichier temporaire"
    return 0
}

demo_awk()
{
    echo ""
    echo "  [DEMO 3] Calcul memoire pur shell+awk (moteur de vitals)..."
    R="$("$BB" awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{if(t){printf "%d%% RAM libre (%d/%d Mo)", a*100/t, a/1024, t/1024}}' /proc/meminfo 2>/dev/null)"
    if [ -n "$R" ]; then ok_ko OK "$R"
    else ok_ko !! "/proc/meminfo illisible ici -> demo significative sur la box" ; fi
    return 0
}

demo_find()
{
    echo ""
    echo "  [DEMO 4] Recherche des plus gros scripts (audit stockage)..."
    TOP="$("$BB" find "$(dirname "$0")" -maxdepth 1 -name '*.sh' -type f 2>/dev/null | head -n 40 | "$BB" xargs du -k 2>/dev/null | sort -n -r | head -n 2)"
    if [ -n "$TOP" ]; then
        printf '%s\n' "$TOP" | while IFS= read -r L_; do echo "           $L_"; done
        ok_ko OK "find+xargs+du+sort chaines sans aucun binaire externe"
    else
        ok_ko !! "rien trouve (layout depot thematise ? lancer depuis la box)"
    fi
    return 0
}

cmd_powers()
{
    echo ""
    echo "=== BUSI POWERS - busybox en action ==="
    if ! find_busybox; then
        ok_ko KO "busybox introuvable -> aucune demo possible (voir INFO)" ; return 1
    fi

    echo ""
    echo "  Ce que UN binaire remplace sur cette box :"
    cat << 'EOF'
    httpd    panneau web :8000 (deploy EXPOSE)      nc       diagnostic/API mono-slot
    wget     telechargements (absent Android)       tar/gzip sauvegardes + paquets .dpk
    dd       fabrication swap.bin (mem_tune)        chroot   mini-conteneurs (chroot_env)
    awk/sed  moteur logs/vitals/nreg                crond    planification (via BOOT_*)
    telnetd  repli shell distant                    watch/top monitoring continu
EOF

    demo_httpd
    demo_tar
    demo_awk
    demo_find

    echo ""
    echo "  aide-memoire complet : docs/BEST-COMMANDES.md (depot)"
    echo ""
    echo "=== FIN BUSI POWERS ==="
    return 0
}

cmd_run()
{
    A="$1"
    if [ -z "$A" ]; then
        echo "[ERREUR] usage : busi RUN <applet> [args...]" ; return 1
    fi
    shift
    if ! find_busybox; then
        echo "[ERREUR] busybox introuvable (voir busi INFO)" ; return 1
    fi
    "$BB" "$A" "$@"
}

cmd_who()
{
    ROOT="${1:-/system}"
    echo ""
    echo "=== BUSI WHO - qui fournit les commandes de $ROOT/bin ==="
    if [ ! -d "$ROOT/bin" ] && [ ! -d "$ROOT/xbin" ]; then
        ok_ko !! "$ROOT/bin absent (a lancer sur la box) - rien inventorie"
        return 0
    fi

    command -v readlink >/dev/null 2>&1 || readlink() { ls -ld "$1" 2>/dev/null | sed -n 's/.*-> //p' ; }

    TBT="" ; TYT="" ; BBL="" ; MKT="" ; OTH="" ; STA=""
    NTB=0 ; NTY=0 ; NBB=0 ; NMK=0 ; NOTH=0 ; NSTA=0
    scan_dir()
    {
        D="$1"
        [ -d "$D" ] || return 0
        for F in "$D"/*; do
            [ -e "$F" ] || continue
            BASE="$(basename "$F")"
            if [ -L "$F" ]; then
                case "$(readlink "$F" 2>/dev/null)" in
                    *toolbox) TBT="$TBT $BASE" ; NTB=$((NTB+1)) ;;
                    *toybox)  TYT="$TYT $BASE" ; NTY=$((NTY+1)) ;;
                    *busybox) BBL="$BBL $BASE" ; NBB=$((NBB+1)) ;;
                    *mksh)    MKT="$MKT $BASE" ; NMK=$((NMK+1)) ;;
                    *)        OTH="$OTH $BASE" ; NOTH=$((NOTH+1)) ;;
                esac
            else
                STA="$STA $BASE" ; NSTA=$((NSTA+1))
            fi
        done
    }
    scan_dir "$ROOT/bin"
    scan_dir "$ROOT/xbin"

    row "liens -> toolbox" "$NTB applet(s)"
    row "liens -> toybox" "$NTY applet(s)"
    row "liens -> busybox" "$NBB applet(s)"
    row "liens -> mksh" "$NMK lien(s)"
    row "autres liens" "$NOTH (logd, surfaceflinger, ...)"
    row binaires_autonomes "$NSTA"

    show_group()
    {
        LBL="$1" ; LST="$2" ; NTOT="$3"
        case "$(printf '%s' "$LST" | tr -d ' ')" in "") return 0 ;; esac
        echo ""
        echo "  $LBL :"
        NL="$(for W_ in $LST; do printf '%s\n' "$W_" ; done | sort)"
        printf '%s\n' "$NL" | awk 'NR<=40 { a[NR]=$1 } END { lim=(NR>40)?40:NR ; for (i=1;i<=lim;i+=5) printf "    %-10s %-10s %-10s %-10s %s\n", a[i], a[i+1], a[i+2], a[i+3], a[i+4] }'
        [ "$NTOT" -gt 40 ] && echo "    ... (+$((NTOT-40)) autres)"
        return 0
    }
    show_group "toolbox" "$TBT" "$NTB"
    show_group "toybox" "$TYT" "$NTY"
    show_group "busybox" "$BBL" "$NBB"

    echo ""
    if [ "$NTB" -gt 0 ]; then
        CRIT=""
        for C_ in getprop setprop start stop log; do
            case " $TBT " in *" $C_"*) CRIT="$CRIT $C_" ;; esac
        done
        [ -n "$CRIT" ] && DETAIL=" (sert aussi:$CRIT)" || DETAIL=""
        ok_ko OK "toolbox conserve - decision actee (gain nul a retirer)$DETAIL"
    fi
    ok_ko OK "sh -> mksh : socle de tous les scripts du kit, intouchable"
    echo ""
    echo "  Rappel : liens et binaires statiques = 0 RAM tant qu'inactifs."
    echo "  Les leviers utiles coupent du RESIDENT : cut_services / disable_wireless."
    echo ""
    echo "=== FIN BUSI WHO ==="
    return 0
}

usage()
{
    sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
}

main()
{
    case "$1" in
        ""|INFO|info)     cmd_info ;;
        LIST|list)        shift ; cmd_list "$@" ;;
        WHERE|where)      shift ; cmd_where "$@" ;;
        CHECK|check)      cmd_check ;;
        POWERS|powers)    cmd_powers ;;
        RUN|run)          shift ; cmd_run "$@" ;;
        WHO|who)          shift ; cmd_who "$@" ;;
        HELP|-h|--help)   usage ;;
        *)                echo "option inconnue : $1 (voir busi HELP)" ; return 1 ;;
    esac
}

if [ "$RUNLOG_LOADED" -eq 1 ] && runlog_start "$SCRIPT_ID"; then
    main "$@" >> "$RUNLOG_FILE" 2>&1 ; RC=$?
    runlog_end "$RC" ; cat "$RUNLOG_FILE"
else
    main "$@" ; RC=$?
fi
exit "$RC"
