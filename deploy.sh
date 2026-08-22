#!/system/bin/sh

# gardes partages (require_root, require_busybox)
for B in "$(dirname "$0")/scripts" "$(dirname "$0")" /data/scripts; do
    if [ -f "$B/core/config.sh" ]; then
        . "$B/core/config.sh"
        break
    fi
done

SCRIPTS_DIR="/data/scripts"
BIN_DIR="/data/bin"
BACKUP_DIR="/data/backup"

INSTALL_LIST="amorce sync_usb disable_wireless boxhelp media inspect_user inspect_system inspect_services inspect_display inspect_gui inspect_remote inspect_all hdmi check_state help selftest show_key field_mode rotate_logs thermal cut_services system_rw front_led motd net_diag sys_diag set_network setHEURE_FILE setHEURE_INIT"

# adb shell arrive en uid 2000 (shell) : elevation auto via su pour les
# actions qui touchent au systeme ou a la cle. L'aide reste accessible sans root.
case "$1" in
    ""|HELP|help|-h|--help|VERSION|version|STATUS|status)
        ;;
    *)
        if [ "$(id -u 2>/dev/null)" != "0" ] && command -v su > /dev/null 2>&1; then
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
}

backup_existing()
{
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

    mkdir -p "$SCRIPTS_DIR/core" "$SCRIPTS_DIR/config" "$BIN_DIR"

    echo "[2] Copie des scripts..."
    if cp -f "$SRC"/scripts/*.sh "$SCRIPTS_DIR/" 2>/dev/null; then
        echo "    [ OK ] $SCRIPTS_DIR"
    else
        echo "    [ ERREUR ] $SCRIPTS_DIR"
    fi
    if cp -f "$SRC"/scripts/core/*.sh "$SCRIPTS_DIR/core/" 2>/dev/null; then
        echo "    [ OK ] $SCRIPTS_DIR/core"
    else
        echo "    [ ERREUR ] $SCRIPTS_DIR/core"
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

    echo "[3b] Panneau web + AMORCE -> racine de la cle..."
    COPIED=0
    for F in index.html AMORCE; do
        [ -f "$SRC/$F" ] || continue
        if find_usb && cp -f "$SRC/$F" "$USB_DIR/$F" 2>/dev/null; then
            echo "    [ OK ] $USB_DIR/$F"
            COPIED=1
        else
            echo "    [ WARN ] cle inaccessible, $F non copie"
        fi
    done
    [ "$COPIED" -eq 0 ] && echo "    [ -- ] rien a copier (source sans index.html/AMORCE)"

    link_bin

    echo "[3c] Validation..."
    VAL_NOTE="OK"
    if ! verify_install; then
        VAL_NOTE="ECHEC"
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

    echo ""
    echo "=== TERMINE ==="
    if [ "$VALID_RC" != "0" ]; then
        echo "[ ERREUR ] installation incomplete : verifier ci-dessus (deploy STATUS)"
        return 1
    fi
    echo "Commandes disponibles : deploy INSTALL | RESTORE | PKG | EXPOSE | STOP | SEND_LOGS | VERSION | STATUS | CLEAN | HELP"
}

do_install()
{
    require_usb || return 1
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

    LATEST="$(ls -1 "$USB_DIR"/*.dpk 2>/dev/null | sort | tail -n 1)"
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

    require_usb || return 1
    sh "$USB_DIR/server/start_server.sh"
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
        TOTAL=6
        collect logcat   logcat -d
        collect dmesg    dmesg
        collect getprop  getprop
        collect ip_link  ip link
        collect mount    mount
        collect ps       ps

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
