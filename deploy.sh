#!/system/bin/sh

# detection root robuste : id -u, sinon parsing du "id" brut (vieux
# toolbox sans option -u ; sous su : uid=0(root) gid=0(root))
is_root()
{
    case "$(id -u 2>/dev/null)" in
        0) return 0 ;;
    esac
    case "$(id 2>/dev/null)" in
        "uid=0("*) return 0 ;;
    esac
    return 1
}

# gardes partages (require_root, require_busybox)
for B in \
    "$(dirname "$0")/scripts" \
    "$(dirname "$0")" \
    "$(dirname "$0")/../scripts" \
    "$(pwd)/scripts" \
    "/data/scripts" ; do
    if [ -f "$B/core/config.sh" ]; then
        . "$B/core/config.sh"
        break
    fi
done

# filet de securite : config.sh introuvable (deploy.sh lance seul) ->
# definitions minimales pour ne jamais echouer en "require_root: not found"
if ! command -v require_root > /dev/null 2>&1; then
    require_root()
    {
        if ! is_root; then
            echo "[ERREUR] privileges root requis"
            echo "         relancer par exemple : su -c \"sh $0 $*\""
            return 1
        fi
        return 0
    }
    require_busybox()
    {
        command -v busybox > /dev/null 2>&1
    }
fi

SCRIPTS_DIR="/data/scripts"
BIN_DIR="/data/bin"
BACKUP_DIR="/data/backup"

INSTALL_LIST="amorce boot reboot remote_map front_digit launcher_toggle investigate stress_ram net_watch capture sync_usb disable_wireless inspect_usb inspect_proc inspect_dev media inspect_user inspect_system inspect_services inspect_display inspect_gui inspect_remote inspect_all device_info hdmi check_state conf_check help run_state recette selftest nreg config manage services hw_report aliases profile ramstep xrun preflight show_key field_mode rotate_logs thermal vitals mem_tune cut_services system_rw front_led motd net_diag sys_diag sd_inspect sd_boot set_network set_time chroot_env busi macro tips swap_watch menu"

# adb shell arrive en uid 2000 (shell) : elevation auto via su pour les
# actions qui touchent au systeme ou a la cle. L'aide reste accessible sans root.
case "$1" in
    ""|HELP|help|-h|--help|VERSION|version|STATUS|status)
        ;;
    *)
        if ! is_root && command -v su > /dev/null 2>&1; then
            echo "[*] uid non root : relance automatique via su..."
            exec su -c "sh $0 $*"
        fi
        ;;
esac

