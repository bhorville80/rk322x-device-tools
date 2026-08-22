#!/bin/sh

cd "$(dirname "$0")/.." || exit 1

VERSION="$(sed -n 's/^DEPLOY_VERSION=//p' config/device.conf 2>/dev/null | tr -d '\r')"
[ -n "$VERSION" ] || VERSION="0"

TS="$(date '+%Y%m%d-%H%M%S')"
NAME="rk322x-tools_v${VERSION}_${TS}.dpk"

mkdir -p dist || exit 1
OUT="dist/$NAME"

tar --exclude='*.bak' -czf "$OUT" \
    deploy.sh \
    set_network.sh \
    set_time.sh \
    setHEURE_FILE.sh \
    setHEURE_INIT.sh \
    disable_wireless.sh \
    index.html \
    scripts \
    server \
    bin \
    config 2>/dev/null || exit 1

if command -v sha256sum >/dev/null 2>&1; then
    ( cd dist && sha256sum "$NAME" > "$NAME.sha256" )
    echo "Somme   : $(cat "$OUT.sha256")"
fi

echo ""
echo "Package : $OUT"
echo "Contenu :"
tar -tzf "$OUT" | sed 's/^/  /'
echo ""
NFILES="$(tar -tzf "$OUT" | wc -l)"
SIZE="$(du -h "$OUT" | cut -f1)"
echo "OK : $NFILES entrees, $SIZE"
