#!/bin/sh
# tools/usb_zip.sh - construit le zip "cle USB prete a l'emploi" dans dist/
#
# Contenu (a dezipper a la racine de la cle) :
#   AMORCE                          aide-memoire box
#   deploy.sh                       installeur / point d'entree
#   rk322x-tools_v<ver>_<id>.dpk    dernier paquet construit (+ .sha256 si present)
#   admin/linux provision.sh        provisioning cote PC (avant branchement box)
#   admin/windows provision.ps1
#
# Le panneau web (web/index.html) n'est pas dans le zip : il est embarque
# dans le .dpk et copie a la racine de la cle par INSTALL/PKG.
#
# Usage:
#   tools/usb_zip.sh            construire le zip depuis le dernier .dpk
#   tools/usb_zip.sh help       cette aide

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO" || exit 1

DIST="dist"

say() { echo "[usb-zip] $*"; }
die() { echo "[ERREUR usb-zip] $*" >&2; exit 1; }
usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; }

case "${1:-}" in
    ""|build) ;;
    help|-h|--help) usage ; exit 0 ;;
    *) die "option inconnue : $1 (voir tools/usb_zip.sh help)" ;;
esac

DPK="$(sh tools/dpk.sh latest 2>/dev/null)"
[ -n "$DPK" ] && [ -f "$DPK" ] || die "aucun paquet dans dist/ : lancer tools/build.sh d'abord"

BASE="$(basename "$DPK" .dpk)"
BUILD_ID="${BASE##*_}"
VERSION="$(sed -n 's/^DEPLOY_VERSION=//p' config/device.conf 2>/dev/null | tr -d '\r')"
[ -n "$VERSION" ] || die "DEPLOY_VERSION illisible dans config/device.conf"

NAME="rk322x-cle_v${VERSION}_${BUILD_ID}.zip"
OUT="$REPO/$DIST/$NAME"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/rk322x_cle.XXXXXX")" || die "tmp indisponible"
trap 'rm -rf "$STAGE"' EXIT INT TERM

say "assemblage du contenu cle..."
mkdir -p "$STAGE/admin" || die "stage impossible"
cp -f AMORCE deploy.sh "$STAGE/" || die "copie AMORCE/deploy.sh"
cp -f "$DPK" "$STAGE/" || die "copie du paquet"
[ -f "$DPK.sha256" ] && cp -f "$DPK.sha256" "$STAGE/"
cp -rf admin/. "$STAGE/admin/" || die "copie admin/"

# --- creation de l'archive (zip natif, sinon bsdtar, sinon PowerShell) -------
MADE=""
if command -v zip >/dev/null 2>&1; then
    ( cd "$STAGE" && zip -qr "$OUT" . ) || die "echec zip"
    MADE="zip"
else
    TAR_BIN=""
    for T in "/c/Windows/System32/tar.exe" "$(command -v tar 2>/dev/null)"; do
        [ -n "$T" ] && [ -f "$T" ] || continue
        "$T" --version 2>/dev/null | grep -q bsdtar || continue
        TAR_BIN="$T"
        break
    done
    if [ -n "$TAR_BIN" ]; then
        OUT_W="$(cygpath -w "$OUT" 2>/dev/null || echo "$OUT")"
        ( cd "$STAGE" && "$TAR_BIN" -a -cf "$OUT_W" AMORCE deploy.sh *.dpk *.sha256 admin ) \
            || die "echec bsdtar"
        MADE="bsdtar"
    else
        command -v powershell.exe >/dev/null 2>&1 || die "ni zip, ni bsdtar, ni PowerShell"
        OUT_W="$(cygpath -w "$OUT")"
        STAGE_W="$(cygpath -w "$STAGE")"
        powershell.exe -NoProfile -Command \
            "Compress-Archive -Path '$STAGE_W\\*' -DestinationPath '$OUT_W' -Force" \
            || die "echec Compress-Archive"
        MADE="powershell"
    fi
fi

[ -s "$OUT" ] || die "archive vide ou absente : $OUT"

NFILES=0
if [ "$MADE" = "bsdtar" ]; then
    NFILES="$("$TAR_BIN" -tf "$OUT_W" 2>/dev/null | grep -c .)"
fi

echo ""
echo "Zip     : $OUT"
echo "Taille  : $(du -h "$DIST/$NAME" | cut -f1)"
[ -n "$NFILES" ] && echo "Entrees : $NFILES"
echo ""
echo "Contenu :"
if [ "$MADE" = "bsdtar" ]; then
    "$TAR_BIN" -tf "$OUT_W" 2>/dev/null | sed 's/^/  /'
else
    ( cd "$STAGE" && find . -type f | sed 's/^\.\///;s/^/  /' )
fi
echo ""
echo "OK : dezipper a la racine de la cle USB"
