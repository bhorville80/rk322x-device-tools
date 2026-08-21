#!/system/bin/sh

SCRIPT_ID="$(basename "$0" .sh)"

RUNLOG_LOADED=0
for B in "$(dirname "$0")" /data/scripts; do
    if [ -f "$B/core/runlog.sh" ]; then
        . "$B/core/runlog.sh"
        RUNLOG_LOADED=1
        break
    fi
done

main()
{

for d in /mnt/media_rw/*; do
    [ -d "$d" ] || continue

    ID="$(basename "$d")"
    LINE="$(mount | grep " $d " | sed -n '1p')"

    case "$LINE" in
        *"public:8,1"*)
            TYPE="USB"
            ;;
        *"public:179,65"*)
            TYPE="SD"
            ;;
        *)
            TYPE="UNKNOWN"
            ;;
    esac

    echo "ID=$ID"
    echo "TYPE=$TYPE"
    echo "PATH=$d"
    echo "MOUNT=$LINE"
    echo "---"
done
}

if [ "$RUNLOG_LOADED" -eq 1 ] && runlog_start "$SCRIPT_ID"; then
    main >> "$RUNLOG_FILE" 2>&1
    RC=$?
    runlog_end "$RC"
    cat "$RUNLOG_FILE"
else
    main
    RC=$?
fi

exit "$RC"

