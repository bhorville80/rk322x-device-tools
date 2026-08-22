#!/system/bin/sh

CONFIG_FILE=""
PROFILE_FILE=""
SECRETS_FILE=""

find_config()
{
    for c in \
        "$(dirname "$0")/config/device.conf" \
        "$(dirname "$0")/../config/device.conf" \
        "$(dirname "$0")/../../config/device.conf" \
        "/data/scripts/config/device.conf" ; do
        if [ -f "$c" ]; then
            CONFIG_FILE="$c"
            break
        fi
    done
    [ -n "$CONFIG_FILE" ] || return 1

    D="$(dirname "$CONFIG_FILE")"

    S="$D/secrets.conf"
    [ -f "$S" ] && SECRETS_FILE="$S"

    P="$(sed -n 's/^PROFILE=//p' "$CONFIG_FILE" 2>/dev/null | head -n 1 | tr -d '\r')"
    if [ -n "$P" ] && [ -f "$D/profiles/$P.conf" ]; then
        PROFILE_FILE="$D/profiles/$P.conf"
    fi

    return 0
}

find_config

cfg_read()
{
    F="$1"
    KEY="$2"
    [ -n "$F" ] && [ -f "$F" ] || return 0
    sed -n "s/^${KEY}=//p" "$F" 2>/dev/null | head -n 1 | tr -d '\r'
}

config_get()
{
    KEY="$1"
    DEF="${2:-}"

    VAL=""
    [ -z "$VAL" ] && VAL="$(cfg_read "$PROFILE_FILE" "$KEY")"
    [ -z "$VAL" ] && VAL="$(cfg_read "$CONFIG_FILE" "$KEY")"
    [ -z "$VAL" ] && VAL="$(cfg_read "$SECRETS_FILE" "$KEY")"

    if [ -n "$VAL" ]; then
        echo "$VAL"
    else
        echo "$DEF"
    fi
}

require_root()
{
    if [ "$(id -u 2>/dev/null)" != "0" ]; then
        echo "[ERREUR] privileges root requis"
        if [ -n "$*" ]; then
            echo "         relancer par exemple : su -c \"sh $0 $*\""
        else
            echo "         relancer par exemple : su -c \"sh $0\""
        fi
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
