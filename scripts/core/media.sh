#!/system/bin/sh

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
