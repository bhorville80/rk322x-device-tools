#!/system/bin/sh

RUNLOG_ROOT=""
RUNLOG_DIR=""
RUNLOG_FILE=""

find_log_root()
{
    for d in /mnt/media_rw/*; do
        [ -d "$d" ] || continue
        [ -f "$d/deploy.sh" ] || continue
        RUNLOG_ROOT="$d"
        return 0
    done

    for d in /mnt/media_rw/*; do
        [ -d "$d" ] || continue
        RUNLOG_ROOT="$d"
        return 0
    done

    return 1
}

runlog_start()
{
    SCRIPT_ID="$1"

    if find_log_root; then
        RUNLOG_DIR="$RUNLOG_ROOT/log/exec"
    else
        RUNLOG_DIR="/data/local/tmp/rk322x_logs/exec"
    fi

    if ! mkdir -p "$RUNLOG_DIR" 2>/dev/null; then
        RUNLOG_DIR="${TMPDIR:-/tmp}/rk322x_logs/exec"
        mkdir -p "$RUNLOG_DIR" 2>/dev/null || return 1
    fi

    TS="$(date '+%Y%m%d-%H%M%S')"
    RUNLOG_FILE="$RUNLOG_DIR/${SCRIPT_ID}_${TS}.log"

    {
        echo "=== RK322X EXEC ==="
        echo "script : $SCRIPT_ID"
        echo "debut  : $(date '+%Y-%m-%d %H:%M:%S')"
        echo "device : $(getprop ro.product.device 2>/dev/null)"
        echo "uid    : $(id -u 2>/dev/null)"
        echo "log    : $RUNLOG_FILE"
        echo "---"
    } > "$RUNLOG_FILE" 2>/dev/null

    [ -s "$RUNLOG_FILE" ]
}

runlog_end()
{
    [ -n "$RUNLOG_FILE" ] && [ -f "$RUNLOG_FILE" ] || return 0
    {
        echo "---"
        echo "fin    : $(date '+%Y-%m-%d %H:%M:%S')"
        echo "rc     : $1"
    } >> "$RUNLOG_FILE" 2>/dev/null
    return 0
}
