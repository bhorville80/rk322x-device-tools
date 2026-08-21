#!/system/bin/sh

CONFIG_FILE=""

find_config()
{
    for c in \
        "$(dirname "$0")/config/device.conf" \
        "$(dirname "$0")/../config/device.conf" \
        "$(dirname "$0")/../../config/device.conf" \
        "/data/scripts/config/device.conf" ; do
        if [ -f "$c" ]; then
            CONFIG_FILE="$c"
            return 0
        fi
    done
    return 1
}

find_config

config_get()
{
    KEY="$1"
    DEF="${2:-}"

    VAL=""
    if [ -n "$CONFIG_FILE" ]; then
        VAL="$(sed -n "s/^${KEY}=//p" "$CONFIG_FILE" 2>/dev/null | head -n 1 | tr -d '\r')"
    fi

    if [ -n "$VAL" ]; then
        echo "$VAL"
    else
        echo "$DEF"
    fi
}

require_root()
{
    if [ "$(id -u 2>/dev/null)" != "0" ]; then
        echo "[ERREUR] privileges root requis : lancer depuis un shell su"
        return 1
    fi
    return 0
}

require_busybox()
{
    if ! command -v busybox >/dev/null 2>&1; then
        echo "[ERREUR] busybox introuvable"
        return 1
    fi
    return 0
}
