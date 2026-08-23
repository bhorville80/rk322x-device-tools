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

INSTALL_LIST="amorce boot reboot remote_map front_digit investigate stress_ram net_watch capture sync_usb disable_wireless media inspect_user inspect_system inspect_services inspect_display inspect_gui inspect_remote inspect_all device_info hdmi check_state conf_check help run_state recette selftest nreg config manage hw_report aliases profile ramstep xrun preflight show_key field_mode rotate_logs thermal vitals mem_tune cut_services system_rw front_led motd net_diag sys_diag sd_inspect sd_boot set_network set_time menu"

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

# post-install : pose le hook de demarrage automatiquement.
# Non bloquant : si /system refuse l'ecriture, simple avertissement
# (boot INSTALL restera possible manuellement).
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
    echo "Commandes disponibles : deploy INSTALL | RESTORE | PKG | EXPOSE | STOP | SEND_LOGS | VERSION | STATUS | CLEAN | HELP"
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
    # pidfile perdu) -> scan des cmdlines dans /proc
    for D in /proc/[0-9]*; do
        [ -r "$D/cmdline" ] || continue
        C="$(tr '\0' ' ' < "$D/cmdline" 2>/dev/null)"
        case "$C" in
            *control_server.sh*) N="control_server" ;;
            *gui_server.sh*)     N="gui_server" ;;
            *watch_usb.sh*)      N="watch_usb" ;;
            *)                   continue ;;
        esac
        PID="${D#/proc/}"
        if kill "$PID" 2>/dev/null; then
            echo "[ OK ] $N orphelin arrete (PID $PID)"
            FOUND=1
        fi
    done

    if [ "$FOUND" -eq 0 ]; then
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

case "$1" in

    INSTALL)
        do_install
        ;;

    PKG)
        do_pkg "$2"
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
        # protection optionnelle de l'API 8080 / GUI 8081 par secret partage :
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
                    echo "protection : DESACTIVEE (API 8080 / GUI 8081 ouvertes au LAN)"
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
        TOTAL=8
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
        echo "  RESTORE      Restaurer la derniere installation sauvegardee"
        echo "  EXPOSE       Exposer la cle (HTTP port 8000)"
        echo "  STOP         Arreter les serveurs"
        echo "  SEND_LOGS    Collecter les logs sur la cle"
        echo "  VERSION      Versions installee / cle (diagnostic mise a jour)"
        echo "  STATUS       Etat du deploiement : outils, liens, backups, cle"
        echo "  CLEAN [DRY]  Assainissement : backups/manifests/shots/staging"
        echo "  TOKEN        Protection API 8080/GUI 8081 (ON/OFF/<valeur>/STATUS)"
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
