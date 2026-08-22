#!/bin/sh
# tools/check.sh - controle statique des scripts shell du depot (gate de build)
#
#   sh -n        obligatoire sur tous les *.sh (hors dist/, history/, .git/)
#   shellcheck   si installe : rapport detaille ; bloquant seulement avec CHECK_STRICT=1
#
# Usage:
#   tools/check.sh

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO" || exit 1

LIST="$(find . -name '*.sh' \
        -not -path './dist/*' \
        -not -path './history/*' \
        -not -path './.git/*' | sort)"

if [ -z "$LIST" ]; then
    echo "[check] aucun script shell trouve"
    exit 0
fi

TMP_ERR="${TMPDIR:-/tmp}/rk322x_check_err.$$"
N=0
ERR=0
for F in $LIST; do
    N=$((N+1))
    if ! sh -n "$F" 2> "$TMP_ERR"; then
        echo "[ERREUR check] syntaxe : $F"
        sed 's/^/    /' "$TMP_ERR"
        ERR=$((ERR+1))
    fi
done
rm -f "$TMP_ERR"

echo "[check] sh -n : $N scripts verifies, $ERR erreur(s)"
[ "$ERR" -eq 0 ] || exit 1

if command -v shellcheck > /dev/null 2>&1; then
    if shellcheck $LIST > /dev/null 2>&1; then
        echo "[check] shellcheck : OK"
    else
        RC=$?
        echo "[check] shellcheck : remarques (rc=$RC), details :"
        shellcheck $LIST || true
        echo "[check] shellcheck : advisory${CHECK_STRICT:+ et BLOQUANT (CHECK_STRICT=1)}"
        [ "${CHECK_STRICT:-0}" = "1" ] && exit "$RC"
    fi
else
    echo "[check] shellcheck absent : saute"
fi

exit 0