find_usb()
{
    for d in /mnt/media_rw/*; do
        [ -d "$d" ] || continue
        [ -f "$d/deploy.sh" ] || continue
        USB_DIR="$d"
        return 0
    done
    return 1
}

require_usb()
{
    if find_usb; then
        echo "Cle : $USB_DIR"
        return 0
    fi
    echo "[ERREUR] aucune cle USB contenant deploy.sh trouvee"
    return 1
}

link_bin()
{
    echo "[*] Commandes dans $BIN_DIR..."
    for NAME in deploy $INSTALL_LIST; do
        if [ -f "$SCRIPTS_DIR/$NAME.sh" ]; then
            TARGET="$SCRIPTS_DIR/$NAME.sh"
        elif [ -f "$SCRIPTS_DIR/core/$NAME.sh" ]; then
            TARGET="$SCRIPTS_DIR/core/$NAME.sh"
        else
            echo "    [ WARN ] $NAME introuvable"
            continue
        fi
        chmod 755 "$TARGET"
        ln -sf "$TARGET" "$BIN_DIR/$NAME"
        echo "    [ OK ] $NAME"
    done

    # purge des liens residuels : une commande dont la cible n'existe plus
    # (script retiré du depot, ancienne version) ne doit pas polluer /data/bin
    STALE=0
    for E in "$BIN_DIR"/*; do
        [ -e "$E" ] || [ -L "$E" ] || continue
        T_="$(readlink "$E" 2>/dev/null)"
        case "$T_" in
            ""|"$SCRIPTS_DIR"/*|"$SCRIPTS_DIR/core"/*) ;;
            *) continue ;;
        esac
        if [ ! -e "$T_" ]; then
            rm -f "$E" && { echo "    [ PURGE ] $(basename "$E") (cible absente : $T_)"; STALE=$((STALE+1)); }
        fi
    done
    [ "$STALE" -gt 0 ] || echo "    [ OK ] aucun lien residuel"
}

backup_existing(){
    if [ -d "$SCRIPTS_DIR" ] && [ -n "$(ls -A "$SCRIPTS_DIR" 2>/dev/null)" ]; then
        TS="$(date '+%Y%m%d-%H%M%S')"
        DEST="$BACKUP_DIR/scripts_$TS"
        mkdir -p "$DEST" 2>/dev/null || { echo "[ ERREUR ] backup impossible ($DEST)"; return 1; }
        if cp -rf "$SCRIPTS_DIR" "$DEST/"; then
            echo "[ OK ] sauvegarde -> $DEST"
            LAST_BACKUP="$DEST"
            return 0
        fi
        echo "[ ERREUR ] sauvegarde echouee"
        return 1
    fi
    echo "[ -- ] rien a sauvegarder"
    return 0
}

write_manifest()
{
    [ -n "$USB_DIR" ] && { [ -d "$USB_DIR" ] || USB_DIR=""; }
    if [ -z "$USB_DIR" ]; then
        find_usb || { echo "[ WARN ] manifest non ecrit (pas de cle)"; return 0; }
    fi

    MAN_DIR="$USB_DIR/manifests/current"
    HIS_DIR="$USB_DIR/manifests/history"

    mkdir -p "$MAN_DIR" "$HIS_DIR" 2>/dev/null

    for F in "$MAN_DIR"/install_*.manifest; do
        [ -f "$F" ] || continue
        mv "$F" "$HIS_DIR/" 2>/dev/null
    done

    TS="$(date '+%Y%m%d-%H%M%S')"
    MAN="$MAN_DIR/install_$TS.manifest"

    {
        echo "date    : $(date '+%Y-%m-%d %H:%M:%S')"
        echo "source  : $INSTALL_SRC_TYPE : $INSTALL_SRC_ID"
        echo "device  : $(getprop ro.product.device 2>/dev/null)"
        echo "uid     : $(id -u 2>/dev/null)"
        echo "list    : $INSTALL_LIST"
        echo "--- files ---"
        ls -1R "$SCRIPTS_DIR" 2>/dev/null
    } > "$MAN" 2>/dev/null

    if [ -f "$MAN" ]; then
        echo "[ OK ] manifest -> $MAN"
        return 0
    fi
    echo "[ WARN ] manifest non ecrit"
    return 0
}

# post-install : pose le hook de demarrage ET les aliases automatiquement.
# Non bloquant : si /system refuse l'ecriture, simples avertissements
# (boot INSTALL / aliases INSTALL resteront possibles manuellement).
post_install_boot()
{
    BOOT_SH="$SCRIPTS_DIR/boot.sh"
    [ -f "$BOOT_SH" ] || return 0

    echo ""
    echo "[5] Demarrage automatique (boot INSTALL)..."
    TMPB="/data/local/tmp/deploy_boot_$$"
    if sh "$BOOT_SH" INSTALL > "$TMPB" 2>&1; then
        grep -E '\[ OK \]' "$TMPB" | sed 's/^/    /'
        echo "    [ OK ] pile web + optimisations lanceront seules au prochain reboot"
    else
        echo "    [WARN] hook non pose (non bloquant) -> boot INSTALL manuel plus tard"
        grep -E 'ERREUR|WARN' "$TMPB" | tail -n 3 | sed 's/^/      /'
    fi
    rm -f "$TMPB" 2>/dev/null

    # raccourcis adb shell (/system/bin) : la cle d'une installation
    # complete sans manip supplementaire ; echec non bloquant
    ALIAS_SH="$SCRIPTS_DIR/aliases.sh"
    if [ -f "$ALIAS_SH" ]; then
        echo "[6] Raccourcis adb shell (aliases INSTALL)..."
        TMPA="/data/local/tmp/deploy_alias_$$"
        if sh "$ALIAS_SH" INSTALL > "$TMPA" 2>&1; then
            grep -E 'poses/mis a jour|collisions' "$TMPA" | sed 's/^/    /'
            echo "    [ OK ] help/manage/nreg/... disponibles depuis adb shell"
        else
            echo "    [WARN] aliases non poses (non bloquant) -> aliases INSTALL plus tard"
            grep -E 'ERREUR|WARN' "$TMPA" | tail -n 2 | sed 's/^/      /'
        fi
        rm -f "$TMPA" 2>/dev/null
    fi
    return 0
}

install_from()
{
    SRC="$1"
    INSTALL_SRC_TYPE="${2:-usb}"
    INSTALL_SRC_ID="${3:-inconnu}"

    echo ""
    echo "=== RK322X INSTALL ==="

    if ! require_root; then
        return 1
    fi

    if [ ! -f "$SRC/deploy.sh" ]; then
        echo "[ERREUR] source invalide (deploy.sh absent) : $SRC"
        return 1
    fi

    echo "[0] Source ($INSTALL_SRC_TYPE) : $SRC"

    echo "[1] Sauvegarde existant..."
    backup_existing || return 1

    mkdir -p "$SCRIPTS_DIR/core" "$SCRIPTS_DIR/config" "$SCRIPTS_DIR/server" "$BIN_DIR"

    echo "[2] Copie des scripts..."
    if cp -f "$SRC"/scripts/*.sh "$SCRIPTS_DIR/" 2>/dev/null; then
        echo "    [ OK ] $SCRIPTS_DIR"
    else
        echo "    [ ERREUR ] $SCRIPTS_DIR"
    fi
    if cp -f "$SRC"/scripts/core/*.sh "$SCRIPTS_DIR/core/" 2>/dev/null && cp -f "$SRC"/scripts/core/actions.tsv "$SCRIPTS_DIR/core/" 2>/dev/null; then
        echo "    [ OK ] $SCRIPTS_DIR/core"
    else
        echo "    [ ERREUR ] $SCRIPTS_DIR/core"
    fi
    # server/ installe aussi cote box : EXPOSE et selftest ne dependent
    # plus du contenu de la cle (serveurs web/gui/control/ssh/watcher).
    # Deux layouts acceptes : cle/server (depot/dpk) ou cle/scripts/server
    # (cle construite par sync_usb)
    NSRV=0
    SRV_SRC="$SRC/server"
    [ -d "$SRV_SRC" ] || SRV_SRC="$SRC/scripts/server"
    for F in "$SRV_SRC"/*.sh; do
        [ -f "$F" ] || continue
        cp -f "$F" "$SCRIPTS_DIR/server/" 2>/dev/null && NSRV=$((NSRV+1))
    done
    if [ "$NSRV" -gt 0 ]; then
        echo "    [ OK ] $SCRIPTS_DIR/server ($NSRV scripts)"
    else
        echo "    [ WARN ] server/ absent dans la source (EXPOSE degrade)"
    fi
    if cp -f "$SRC/config/device.conf" "$SCRIPTS_DIR/config/" 2>/dev/null; then
        echo "    [ OK ] $SCRIPTS_DIR/config/device.conf"
    else
        echo "    [ WARN ] device.conf absent dans la source"
    fi

    echo "[3] Copie de deploy.sh..."
    if cp -f "$SRC/deploy.sh" "$SCRIPTS_DIR/deploy.sh"; then
        echo "    [ OK ] $SCRIPTS_DIR/deploy.sh"
    else
        echo "    [ ERREUR ] $SCRIPTS_DIR/deploy.sh"
    fi

    echo "[3b] Panneau web + AMORCE + docs -> racine de la cle..."
    COPIED=0
    for F in "$SRC"/web/*.html "$SRC/AMORCE" "$SRC"/INSTALLER.sh \
             "$SRC"/README.md "$SRC"/TROUBLESHOOTING.md "$SRC"/ROADMAP.md; do
        [ -f "$F" ] || continue
        DEST="$USB_DIR/$(basename "$F")"
        if find_usb && cp -f "$F" "$DEST" 2>/dev/null; then
            echo "    [ OK ] $DEST"
            COPIED=1
        else
            echo "    [ WARN ] cle inaccessible, $(basename "$F") non copie"
        fi
    done
    # documentations detaillees -> docs/ sur la cle (servi par :8000/docs/)
    if find_usb; then
        mkdir -p "$USB_DIR/docs" 2>/dev/null
        for F in "$SRC"/docs/*.md; do
            [ -f "$F" ] || continue
            cp -f "$F" "$USB_DIR/docs/" 2>/dev/null && { echo "    [ OK ] docs/$(basename "$F")"; COPIED=1; }
        done
    fi
    [ "$COPIED" -eq 0 ] && echo "    [ -- ] rien a copier (source sans panneau web/AMORCE)"

    link_bin

    echo "[3c] Validation..."
    if verify_install; then
        VAL_NOTE="OK"
        VALID_RC=0
    else
        VAL_NOTE="ECHEC"
        VALID_RC=1
    fi

    echo "[4] Trace..."
    BUILD_ID_SRC="$(sed -n 's/^build_id *: *//p' "$SRC/BUILD-INFO.txt" 2>/dev/null | head -n 1 | tr -d '\r')"
    {
        echo "version : $(sed -n 's/^DEPLOY_VERSION=//p' "$SCRIPTS_DIR/config/device.conf" 2>/dev/null | tr -d '\r')"
        echo "build   : ${BUILD_ID_SRC:-inconnu}"
        echo "date    : $(date '+%Y-%m-%d %H:%M:%S')"
        echo "source  : $INSTALL_SRC_TYPE : $INSTALL_SRC_ID"
        echo "validation : $VAL_NOTE"
    } > "$SCRIPTS_DIR/VERSION"
    echo "    [ OK ] $SCRIPTS_DIR/VERSION"
    write_manifest

    if [ "$VALID_RC" != "0" ]; then
        echo "[ ERREUR ] installation incomplete : verifier ci-dessus (deploy STATUS)"
        return 1
    fi

    # hook init + aliases poses d'office : INSTALL complete sans manip RW
    # manuelle (echecs non bloquants, voir [5]/[6] ci-dessus)
    post_install_boot

    IP_HINT="$(sed -n 's/^IP=//p' "$SCRIPTS_DIR/config/device.conf" 2>/dev/null | head -n 1 | tr -d '\r')"
    EXPOSE_FLAG="$(sed -n 's/^BOOT_EXPOSE=//p' "$SCRIPTS_DIR/config/device.conf" | head -n 1)"
    echo ""
    echo "=== PROCHAINES ETAPES ==="
    echo "  [C1] config CHECK          valider la configuration"
    echo "  [R1] nreg                  non-regression (10 themes)"
    echo "  [S1] manage                etat global services / web / ports"
    if [ "$EXPOSE_FLAG" = "1" ]; then
        echo "  [W0] IHM deja lancee : http://${IP_HINT:-<ip-box>}:8000/"
    else
        echo "  [S2] demarrer la pile : deploy STOP ; deploy EXPOSE"
        echo "  [W0] puis : http://${IP_HINT:-<ip-box>}:8000/"
    fi
    echo "  [B1] reboot de controle    -> tout doit revenir SEUL (boot STATUS)"
    echo "  Procedure complete sur la cle : docs/STARTUP.md"
    echo ""
    echo "=== TERMINE ==="
    echo "Commandes disponibles : deploy INSTALL | PKG | NEWKEY | RESTORE | EXPOSE | STOP | SEND_LOGS | VERSION | STATUS | CLEAN | HELP"
}

