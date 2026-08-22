#!/bin/sh
# write_set_heure.sh - depose SET_HEURE (heure UTC du PC) a la racine de la cle USB
#
# La box lira ce fichier au prochain set_time AUTO / set_time FILE.
# Format : une ligne YYYYMMDD.HHMMSS (UTC).
#
# Usage:
#   admin/linux/write_set_heure.sh                  # cle auto-detectee
#   admin/linux/write_set_heure.sh /media/user/CLE  # chemin explicite

REPO="$(cd "$(dirname "$0")/../.." && pwd)"

die() { echo "[ERREUR SET_HEURE] $*" >&2; exit 1; }

KEY="${1:-}"

if [ -z "$KEY" ]; then
    USER_NAME="${USER:-$(id -un 2>/dev/null)}"
    for D in /media/$USER_NAME/* /run/media/$USER_NAME/* /mnt/*; do
        [ -d "$D" ] || continue
        [ -w "$D" ] || continue
        KEY="$D"
        break
    done
    [ -n "$KEY" ] || die "aucune cle USB detectee (ou passer le chemin en argument)"
fi

[ -d "$KEY" ] || die "chemin introuvable : $KEY"
[ -w "$KEY" ] || die "cle non accessible en ecriture : $KEY"

NOW="$(date -u '+%Y%m%d.%H%M%S')"
printf '%s' "$NOW" > "$KEY/SET_HEURE" || die "ecriture impossible sur $KEY/SET_HEURE"
sync

echo "[ OK ] $KEY/SET_HEURE <- $NOW (UTC)"
exit 0
