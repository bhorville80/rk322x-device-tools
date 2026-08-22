#!/system/bin/sh

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

USB_DIR=""

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

pkg_version()
{
    echo "$1" | sed -n 's/.*_v\([0-9]*\)_.*/\1/p'
}

installed_version()
{
    sed -n 's/^version : *//p' /data/scripts/VERSION 2>/dev/null | tr -d '\r' | head -n 1
}

main()
{
    echo ""
    echo "=== CLE USB - ETAT / PAQUETS ==="

    if ! find_usb; then
        echo "[ERREUR] aucune cle USB contenant deploy.sh trouvee"
        return 1
    fi

    echo ""
    echo "--- Cle ---"
    echo "  Chemin : $USB_DIR"
    echo "  ID     : $(basename "$USB_DIR")"

    echo ""
    echo "--- Paquets .dpk disponibles ---"

    LATEST="$(ls -1 "$USB_DIR"/*.dpk 2>/dev/null | sort | tail -n 1)"

    FOUND=0
    for P in $(ls -1 "$USB_DIR"/*.dpk 2>/dev/null | sort); do
        FOUND=$((FOUND+1))
        NAME="$(basename "$P")"
        SIZE="$(du -h "$P" 2>/dev/null | cut -f1)"
        VER="$(pkg_version "$NAME")"
        MARK=""
        [ "$P" = "$LATEST" ] && MARK="   <-- cible de deploy PKG"
        printf '  [%s] v%s  %-45s %s%s\n' "$FOUND" "${VER:-?}" "$NAME" "$SIZE" "$MARK"
    done

    if [ "$FOUND" -eq 0 ]; then
        echo "  [ -- ] aucun paquet .dpk sur la cle"
    fi

    echo ""
    echo "--- Installation sur la box ---"

    INST="$(installed_version)"
    if [ -z "$INST" ]; then
        echo "  [ -- ] rien d'installe (deploy INSTALL ou deploy PKG)"
    else
        DATE_INST="$(sed -n 's/^date    : *//p' /data/scripts/VERSION 2>/dev/null | head -n 1)"
        SRC_INST="$(sed -n 's/^source  : *//p' /data/scripts/VERSION 2>/dev/null | head -n 1)"
        echo "  Installee : v$INST ($DATE_INST, source $SRC_INST)"

        if [ -n "$LATEST" ]; then
            VER_LATEST="$(pkg_version "$(basename "$LATEST")")"
            case "$VER_LATEST" in
                ''|*[!0-9]*) ;;
                *)
                    if [ "$VER_LATEST" -gt "$INST" ]; then
                        echo "  [WARN] mise a jour disponible (paquet v$VER_LATEST)"
                    elif [ "$VER_LATEST" -lt "$INST" ]; then
                        echo "  [WARN] paquet plus ancien que l'installation"
                    else
                        echo "  [ OK ] boite a jour"
                    fi
                    ;;
            esac
        fi
    fi

    echo ""
    echo "--- Etat de la cle ---"

    PENDING=0
    for F in "$USB_DIR"/incoming/*; do
        [ -f "$F" ] || continue
        case "$(basename "$F")" in .*|_*) continue ;; esac
        PENDING=$((PENDING+1))
    done
    echo "  Fichiers temoins en attente : $PENDING"

    EXEC_LOGS=0
    for F in "$USB_DIR"/log/exec/*.log; do
        [ -f "$F" ] || continue
        EXEC_LOGS=$((EXEC_LOGS+1))
    done
    echo "  Logs d'execution            : $EXEC_LOGS"

    MANIFESTS=0
    for F in "$USB_DIR"/manifests/current/install_*.manifest; do
        [ -f "$F" ] || continue
        MANIFESTS=$((MANIFESTS+1))
    done
    echo "  Manifests courants          : $MANIFESTS"

    echo ""
    return 0
}

if [ "$RUNLOG_LOADED" -eq 1 ] && runlog_start "$SCRIPT_ID"; then
    main >> "$RUNLOG_FILE" 2>&1
    RC=$?
    runlog_end "$RC"
    cat "$RUNLOG_FILE"
else
    main
    RC=$?
fi

exit "$RC"
