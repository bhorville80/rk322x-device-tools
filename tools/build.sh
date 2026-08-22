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

echo ""
echo "[build] OK"
