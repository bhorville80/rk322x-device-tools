#!/bin/sh
# tools/dpk.sh - gestion des paquets .dpk cote PC
#
# Usage:
#   tools/dpk.sh build               construire le paquet (via pack.sh)
#   tools/dpk.sh list                lister les paquets de dist/
#   tools/dpk.sh latest              chemin du dernier paquet construit
#   tools/dpk.sh verify [f]          verifier un paquet (tar.gz + sha256)
#   tools/dpk.sh push [-t S] [f]     adb push du paquet vers la box
#   tools/dpk.sh install [-t S] [f]  push + installation a distance
#   tools/dpk.sh help                cette aide
#
# Options:
#   -t S / --target S   serial ou adresse adb (ex: 192.168.50.20:5555)
#   f                   chemin d'un .dpk (defaut : dernier de dist/)

set -e

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$REPO/dist"
PKG_REMOTE_DIR="/data/local/tmp"
DEPLOY_REMOTE="$PKG_REMOTE_DIR/deploy.sh"

TARGET="${DPK_TARGET:-}"
PKG=""

say() { echo "[dpk] $*"; }
die() { echo "[ERREUR dpk] $*" >&2; exit 1; }

adb_run()
{
    if [ -n "$TARGET" ]; then
        adb -s "$TARGET" "$@"
    else
        adb "$@"
    fi
}

latest_pkg()
{
    ls -1 "$DIST"/*.dpk 2>/dev/null | sort | tail -n 1
}

resolve_pkg()
{
    if [ -n "$PKG" ]; then
        if [ ! -f "$PKG" ]; then
            die "paquet introuvable : $PKG"
        fi
        return 0
    fi
    PKG="$(latest_pkg)"
    if [ -z "$PKG" ]; then
        die "aucun .dpk dans dist/ (lancer : tools/dpk.sh build)"
    fi
}

parse_opts()
{
    while [ $# -gt 0 ]; do
        case "$1" in
            -t|--target)
                [ $# -ge 2 ] || die "-t requiert une valeur"
                TARGET="$2"
                shift 2 ;;
            *)
                PKG="$1"
                shift ;;
        esac
    done
}

do_build()
{
    sh "$REPO/tools/pack.sh"
}

do_list()
{
    LATEST="$(latest_pkg)"
    say "paquets dans dist/ :"
    for F in $(ls -1 "$DIST"/*.dpk 2>/dev/null | sort); do
        MARK=" "
        [ "$F" = "$LATEST" ] && MARK="*"
        SIZE="$(du -h "$F" | cut -f1)"
        SUM=""
        if [ -f "$F.sha256" ]; then
            SUM=" sha256:$(cut -d' ' -f1 "$F.sha256" | cut -c1-12)..."
        fi
        echo "  $MARK $(basename "$F")  ($SIZE$SUM)"
    done
    if [ -z "$LATEST" ]; then
        echo "  (vide)"
    else
        say "dernier : $LATEST"
    fi
    return 0
}

do_latest()
{
    resolve_pkg
    echo "$PKG"
}

do_verify()
{
    resolve_pkg
    say "verification : $PKG"

    if tar -tzf "$PKG" > /dev/null 2>&1; then
        NFILES="$(tar -tzf "$PKG" | wc -l)"
        say "[ OK ] archive lisible ($NFILES entrees)"
    else
        die "archive illisible (tar+gzip requis)"
    fi

    if tar -tzf "$PKG" | grep -q '^deploy.sh$'; then
        say "[ OK ] deploy.sh present"
    else
        die "deploy.sh absent de l'archive"
    fi

    if [ -f "$PKG.sha256" ]; then
        if command -v sha256sum >/dev/null 2>&1; then
            WANT="$(cut -d' ' -f1 "$PKG.sha256")"
            GOT="$(sha256sum "$PKG" | cut -d' ' -f1)"
            if [ "$GOT" = "$WANT" ]; then
                say "[ OK ] sha256 correspond"
            else
                die "sha256 differents (attendu $WANT, obtenu $GOT)"
            fi
        else
            say "[ WARN ] sha256sum absent, controle saute"
        fi
    else
        say "[ WARN ] pas de .sha256 associe"
    fi

    say "OK : $PKG"
}

require_adb()
{
    command -v adb >/dev/null 2>&1 || die "adb introuvable dans le PATH"
}

check_device()
{
    if ! adb_run get-state > /dev/null 2>&1; then
        if [ -n "$TARGET" ]; then
            say "device injoignable, tentative adb connect..."
            adb connect "$TARGET" > /dev/null 2>&1 || true
            sleep 1
        fi
        adb_run get-state > /dev/null 2>&1 \
            || die "aucun device adb (target: ${TARGET:-defaut})"
    fi
    say "[ OK ] device adb joignable"
}

do_push()
{
    require_adb
    resolve_pkg
    do_verify
    check_device

    say "push -> $PKG_REMOTE_DIR/"
    adb_run push "$PKG" "$PKG_REMOTE_DIR/" > /dev/null || die "push echoue"
    adb_run push "$REPO/deploy.sh" "$DEPLOY_REMOTE" > /dev/null \
        || die "push deploy.sh echoue"

    say "[ OK ] $(basename "$PKG") + deploy.sh pushes sur la box"
    say "installation : tools/dpk.sh install ou deploy PKG sur la box"
}

do_install()
{
    require_adb
    resolve_pkg
    check_device

    NAME="$(basename "$PKG")"
    REMOTE_PKG="$PKG_REMOTE_DIR/$NAME"

    do_push

    say "installation a distance (deploy PKG)..."
    # NB: guillemets pour que tout passe dans su -c
    # NB: adb ancien ne propage pas toujours le code de sortie distant
    if adb_run shell "su -c 'sh $DEPLOY_REMOTE PKG $REMOTE_PKG'"; then
        say "nettoyage..."
        adb_run shell rm -f "$DEPLOY_REMOTE" "$REMOTE_PKG" > /dev/null 2>&1 || true
        say "TERMINE : $NAME installe"
        say "controle box : show_key | selftest | cat /data/scripts/VERSION"
    else
        say "nettoyage..."
        adb_run shell rm -f "$DEPLOY_REMOTE" > /dev/null 2>&1 || true
        die "installation distante echouee ($NAME laisse sur la box dans $PKG_REMOTE_DIR)"
    fi
}

do_help()
{
    sed -n '3,15p' "$0" | sed 's/^# \{0,1\}//'
}

CMD="${1:-help}"
shift 2> /dev/null || true

case "$CMD" in
    build)          do_build ;;
    list|ls)        parse_opts "$@" ; do_list ;;
    latest)         parse_opts "$@" ; do_latest ;;
    verify)         parse_opts "$@" ; do_verify ;;
    push)           parse_opts "$@" ; do_push ;;
    install)        parse_opts "$@" ; do_install ;;
    help|-h|--help) do_help ;;
    *)              die "commande inconnue : $CMD (voir tools/dpk.sh help)" ;;
esac