do_install()
{
    require_usb || return 1

    # layout zip officiel : deploy.sh + .dpk a la racine, sans scripts/ ->
    # bascule automatique sur l'installation par paquet (sinon install
    # incomplete : scripts manquants + server/ vide)
    if ! ls "$USB_DIR"/scripts/*.sh > /dev/null 2>&1; then
        if ls "$USB_DIR"/*.dpk > /dev/null 2>&1; then
            echo "[*] scripts/ absent sur la cle -> installation via le .dpk"
            do_pkg ""
            return $?
        fi
        echo "[ERREUR] ni scripts/ ni .dpk sur la cle : rien a installer"
        return 1
    fi

    install_from "$USB_DIR" usb "$(basename "$USB_DIR")"
}

find_pkg()
{
    PKG_FILE=""

    if [ -n "$1" ]; then
        if [ -f "$1" ]; then
            PKG_FILE="$1"
            return 0
        fi
        echo "[ERREUR] paquet introuvable : $1"
        return 1
    fi

    require_usb || return 1

    # BUILD_ID (3e champ _) a largeur fixe : le tri lexical du nom complet
    # placerait v9 apres v13
    LATEST="$(ls -1 "$USB_DIR"/*.dpk 2>/dev/null | sort -t_ -k3 | tail -n 1)"
    if [ -n "$LATEST" ]; then
        PKG_FILE="$LATEST"
        return 0
    fi

    echo "[ERREUR] aucun .dpk a la racine de la cle"
    return 1
}

do_pkg()
{
    echo ""
    echo "=== RK322X INSTALL PAR PAQUET ==="

    if ! require_root; then
        return 1
    fi

    find_pkg "$1" || return 1
    echo "[0] Paquet : $PKG_FILE"

    TAR=""
    if tar -tzf "$PKG_FILE" > /dev/null 2>&1; then
        TAR="tar"
    elif busybox tar -tzf "$PKG_FILE" > /dev/null 2>&1; then
        TAR="busybox tar"
    else
        echo "[ERREUR] archive illisible (tar+gzip requis)"
        return 1
    fi
    echo "    [ OK ] extraction via : $TAR"

    STAGE="/data/local/tmp/dpk_$(date '+%Y%m%d-%H%M%S')"
    mkdir -p "$STAGE" || { echo "[ERREUR] staging impossible"; return 1; }

    if ! $TAR -xzf "$PKG_FILE" -C "$STAGE"; then
        echo "[ ERREUR ] extraction echouee"
        rm -rf "$STAGE"
        return 1
    fi

    if [ ! -f "$STAGE/deploy.sh" ]; then
        echo "[ERREUR] paquet invalide (deploy.sh absent apres extraction)"
        rm -rf "$STAGE"
        return 1
    fi

    install_from "$STAGE" pkg "$(basename "$PKG_FILE")"
    RC=$?

    rm -rf "$STAGE"
    return $RC
}

do_restore()
{
    echo ""
    echo "=== RK322X RESTORE ==="

    if ! require_root; then
        return 1
    fi

    LATEST="$(ls -1d "$BACKUP_DIR"/scripts_* 2>/dev/null | sort | tail -n 1)"
    if [ -z "$LATEST" ]; then
        echo "[ERREUR] aucune sauvegarde dans $BACKUP_DIR"
        return 1
    fi

    echo "[1] Restauration depuis $LATEST..."
    rm -rf "$SCRIPTS_DIR"
    if cp -rf "$LATEST/scripts" "$SCRIPTS_DIR"; then
        echo "    [ OK ] $SCRIPTS_DIR"
    else
        echo "    [ ERREUR ] restauration echouee"
        return 1
    fi

    link_bin

    echo ""
    echo "=== TERMINE ==="
}

do_expose()
{
    echo ""
    echo "=== RK322X EXPOSE ==="

    if ! require_busybox; then
        return 1
    fi

    # start_server : installation locale d'abord (fiable), cle en secours
    STARTER=""
    [ -f "$SCRIPTS_DIR/server/start_server.sh" ] && STARTER="$SCRIPTS_DIR/server/start_server.sh"
    if [ -z "$STARTER" ]; then
        require_usb || return 1
        if [ -f "$USB_DIR/server/start_server.sh" ]; then
            STARTER="$USB_DIR/server/start_server.sh"
        elif [ -f "$USB_DIR/scripts/server/start_server.sh" ]; then
            STARTER="$USB_DIR/scripts/server/start_server.sh"
        else
            echo "[ERREUR] start_server.sh introuvable (ni $SCRIPTS_DIR/server/ ni cle)"
            echo "         relancer : deploy INSTALL"
            return 1
        fi
    fi
    sh "$STARTER"
}

# port encore en ecoute ? netstat, sinon /proc/net/tcp (hexa, etat 0A=LISTEN)
port_still_up()
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

do_stop()
{
    echo ""
    echo "=== RK322X STOP SERVEURS ==="

    FOUND=0
    for P in /mnt/media_rw/*/server/*.pid; do
        [ -f "$P" ] || continue
        PID="$(cat "$P" 2>/dev/null)"
        if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
            if kill "$PID" 2>/dev/null; then
                echo "[ OK ] $(basename "$P") arrete (PID $PID)"
                FOUND=1
            else
                echo "[ ERREUR ] impossible d'arreter PID $PID ($(basename "$P"))"
            fi
        else
            echo "[ WARN ] PID invalide dans $(basename "$P")"
        fi
        rm -f "$P"
    done

    # filet : instances orphelines sans pidfile (cle debranchee entre deux,
    # pidfile perdu) -> scan des cmdlines dans /proc.
    # Les DETENTEURS DE PORT sont vises aussi : en mono-slot le listener
    # effectif est un processus "busybox nc -l -p 80xx" enfant du shell
    # serveur ; tuer le shell seul laisse le nc orphelin sur le bind et le
    # EXPOSE suivant echoue alors silencieusement (8180/8081 injoignables
    # persistants ; temoin manage : 8081 en ecoute sans aucun pidfile).
    for D in /proc/[0-9]*; do
        [ -r "$D/cmdline" ] || continue
        C="$(tr '\0' ' ' < "$D/cmdline" 2>/dev/null)"
        case "$C" in
            *control_server.sh*) N="control_server" ;;
            *gui_server.sh*)     N="gui_server" ;;
            *watch_usb.sh*)      N="watch_usb" ;;
            *"busybox nc"*)      N="nc (listener)" ;;
            *"httpd -f"*)        N="httpd (panneau)" ;;
            # superviseur multi-listeners du control : tuer la boucle sh
            # parente ne le touche PAS (temoin v20 : apres STOP le tcpsvd de
            # la session precedente tenait encore 8180 -> tous les binds du
            # control relance echouaient, verdict d'ecoute faux-positif car
            # il sondait le detenteur etranger)
            *tcpsvd*)
                case "$C" in
                    *" 8180 "*|*" 8180") N="tcpsvd (superviseur 8180)" ;;
                    *)                   continue ;;
                esac
                ;;
            *)                   continue ;;
        esac
        PID="${D#/proc/}"
        if kill "$PID" 2>/dev/null; then
            echo "[ OK ] $N orphelin arrete (PID $PID)"
            FOUND=1
        fi
    done

    # verdict de liberation : un port encore en ecoute apres balayage =
    # detenteur non gere, a signaler plutot qu'a masquer
    sleep 1
    HELD=""
    for PORT_ in 8000 8180 8081; do
        if port_still_up "$PORT_"; then HELD="$HELD $PORT_" ; fi
    done
    if [ -n "$HELD" ]; then
        echo "[ WARN ] port(s)$HELD encore en ecoute apres arret"
        echo "         detenteur non identifie : rebooter la box avant EXPOSE"
        echo "         (sinon le bind echouera silencieusement)"
    fi

    if [ "$FOUND" -eq 0 ] && [ -z "$HELD" ]; then
        echo "[ -- ] aucun serveur actif"
    fi
}

conf_version()
{
    sed -n 's/^DEPLOY_VERSION=//p' "$1" 2>/dev/null | head -n 1 | tr -d '\r'
}

verify_install()
{
    MISS_S=0; SYNTAX=0; MISS_L=0

    for NAME in $INSTALL_LIST deploy; do
        F=""
        [ -f "$SCRIPTS_DIR/$NAME.sh" ] && F="$SCRIPTS_DIR/$NAME.sh"
        [ -z "$F" ] && [ -f "$SCRIPTS_DIR/core/$NAME.sh" ] && F="$SCRIPTS_DIR/core/$NAME.sh"
        if [ -z "$F" ]; then
            echo "    [ KO ] script manquant : $NAME"
            MISS_S=$((MISS_S+1))
            continue
        fi
        if ! sh -n "$F" 2>/dev/null; then
            echo "    [ KO ] syntaxe : $(basename "$F") (copie tronquee ?)"
            SYNTAX=$((SYNTAX+1))
        fi
    done

    for NAME in $INSTALL_LIST deploy; do
        [ -e "$BIN_DIR/$NAME" ] || { echo "    [ KO ] lien absent : $BIN_DIR/$NAME"; MISS_L=$((MISS_L+1)); }
    done

    NB_SH="$(ls -1 "$SCRIPTS_DIR"/*.sh 2>/dev/null | grep -c .)"
    NB_CORE="$(ls -1 "$SCRIPTS_DIR/core"/*.sh 2>/dev/null | grep -c .)"
    NB_LK="$(ls -1 "$BIN_DIR" 2>/dev/null | grep -c .)"
    echo "    scripts : $NB_SH (+$NB_CORE core)   liens bin : $NB_LK"

    if [ "$((MISS_S + SYNTAX + MISS_L))" -eq 0 ]; then
        echo "    [ OK ] installation coherente ($((NB_SH + NB_CORE)) scripts, $NB_LK liens)"
        return 0
    fi
    echo "    [ ERREUR ] $MISS_S manquant(s), $SYNTAX syntaxe, $MISS_L lien(s)"
    return 1
}

trim_newest()
{
    # $1 rep  $2 motif  $3 keep  $4 label : supprime les plus anciens au-dela de KEEP
    DIR="$1"; PAT="$2"; KEEP="$3"; LABEL="$4"

    [ -d "$DIR" ] || return 0
    LIST="$(ls -1d "$DIR"/$PAT 2>/dev/null | sort)"
    TOT="$(printf '%s\n' "$LIST" | grep -c .)"
    [ -z "$TOT" ] && TOT=0

    OVER=$((TOT - KEEP))
    if [ "$OVER" -le 0 ]; then
        printf '  %-26s %s element(s) (limite %s)\n' "$LABEL" "$TOT" "$KEEP"
        return 0
    fi
    if [ "$DRY" = "1" ]; then
        printf '  %-26s supprimerait %s element(s)\n' "$LABEL" "$OVER"
    else
        printf '%s\n' "$LIST" | head -n "$OVER" | while read -r F; do
            rm -rf "$F" 2>/dev/null
        done
        printf '  %-26s %s supprime(s) (garde %s)\n' "$LABEL" "$OVER" "$KEEP"
    fi
    return 0
}

do_clean()
{
    DRY=0
    case "$1" in DRY|dry|-n) DRY=1 ;; esac

    if ! require_root; then
        return 1
    fi

    echo ""
    echo "=== RK322X CLEAN (assainissement)${DRY:+ -- SIMULATION} ==="

    trim_newest "$BACKUP_DIR" "scripts_*" 3 "backups install"

    if find_usb; then
        trim_newest "$USB_DIR/manifests/history" "install_*.manifest" 10 "manifests history"
        trim_newest "$USB_DIR/log/gui_shots" "*.png" 11 "gui_shots (latest inclus)"

        RL=""
        [ -f "$USB_DIR/scripts/rotate_logs.sh" ] && RL="$USB_DIR/scripts/rotate_logs.sh"
        [ -z "$RL" ] && [ -f "$SCRIPTS_DIR/rotate_logs.sh" ] && RL="$SCRIPTS_DIR/rotate_logs.sh"
        if [ -n "$RL" ]; then
            if [ "$DRY" = "1" ]; then
                echo "  rotation logs exec         (serait lancee)"
            else
                sh "$RL" > /dev/null 2>&1 && echo "  rotation logs exec         OK"
            fi
        fi
    else
        echo "  cle absente : nettoyage cote box uniquement"
    fi

    TMPD="/data/local/tmp"
    for D in "$TMPD"/dpk_* "$TMPD/rk322x_logs"; do
        [ -e "$D" ] || continue
        if [ "$DRY" = "1" ]; then
            echo "  staging/tmp                supprimerait $(basename "$D")"
        else
            rm -rf "$D" 2>/dev/null
            echo "  staging/tmp                $(basename "$D") supprime"
        fi
    done
    for P in "$TMPD"/.probe_gui_*.png "$TMPD"/*.pid; do
        [ -e "$P" ] || continue
        if [ "$DRY" = "1" ]; then
            echo "  residus tmp                supprimerait $(basename "$P")"
        else
            rm -f "$P" 2>/dev/null
            echo "  residus tmp                $(basename "$P") supprime"
        fi
    done

    trim_newest "/data/tombstones" "*" 5 "tombstones crash"

    echo ""
    echo "[ OK ] assainissement termine${DRY:+ (simulation : relancer sans DRY)}"
    return 0
}

do_version()
{
    echo ""
    echo "=== RK322X VERSIONS ==="

    echo ""
    echo "Script en cours : $0"

    INSTALLED=""
    [ -f "$SCRIPTS_DIR/config/device.conf" ] && INSTALLED="$(conf_version "$SCRIPTS_DIR/config/device.conf")"
    printf '  %-18s : %s\n' "Installee (/data)" "${INSTALLED:-absente}"

    if [ -f "$SCRIPTS_DIR/VERSION" ]; then
        sed 's/^/      /' "$SCRIPTS_DIR/VERSION"
    fi

    KEY_VER=""
    if find_usb && [ -f "$USB_DIR/config/device.conf" ]; then
        KEY_VER="$(conf_version "$USB_DIR/config/device.conf")"
        printf '  %-18s : %s (%s)\n' "Sur la cle" "${KEY_VER:-absente}" "$USB_DIR"
    else
        printf '  %-18s : %s\n' "Sur la cle" "aucune cle detectee"
    fi

    echo ""
    case "$INSTALLED" in
        "")
            echo "[ -- ] rien d'installe : lancer depuis la cle :"
            echo "       su -c \"sh /mnt/media_rw/<ID>/deploy.sh INSTALL\""
            ;;
        *)
            case "$KEY_VER" in
                "") echo "[ -- ] pas de cle : impossible de comparer" ;;
                "$INSTALLED")
                    echo "[ OK ] a jour (v$INSTALLED)"
                    ;;
                *)
                    case "$KEY_VER" in
                        ''|*[!0-9]*) CMP="" ;;
                        *) case "$INSTALLED" in
                               ''|*[!0-9]*) CMP="" ;;
                               *) if [ "$KEY_VER" -gt "$INSTALLED" ]; then CMP=">"; else CMP="<>"; fi ;;
                           esac ;;
                    esac
                    case "$CMP" in
                        ">")
                            echo "[WARN] cle v$KEY_VER plus recente que l'installee v$INSTALLED"
                            echo "       -> deploy INSTALL"
                            ;;
                        *)
                            echo "[WARN] installee v$INSTALLED != cle v$KEY_VER"
                            echo "       -> deploy INSTALL pour aligner (ou sync_usb depuis la box)"
                            ;;
                    esac
                    ;;
            esac
            ;;
    esac
    echo ""
    return 0
}

do_deploy_status()
{
    echo ""
    echo "=== RK322X DEPLOY STATUS ==="

    echo ""
    echo "--- Installation sur la box ---"
    if [ -f "$SCRIPTS_DIR/VERSION" ]; then
        sed 's/^/  /' "$SCRIPTS_DIR/VERSION"
    else
        echo "  [ -- ] aucune trace d'installation ($SCRIPTS_DIR/VERSION absent)"
    fi
    IV="$(conf_version "$SCRIPTS_DIR/config/device.conf")"
    printf '  %-12s : %s\n' "version box" "${IV:-absente}"

    echo ""
    echo "--- Outils attendus ---"
    PRESENT=0; MISS=0; MISSING=""
    for NAME in $INSTALL_LIST deploy; do
        if [ -f "$SCRIPTS_DIR/$NAME.sh" ] || [ -f "$SCRIPTS_DIR/core/$NAME.sh" ]; then
            PRESENT=$((PRESENT+1))
        else
            MISSING="$MISSING $NAME"
            MISS=$((MISS+1))
        fi
    done
    echo "  presents     : $PRESENT"
    echo "  manquants    : $MISS${MISSING:+ =>$MISSING}"
    LK="$(ls -1 "$BIN_DIR" 2>/dev/null | grep -c .)"
    echo "  liens bin    : $LK ($BIN_DIR)"

    echo ""
    echo "--- Sauvegardes / manifests ---"
    NBB="$(ls -1d "$BACKUP_DIR"/scripts_* 2>/dev/null | grep -c .)"
    LASTB="$(ls -1d "$BACKUP_DIR"/scripts_* 2>/dev/null | sort | tail -n 1)"
    echo "  backups      : $NBB (dernier : $(basename "${LASTB:-aucun}"))"

    if find_usb; then
        MAN="$(ls -1 "$USB_DIR/manifests/current"/install_*.manifest 2>/dev/null | sort | tail -n 1)"
        [ -n "$MAN" ] && echo "  manifest     : $(basename "$MAN")"
        NH="$(ls -1 "$USB_DIR/manifests/history" 2>/dev/null | grep -c .)"
        echo "  history      : $NH entree(s)"

        KV="$(conf_version "$USB_DIR/config/device.conf")"
        echo ""
        echo "--- Cle USB ---"
        echo "  chemin       : $USB_DIR"
        echo "  version cle  : ${KV:-absente}"
        if [ -n "$IV" ] && [ -n "$KV" ] && [ "$IV" != "$KV" ]; then
            echo "  verdict      : divergent -> deploy INSTALL"
        elif [ -z "$IV" ]; then
            echo "  verdict      : rien installe -> deploy INSTALL"
        else
            echo "  verdict      : a jour"
        fi

        ALIVE=0
        for P in "$USB_DIR"/server/*.pid; do
            [ -f "$P" ] || continue
            PID="$(cat "$P" 2>/dev/null)"
            kill -0 "$PID" 2>/dev/null && ALIVE=$((ALIVE+1))
        done
        echo "  serveurs actifs : $ALIVE pidfile(s)"
    else
        echo ""
        echo "--- Cle USB ---"
        echo "  absente (verdict limite a la box)"
    fi

    echo ""
    return 0
}

# ---------------------------------------------------------------
# NEWKEY - usine a cles : transforme une cle USB BRANCHEE sur la
# box en cle "exposition" prete a installer sur une box vierge.
#
#   deploy NEWKEY              analyse + selection interactive
#   deploy NEWKEY <chemin>     destination imposee (mode scripte)
#   NK_FORCE=1 deploy NEWKEY   passer outre le refus cle ACTIVE
#
# Depose : deploy.sh, INSTALLER.sh, panneau web (*.html), AMORCE,
# README/TROUBLESHOOTING/ROADMAP, docs/, dernier .dpk (+ .sha256).
# La cle ACTIVE (serveurs web et/ou swap en cours) est refusee :
# ecrire dessus couperait l'exposition en cours.
# ---------------------------------------------------------------

nk_keys()
{
    for d in /mnt/media_rw/*; do
        [ -d "$d" ] && printf '%s\n' "$d"
    done
}

nk_active_key()
{
    # cle ACTIVE = serveurs vivants (pidfiles), sinon swap monte dessus
    for F in /mnt/media_rw/*/server/*.pid; do
        [ -f "$F" ] || continue
        P_="$(cat "$F" 2>/dev/null)"
        if [ -n "$P_" ] && kill -0 "$P_" 2>/dev/null; then
            dirname "$(dirname "$F")"
            return 0
        fi
    done
    S_="$(grep '^/mnt/media_rw/' /proc/swaps 2>/dev/null | awk '{print $1}' | head -n 1)"
    [ -n "$S_" ] && { dirname "$S_"; return 0; }
    return 1
}

nk_latest_dpk()
{
    ls -1 "$1"/*.dpk 2>/dev/null | sort -t_ -k3 | tail -n 1
}

do_newkey()
{
    echo ""
    echo "=== RK322X NEWKEY - PREPARATION D'UNE CLE EXPOSITION ==="

    ALL_="$(nk_keys)"
    if [ -z "$ALL_" ]; then
        echo "[ERREUR] aucune cle USB branchee (/mnt/media_rw vide)"
        return 1
    fi

    ACT_="$(nk_active_key)"

    # ---- [1] analyse des candidates -------------------------------------
    echo ""
    echo "[1] Analyse des cles branchees :"
    N_=0
    for K in $ALL_; do
        N_=$((N_+1))
        FS_="$(grep " $K " /proc/mounts 2>/dev/null | head -n 1 | cut -d' ' -f3)"
        AV_="$(df -m "$K" 2>/dev/null | awk 'NR==2{print $4}')"
        DSC_=""
        [ -f "$K/deploy.sh" ]  && DSC_="${DSC_}deploy.sh "
        [ -f "$K/index.html" ] && DSC_="${DSC_}panneau "
        [ -d "$K/docs" ]       && DSC_="${DSC_}docs "
        [ -f "$K/swap.bin" ]   && DSC_="${DSC_}swap.bin "
        DP_="$(nk_latest_dpk "$K")"
        [ -n "$DP_" ] && DSC_="${DSC_}dpk:$(basename "$DP_" | cut -d_ -f3 | sed 's/\.dpk$//') "
        TAG_=""
        [ "$K" = "$ACT_" ] && TAG_="  *** ACTIVE (serveurs/swap) ***"
        printf '  [%d] %-26s %-8s libre %s Mo\n      contenu : %s%s\n' \
            "$N_" "$K" "${FS_:-?}" "${AV_:-?}" "${DSC_:-vide}" "$TAG_"
    done

    # ---- [2] selection + gardes -----------------------------------------
    DEST_="$1"
    INT_=0
    if [ -z "$DEST_" ]; then
        INT_=1
        if [ -r /dev/tty ]; then
            printf '\n[2] Cle destination [1-%d] (ENTREE = annuler) : ' "$N_"
            IFS= read -r SEL_ < /dev/tty || SEL_=""
        else
            echo ""
            echo "[ERREUR] pas de terminal interactif : preciser le chemin :"
            echo "         deploy NEWKEY /mnt/media_rw/<ID>"
            return 1
        fi
        case "$SEL_" in
            "") echo "annule (rien modifie)"; return 0 ;;
            *[!0-9]*) echo "[ERREUR] choix invalide : $SEL_"; return 1 ;;
        esac
        [ "$SEL_" -ge 1 ] && [ "$SEL_" -le "$N_" ] \
            || { echo "[ERREUR] choix hors plage : $SEL_"; return 1; }
        DEST_="$(printf '%s\n' "$ALL_" | sed -n "${SEL_}p")"
    fi

    OK_=0
    for K in $ALL_; do [ "$K" = "$DEST_" ] && OK_=1; done
    if [ "$OK_" != "1" ]; then
        echo "[ERREUR] '$DEST_' n'est pas une cle USB montee (/mnt/media_rw/*)"
        return 1
    fi

    if [ -n "$ACT_" ] && [ "$DEST_" = "$ACT_" ] && [ "$NK_FORCE" != "1" ]; then
        echo ""
        echo "[REFUS] $DEST_ est la cle ACTIVE (pile web et/ou swap en cours) :"
        echo "        ecrire dessus couperait l'exposition et le swap."
        echo "        Passer outre (deconseille) : NK_FORCE=1 deploy NEWKEY $DEST_"
        return 1
    fi
    [ -n "$ACT_" ] && [ "$DEST_" = "$ACT_" ] && \
        echo "[WARN] destination = cle ACTIVE (NK_FORCE) : interruption probable"

    # ---- [3] source : la cle portant le dpk le plus recent ---------------
    CAND_=""
    for K in $ALL_; do
        [ "$K" = "$DEST_" ] && continue
        for D_ in "$K"/*.dpk; do
            [ -f "$D_" ] || continue
            CAND_="${CAND_}${D_}
"
        done
    done
    PKG_="$(printf '%s' "$CAND_" | sort -t_ -k3 | tail -n 1)"
    SRC_="$(dirname "$PKG_")"
    if [ ! -f "$PKG_" ]; then
        DP_="$(nk_latest_dpk "$DEST_")"
        if [ -n "$DP_" ]; then
            SRC_="$DEST_"
            PKG_="$DP_"
            echo "[..] pas d'autre source : rafraichi depuis le dpk deja present"
        else
            echo ""
            echo "[ERREUR] aucun .dpk source disponible (autres cles et destination) :"
            echo "         une cle exposition exige le paquet ; brancher une cle existante"
            echo "         ou deposer le .dpk a la racine avant de relancer."
            return 1
        fi
    fi
    echo ""
    echo "[3] Source : $SRC_"
    echo "    Paquet : $(basename "$PKG_")"

    if [ "$INT_" = "1" ] && [ -r /dev/tty ]; then
        printf 'Deployer sur %s ? [o/N] : ' "$DEST_"
        IFS= read -r ANS_ < /dev/tty || ANS_=""
        case "$ANS_" in
            o|O|y|Y|oui|OUI) ;;
            *) echo "annule (rien modifie)"; return 0 ;;
        esac
    fi

    # ---- [4] deploiement --------------------------------------------------
    mkdir -p "$DEST_/docs" 2>/dev/null \
        || { echo "[ERREUR] ecriture impossible sur $DEST_ (cle en lecture seule ?)"; return 1; }

    COPIED_=0
    cp_one()
    {
        [ -f "$1" ] || return 0
        if cp -f "$1" "$2" 2>/dev/null; then
            COPIED_=$((COPIED_+1))
            return 0
        fi
        echo "    [ ERREUR ] copie : $3"
        return 1
    }

    echo ""
    echo "[4] Deploiement -> $DEST_ ..."
    DEPLOY_SRC="$SRC_/deploy.sh"
    [ -f "$DEPLOY_SRC" ] || DEPLOY_SRC="$SCRIPTS_DIR/deploy.sh"
    cp_one "$DEPLOY_SRC"          "$DEST_/deploy.sh"                 "deploy.sh"
    chmod 755 "$DEST_/deploy.sh" 2>/dev/null
    cp_one "$SRC_/INSTALLER.sh"   "$DEST_/INSTALLER.sh"              "INSTALLER.sh"
    chmod 755 "$DEST_/INSTALLER.sh" 2>/dev/null
    for H in "$SRC_"/*.html; do
        [ -f "$H" ] || continue
        cp_one "$H" "$DEST_/$(basename "$H")" "panneau ($(basename "$H"))"
    done
    for F in AMORCE README.md TROUBLESHOOTING.md ROADMAP.md BUILD-INFO.txt; do
        cp_one "$SRC_/$F" "$DEST_/$F" "$F"
    done
    for M in "$SRC_"/docs/*.md; do
        [ -f "$M" ] || continue
        cp_one "$M" "$DEST_/docs/$(basename "$M")" "docs/$(basename "$M")"
    done
    SHA_=""
    [ -f "${PKG_}.sha256" ] && SHA_="${PKG_}.sha256"
    cp_one "$PKG_" "$DEST_/$(basename "$PKG_")" "paquet $(basename "$PKG_")"
    [ -n "$SHA_" ] && cp_one "$SHA_" "$DEST_/$(basename "$SHA_")" "sha256"
    echo "    [ OK ] $COPIED_ fichier(s) copies"

    # production propre : UN SEUL dpk par cle exposition
    PURGED_=0
    for D_ in "$DEST_"/*.dpk "$DEST_"/*.dpk.sha256; do
        [ -f "$D_" ] || continue
        [ "$D_" = "$DEST_/$(basename "$PKG_")" ] && continue
        [ -n "$SHA_" ] && [ "$D_" = "$DEST_/$(basename "$SHA_")" ] && continue
        rm -f "$D_" && PURGED_=$((PURGED_+1))
    done
    [ "$PURGED_" -gt 0 ] && echo "    [ OK ] $PURGED_ ancien(s) paquet(s) purge(s) (un seul dpk garde)"

    # ---- [5] verification -------------------------------------------------
    echo ""
    echo "[5] Verification :"
    RC_=0
    sh -n "$DEST_/deploy.sh" 2>/dev/null \
        && echo "    [ OK ] deploy.sh (syntaxe)" \
        || { echo "    [ KO ] deploy.sh (syntaxe)"; RC_=1; }

    TARC_="tar"
    tar -tzf "$DEST_/$(basename "$PKG_")" > /dev/null 2>&1 || TARC_="busybox tar"
    $TARC_ -tzf "$DEST_/$(basename "$PKG_")" > /dev/null 2>&1 \
        && echo "    [ OK ] paquet lisible ($TARC_)" \
        || { echo "    [ KO ] paquet illisible"; RC_=1; }

    if [ -n "$SHA_" ]; then
        WANT_="$(cut -d' ' -f1 "$DEST_/$(basename "$SHA_")" 2>/dev/null | tr 'A-Z' 'a-z')"
        GOT_="$(sha256sum "$DEST_/$(basename "$PKG_")" 2>/dev/null \
               || busybox sha256sum "$DEST_/$(basename "$PKG_")" 2>/dev/null)"
        GOT_="$(printf '%s' "$GOT_" | cut -d' ' -f1 | tr 'A-Z' 'a-z')"
        if [ -n "$WANT_" ] && [ "$WANT_" = "$GOT_" ]; then
            echo "    [ OK ] sha256 conforme"
        else
            echo "    [ KO ] sha256 divergent"; RC_=1
        fi
    fi

    MISS_=0
    for F in deploy.sh INSTALLER.sh index.html AMORCE; do
        [ -f "$DEST_/$F" ] && continue
        echo "    [ KO ] manquant : $F"
        MISS_=$((MISS_+1))
    done
    [ "$MISS_" -eq 0 ] && echo "    [ OK ] fichiers essentiels presents"
    FREE_="$(df -m "$DEST_" 2>/dev/null | awk 'NR==2{print $4}')"
    echo "    espace restant : ${FREE_:-?} Mo"

    # ---- [6] exposition ----------------------------------------------------
    echo ""
    echo "[6] Exposition :"
    UP_=0
    netstat -tln 2>/dev/null | grep -q ":8000 " && UP_=1
    grep -qi ":1F40 .* 0A " /proc/net/tcp 2>/dev/null && UP_=1
    if [ "$UP_" = "1" ]; then
        echo "    [ -- ] pile web deja active (8000 sert la cle courante)"
    else
        if do_expose > /dev/null 2>&1; then
            echo "    [ OK ] pile web demarree (deploy EXPOSE)"
        else
            echo "    [WARN] expose en echec (relancer : deploy EXPOSE)"
        fi
    fi

    IP_HINT="$(sed -n 's/^IP=//p' "$SCRIPTS_DIR/config/device.conf" 2>/dev/null | head -n 1 | tr -d '\r')"
    echo ""
    if [ "$RC_" = "0" ]; then
        echo "=== CLE PRETE : $DEST_ ==="
    else
        echo "=== CLE INCOMPLETE (voir KO ci-dessus) : $DEST_ ==="
    fi
    echo "  IHM box             : http://${IP_HINT:-<ip-box>}:8000/"
    echo "  Sur une box vierge  : brancher la cle puis sh /mnt/media_rw/<ID>/INSTALLER.sh"
    echo "  swap.bin (512 Mo)   : cree automatiquement au premier mem_tune OPTIMIZE"
    echo ""
    return "$RC_"
}

case "$1" in

    INSTALL)
        do_install
        ;;

    PKG)
        do_pkg "$2"
        ;;

    NEWKEY|newkey)
        # le verdict de preparation doit rester consultable en scripte :
        # rc=1 si la cle n'est pas prete (refus ACTIVE, dpk absent, KO verif)
        do_newkey "$2"
        exit $?
        ;;

    RESTORE)
        do_restore
        ;;

    EXPOSE)
        do_expose
        ;;

    STOP)
        do_stop
        ;;

    VERSION|version)
        do_version
        ;;

    STATUS|status)
        do_deploy_status
        ;;

    CLEAN|clean)
        do_clean "$2"
        ;;

    TOKEN)
        # protection optionnelle de l'API 8180 / GUI 8081 par secret partage :
        # tant que server/token n'existe pas, ces ports sont ouverts au LAN.
        echo ""
        echo "=== RK322X TOKEN API ==="
        require_usb || exit 1
        TOKFILE="$USB_DIR/server/token"
        mkdir -p "$USB_DIR/server" 2>/dev/null
        case "$2" in
            ""|STATUS|status)
                if [ -f "$TOKFILE" ]; then
                    echo "protection : ACTIVEE (server/token present)"
                    echo "valeur     : masquee ($(wc -c < "$TOKFILE" | tr -dc '0-9') octets)"
                else
                    echo "protection : DESACTIVEE (API 8180 / GUI 8081 ouvertes au LAN)"
                fi
                echo ""
                echo "usage : deploy TOKEN ON | OFF | <valeur>"
                echo "  ON        token aleatoire genere et affiche"
                echo "  OFF       supprime la protection"
                echo "  <valeur>  pose ce token (alphanumeriques seuls)"
                ;;
            OFF)
                if [ -f "$TOKFILE" ]; then
                    rm -f "$TOKFILE" && echo "[ OK ] protection supprimee"
                else
                    echo "[ -- ] deja desactivee"
                fi
                echo "suivant : deploy STOP && deploy EXPOSE"
                ;;
            ON)
                VAL=""
                [ -c /dev/urandom ] && \
                    VAL="$(head -c 64 /dev/urandom 2>/dev/null | tr -cd 'a-zA-Z0-9' | cut -c1-16)"
                [ -z "$VAL" ] && VAL="RK$(date '+%d%H%M%S')"
                printf '%s' "$VAL" > "$TOKFILE" && \
                    echo "[ OK ] token genere : $VAL"
                echo "note    : le panneau web demandera cette valeur une fois par navigateur"
                echo "suivant : deploy STOP && deploy EXPOSE"
                ;;
            *)
                case "$2" in
                    *[!a-zA-Z0-9]*)
                        echo "[ERREUR] valeur invalide : alphanumeriques seuls (a-z A-Z 0-9)"
                        exit 1
                        ;;
                esac
                if printf '%s' "$2" > "$TOKFILE"; then
                    echo "[ OK ] token pose (${#2} caracteres)"
                    echo "note    : le panneau web demandera cette valeur une fois par navigateur"
                    echo "suivant : deploy STOP && deploy EXPOSE"
                else
                    echo "[ERREUR] ecriture impossible dans $TOKFILE"
                    exit 1
                fi
                ;;
        esac
        ;;

    SEND_LOGS)
        # auto-elevation : sans root, ps est aveugle (proc hidepid=2 : aucun
        # processus des serveurs visibles, temoin v21 : ps.txt sans httpd ni
        # nc alors que 8000/8081 ecoutaient) et certains /proc restent muets.
        # Re-exec unique via su, garde-fou anti-boucle par variable d'env.
        if [ "${RK_SEND_LOGS_ELEVATED:-}" != "1" ] && [ "$(id -u 2>/dev/null)" != "0" ] \
           && [ "$(id 2>/dev/null | cut -d: -f1)" != "uid=0" ] \
           && command -v su > /dev/null 2>&1; then
            echo "[*] uid non root : relance automatique via su (ps/logcat complets)"
            RK_SEND_LOGS_ELEVATED=1 exec su -c "RK_SEND_LOGS_ELEVATED=1 sh '$0' SEND_LOGS"
        fi

        TS="$(date '+%Y%m%d_%H%M%S')"

        echo ""
        echo "=== RK322X COLLECTE DES LOGS ==="
        require_usb || exit 1

        OUT="$USB_DIR/log/log_$TS"
        mkdir -p "$OUT"
        echo "[1] Destination : $OUT"
        echo "[2] Collecte..."
        echo ""

        collect()
        {
            NAME="$1"; shift
            N=$((N+1))
            printf '  [%d/%d] %-12s ' "$N" "$TOTAL" "$NAME"
            if "$@" > "$OUT/$NAME.txt" 2>&1; then
                SIZE="$(du -h "$OUT/$NAME.txt" 2>/dev/null | cut -f1)"
                echo "[OK] ($SIZE)"
            else
                echo "[ERREUR]"
            fi
        }

        N=0
        TOTAL=12
        collect logcat   logcat -d
        collect dmesg    dmesg
        collect getprop  getprop
        collect ip_link  ip link
        collect mount    mount
        collect ps       ps

        # [7] traces du demarrage PRECEDENT (indispensables apres un boot
        # bloque : le dmesg live est deja efface par le redemarrage)
        N=$((N+1))
        printf '  [%d/%d] %-12s ' "$N" "$TOTAL" "pstore"
        PST=0
        for F in /sys/fs/pstore/console-ramoops* /sys/fs/pstore/dmesg-ramoops* /proc/last_kmsg; do
            [ -f "$F" ] || continue
            cp -f "$F" "$OUT/pstore_$(basename "$F")" 2>/dev/null && PST=$((PST+1))
        done
        if [ "$PST" -gt 0 ]; then
            echo "[OK] ($PST fichier(s))"
        else
            echo "[ -- ] non expose par ce noyau"
        fi

        # [8] enumeration des peripheriques mmc/SD (carte vue ? mmcblk1 ?)
        N=$((N+1))
        printf '  [%d/%d] %-12s ' "$N" "$TOTAL" "mmc"
        { ls -l /dev/block/mmcblk* 2>/dev/null
          echo "--- cat /sys/class/mmc_host/*/device type (si present) ---"
          for M in /sys/class/mmc_host/mmc*/mmc*:*/type; do
              [ -f "$M" ] && echo "$M : $(cat "$M" 2>/dev/null)"
          done
        } > "$OUT/mmc_dev.txt" 2>&1
        grep -q . "$OUT/mmc_dev.txt" && echo "[OK]" || echo "[ERREUR]"

        # [9] logs des serveurs : traces portant les verdicts de bind
        # 8180/8081 (FIFO en ecoute / NON ouvert) et les requetes recues.
        # Pile installee : les serveurs lances depuis /data/scripts/server ont
        # pu ecrire dans /data/scripts/log (layout ancien) -> pour chaque
        # fichier on prend la copie LA PLUS RECENTE des deux sources, sinon
        # le diagnostic "port injoignable" reste aveugle sur ces box (temoin :
        # CONTROL STARTED trace, control_server.log absent de la cle).
        N=$((N+1))
        printf '  [%d/%d] %-12s ' "$N" "$TOTAL" "srv_logs"
        SRV_N=0
        for SL in http_server.log control_server.log gui_server.log watch.log; do
            SRC=""
            for CAND in "$USB_DIR/log/$SL" "/data/scripts/log/$SL"; do
                [ -f "$CAND" ] || continue
                if [ -z "$SRC" ] || [ "$CAND" -nt "$SRC" ]; then SRC="$CAND"; fi
            done
            [ -n "$SRC" ] || continue
            cp -f "$SRC" "$OUT/srv_$SL" 2>/dev/null && SRV_N=$((SRV_N+1))
        done
        if [ "$SRV_N" -gt 0 ]; then
            echo "[OK] ($SRV_N fichier(s))"
        else
            echo "[ -- ] aucun log serveur sur la cle"
        fi

        # [10] ports en ecoute au moment de la collecte (net_diag PORTS)
        ND=""
        for CAND in /data/scripts/net_diag.sh "$USB_DIR/scripts/inspect/net_diag.sh"; do
            [ -f "$CAND" ] && { ND="$CAND"; break; }
        done
        if [ -n "$ND" ]; then
            collect ports sh "$ND" PORTS
            # valeur impossible = net_diag perime (sans filtre 1-65535,
            # temoin v21 : "12884901988") -> annotation dans le bundle
            # (tout nombre de 6 chiffres + depasse forcement 65535)
            if tr -cs '0-9' '\n' < "$OUT/ports.txt" 2>/dev/null \
               | grep -q '^[0-9][0-9][0-9][0-9][0-9][0-9]'; then
                echo "" >> "$OUT/ports.txt"
                echo "!! valeur(s) > 65535 : net_diag installe PERIME - se fier a ports_raw.txt et reinstaller le kit (deploy PKG)" >> "$OUT/ports.txt"
                echo "         [WARN] ports : net_diag perime detecte (voir annotation)"
            fi
        else
            N=$((N+1))
            printf '  [%d/%d] %-12s ' "$N" "$TOTAL" "ports"
            echo "[ ERREUR ] net_diag introuvable"
        fi

        # [11] brut reseau : meme si net_diag restait muet (collecte degradee,
        # regression), les sources premieres restent exploitables hors ligne
        N=$((N+1))
        printf '  [%d/%d] %-12s ' "$N" "$TOTAL" "ports_raw"
        {
            echo '--- netstat -tln ---'
            netstat -tln 2>&1
            echo '--- /proc/net/tcp ---'
            cat /proc/net/tcp 2>&1
            echo '--- /proc/net/tcp6 ---'
            cat /proc/net/tcp6 2>&1
        } > "$OUT/ports_raw.txt" 2>&1
        grep -q . "$OUT/ports_raw.txt" && echo "[OK]" || echo "[ERREUR]"

        # [12] versions installee vs cle : une install partielle/perimee se
        # voit immédiatement dans le bundle (temoin v21 : net_diag sans le
        # filtre 1-65535 executé alors que le reste etait a jour)
        N=$((N+1))
        printf '  [%d/%d] %-12s ' "$N" "$TOTAL" "versions"
        {
            echo '--- installee (/data/scripts) ---'
            cat /data/scripts/VERSION 2>&1
            grep -h '^DEPLOY_VERSION=' /data/scripts/config/device.conf 2>&1
            echo ''
            echo '--- cle (config/device.conf) ---'
            grep -h '^DEPLOY_VERSION=' "$USB_DIR/config/device.conf" 2>&1
            echo ''
            echo '--- empreintes net_diag/control/gui (installees) ---'
            if command -v sha256sum > /dev/null 2>&1; then SUM="sha256sum"; else SUM="busybox sha256sum"; fi
            $SUM /data/scripts/net_diag.sh \
                 /data/scripts/server/control_server.sh \
                 /data/scripts/server/gui_server.sh 2>&1
        } > "$OUT/versions.txt" 2>&1
        grep -q . "$OUT/versions.txt" && echo "[OK]" || echo "[ERREUR]"

        echo ""
        echo "=== TERMINE ==="
        ls -1 "$OUT" | sed 's/^/  - /'
        echo ""
        echo "Logs disponibles dans : $OUT"
        ;;

    *)
        echo ""
        echo "RK322X DEPLOY"
        echo ""
        echo "Usage: deploy <commande>"
        echo ""
        echo "Commandes:"
        echo "  INSTALL      Installer les scripts de la cle (avec sauvegarde auto)"
        echo "  PKG [f]      Installer depuis un paquet .dpk (racine cle ou chemin)"
        echo "  NEWKEY [c]   Usine a cles : prepare une cle branchee pour exposition"
        echo "               (analyse -> validation -> deploiement -> expose)"
        echo "  RESTORE      Restaurer la derniere installation sauvegardee"
        echo "  EXPOSE       Exposer la cle (HTTP port 8000)"
        echo "  STOP         Arreter les serveurs"
        echo "  SEND_LOGS    Collecter les logs sur la cle"
        echo "  VERSION      Versions installee / cle (diagnostic mise a jour)"
        echo "  STATUS       Etat du deploiement : outils, liens, backups, cle"
        echo "  CLEAN [DRY]  Assainissement : backups/manifests/shots/staging"
        echo "  TOKEN        Protection API 8180/GUI 8081 (ON/OFF/<valeur>/STATUS)"
        echo ""
        if [ -f "/data/scripts/help.sh" ]; then
            echo "Aide complete des outils : help"
        elif [ -f "$USB_DIR/scripts/help.sh" ] || find_usb; then
            echo "Aide complete des outils : sh $USB_DIR/scripts/help.sh"
        fi
        echo ""
        ;;
esac

exit 0
