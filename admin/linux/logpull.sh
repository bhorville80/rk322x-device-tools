#!/bin/sh
# logpull.sh - recupere les collections SEND_LOGS de la cle vers le PC (via adb)
#
# La cle reste branchee sur la box : l'archive est faite sur la box (root),
# poussee en /data/local/tmp puis tiree vers history/logs/.
#
# Usage:
#   admin/linux/logpull.sh                 # derniere collection
#   admin/linux/logpull.sh -a              # toutes les collections
#   admin/linux/logpull.sh -t IP:5555 -o /tmp/out
#
# Prerequis : adb + acces root (su). Toolkit installe non requis.

REPO="$(cd "$(dirname "$0")/../.." && pwd)"

die() { echo "[ERREUR logpull] $*" >&2; exit 1; }

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; }

TARGET=""
OUT="$REPO/history/logs"
ALL=0
while [ $# -gt 0 ]; do
    case "$1" in
        -a|--all)    ALL=1; shift ;;
        -t|--target) TARGET="$2"; shift 2 ;;
        -o|--out)    OUT="$2"; shift 2 ;;
        -h|--help)   usage; exit 0 ;;
        *)           die "option inconnue : $1 (-h pour l'aide)" ;;
    esac
done

command -v adb >/dev/null 2>&1 || die "adb introuvable dans le PATH"

if [ -z "$TARGET" ]; then
    TARGET="${DPK_TARGET:-}"
fi
if [ -z "$TARGET" ]; then
    CONF="$REPO/config/device.conf"
    [ -f "$CONF" ] || die "config/device.conf introuvable (et pas de -t)"
    IP="$(sed -n 's/^IP=//p' "$CONF" | head -n 1 | tr -d '\r')"
    [ -n "$IP" ] || die "IP illisible dans config/device.conf"
    TARGET="$IP:5555"
fi

case "$TARGET" in *:*) adb connect "$TARGET" > /dev/null 2>&1 ;; esac
adb_run() { adb -s "$TARGET" "$@"; }
rget() { adb_run shell "$1" 2>/dev/null | tr -d '\r'; }
rrun() { adb_run shell "su -c '$1'" > /dev/null 2>&1; }

KEY_DIR="$(rget 'ls -1d /mnt/media_rw/*/deploy.sh 2>/dev/null' | head -n 1)"
[ -n "$KEY_DIR" ] || die "aucune cle detectee sur la box ($TARGET)"
KEY_DIR="${KEY_DIR%/deploy.sh}"

COLS="$(rget "ls -1d $KEY_DIR/log/log_* 2>/dev/null | sort")"
[ -n "$COLS" ] || die "aucune collection SEND_LOGS sur la cle (deploy SEND_LOGS d'abord ?)"

if [ "$ALL" -eq 1 ]; then
    BASES="$(printf '%s\n' "$COLS" | sed "s|$KEY_DIR/log/||" | tr '\n' ' ')"
    LABEL="tout"
else
    LAST="$(printf '%s\n' "$COLS" | tail -n 1)"
    BASES="$(basename "$LAST")"
    LABEL="$BASES"
fi
# un seul mot attendu (log_<TS>) ; securise contre les espaces
case "$BASES" in *[!a-zA-Z0-9_.-]*) die "nom de collection inattendu : $BASES" ;; esac

STAMP="$(date '+%Y%m%d-%H%M%S')"
REMOTE_TGZ="/data/local/tmp/rk322x_pull_$STAMP.tgz"

echo "[..] tirage de : $LABEL <- $KEY_DIR/log"
rrun "tar -czf $REMOTE_TGZ -C $KEY_DIR/log $BASES || busybox tar -czf $REMOTE_TGZ -C $KEY_DIR/log $BASES"

mkdir -p "$OUT" || die "destination inaccessible : $OUT"
LOCAL_TGZ="$OUT/rk322x_pull_$STAMP.tgz"
adb_run pull "$REMOTE_TGZ" "$LOCAL_TGZ" > /dev/null 2>&1 \
    || { rrun "rm -f $REMOTE_TGZ"; die "echec adb pull"; }
rrun "rm -f $REMOTE_TGZ"

EXTRACT="$OUT/${BASES%% *}_$STAMP"
mkdir -p "$EXTRACT"
tar -xzf "$LOCAL_TGZ" -C "$EXTRACT" 2>/dev/null || die "extraction locale impossible"
rm -f "$LOCAL_TGZ"

echo "[ OK ] extrait dans : $EXTRACT"
find "$EXTRACT" -type f | sed 's/^/       /'
