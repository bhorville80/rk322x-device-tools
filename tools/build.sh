#!/bin/sh
# tools/build.sh - process de build complet
#
#   1. controle statique des scripts shell   (tools/check.sh)
#   2. construction du paquet .dpk           (tools/pack.sh)
#   3. verification du paquet produit        (tools/dpk.sh verify)
#
# Usage:
#   tools/build.sh

REPO="$(cd "$(dirname "$0")/.." && pwd)"

echo "[build] === 1/3 controle des scripts ==="
sh "$REPO/tools/check.sh" || exit 1

echo ""
echo "[build] === 2/3 construction du paquet ==="
sh "$REPO/tools/pack.sh" || exit 1

echo ""
echo "[build] === 3/3 verification du paquet ==="
sh "$REPO/tools/dpk.sh" verify || exit 1

# rotation dist/ : ne garder que les KEEP derniers paquets (+ .sha256)
KEEP=5
cd "$REPO/dist" 2>/dev/null && {
    OLD="$(ls -1 *.dpk 2>/dev/null | sort -t_ -k3 | head -n -"$KEEP" 2>/dev/null)"
    for F in $OLD; do
        rm -f "$F" "$F.sha256"
        echo "[build] rotation dist : $F supprime (garde les $KEEP derniers)"
    done
    cd "$REPO"
}

echo ""
echo "[build] OK"
