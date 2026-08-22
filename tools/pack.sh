#!/bin/sh
# tools/pack.sh - construit le paquet .dpk dans dist/
#
# Usage:
#   tools/pack.sh             construire le paquet
#   tools/pack.sh help        cette aide
#
# Sorties:
#   dist/rk322x-tools_v<version>_<BUILD_ID>.dpk          archive tar.gz du toolkit
#   dist/rk322x-tools_v<version>_<BUILD_ID>.dpk.sha256   empreinte de controle
#   dist/latest/                                         copie du dernier build
#
# BUILD_ID au format YY.MM.ddHH.MMss (ex : 26.08.2221.4320).
# Le paquet embarque un BUILD-INFO.txt (version, build_id, date, etat git).
# En cas d'echec, aucune archive partielle n'est laissee dans dist/.

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO" || exit 1

DIST="dist"
NAME_BASE="rk322x-tools"

say() { echo "[pack] $*"; }
die() { echo "[ERREUR pack] $*" >&2; exit 1; }
usage()
{
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
}

OK=0
OUT=""
BUILD_INFO="$REPO/BUILD-INFO.txt"
trap 'rm -f "$BUILD_INFO"; [ "$OK" = "1" ] || [ -z "$OUT" ] || rm -f "$OUT"' EXIT INT TERM

case "${1:-}" in
    ""|build) ;;
    help|-h|--help) usage ; exit 0 ;;
    *) die "option inconnue : $1 (voir tools/pack.sh help)" ;;
esac

command -v tar >/dev/null 2>&1 || die "tar introuvable dans le PATH"

VERSION="$(sed -n 's/^DEPLOY_VERSION=//p' config/device.conf 2>/dev/null | tr -d '\r')"
[ -n "$VERSION" ] || die "DEPLOY_VERSION illisible dans config/device.conf"

# --- entrees du paquet ------------------------------------------------------
INPUTS="AMORCE deploy.sh scripts server config web"

MISSING=""
for F in $INPUTS; do
    [ -e "$F" ] || MISSING="$MISSING $F"
done
[ -z "$MISSING" ] || die "entrees manquantes :$MISSING"

# --- garde-fou fins de ligne -------------------------------------------------
# Un \r (CRLF Windows) casse l'execution sur la box :
#   tmp-mksh: ... not found / syntax error: 'do' unexpected
# On refuse tout build dont les scripts seraient contamines.
CR_LIST=""
for F in $(find $INPUTS -type f \
        ! -name '*.ps1' ! -name '*.bat' \
        ! -name '*.pid' ! -name '*.log' \
        ! -name '*.bak' ! -name '*.swp' ! -name '*~' 2>/dev/null | sort); do
    if [ -n "$(tr -dc '\r' < "$F" 2>/dev/null)" ]; then
        CR_LIST="$CR_LIST $F"
    fi
done
[ -z "$CR_LIST" ] || die "fins de ligne CRLF detectees dans :$CR_LIST (convertir en LF)"

# --- metadonnees de construction -------------------------------------------
# BUILD_ID horodate au format YY.MM.ddHH.MMss (ex : 26.08.2221.4320)
BUILD_ID="$(date '+%y.%m.%d%H.%M%S')"
NAME="${NAME_BASE}_v${VERSION}_${BUILD_ID}.dpk"
OUT="$DIST/$NAME"
LATEST_DIR="$DIST/latest"

GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo inconnu)"
GIT_STATE="clean"
[ -n "$(git status --porcelain 2>/dev/null | head -n 1)" ] && GIT_STATE="modifie"

{
    echo "paquet   : $NAME"
    echo "version  : $VERSION"
    echo "build_id : $BUILD_ID"
    echo "date     : $(date '+%Y-%m-%d %H:%M:%S')"
    echo "git      : $GIT_SHA ($GIT_STATE)"
    echo "hote     : $(uname -s -r 2>/dev/null)"
} > "$BUILD_INFO" || die "ecriture BUILD-INFO.txt impossible"

mkdir -p "$DIST" || die "dist/ inaccessible"

# --- construction -----------------------------------------------------------
say "construction : $OUT"
if ! tar --exclude='*.bak' --exclude='*.swp' --exclude='*~' \
         --exclude='*.pid' --exclude='*.log' \
         --exclude='config/secrets.conf' \
         -czf "$OUT" BUILD-INFO.txt $INPUTS; then
    die "echec tar (voir messages ci-dessus)"
fi
rm -f "$BUILD_INFO"

# --- verification post-build -------------------------------------------------
tar -tzf "$OUT" > /dev/null 2>&1 || die "archive produite illisible"
tar -tzf "$OUT" | grep -q '^deploy.sh$' || die "deploy.sh absent de l'archive"

if command -v sha256sum >/dev/null 2>&1; then
    ( cd "$DIST" && sha256sum "$NAME" > "$NAME.sha256" ) \
        || die "calcul sha256 impossible"
fi

NFILES="$(tar -tzf "$OUT" | wc -l)"
SIZE="$(du -h "$OUT" | cut -f1)"

# --- dernier build isole dans dist/latest/ ----------------------------------
mkdir -p "$LATEST_DIR" || die "dist/latest inaccessible"
rm -f "$LATEST_DIR"/*.dpk "$LATEST_DIR"/*.sha256 2>/dev/null
cp -f "$OUT" "$LATEST_DIR/" || die "copie vers dist/latest echouee"
[ -f "$OUT.sha256" ] && cp -f "$OUT.sha256" "$LATEST_DIR/"

OK=1
echo ""
echo "Package : $OUT"
[ -f "$OUT.sha256" ] && echo "Somme   : $(cat "$OUT.sha256")"
echo "Latest  : $LATEST_DIR/$NAME (historique conserve dans dist/)"
echo "Git     : $GIT_SHA ($GIT_STATE)"
echo "Contenu :"
tar -tzf "$OUT" | sed 's/^/  /'
echo ""
echo "OK : $NFILES entrees, $SIZE"
