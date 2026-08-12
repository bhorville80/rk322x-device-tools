#!/system/bin/sh

USB_DIR="/mnt/media_rw/4E28-7C59"
LOG_DIR="$USB_DIR/log"
LOG_FILE="$LOG_DIR/system.log"

mkdir -p "$LOG_DIR"

log_msg()
{
    SCRIPT="$1"
    ACTION="$2"
    RESULT="$3"

    printf '%s [%s] %s : %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" \
        "$SCRIPT" \
        "$ACTION" \
        "$RESULT" >> "$LOG_FILE"
}

log_ok()
{
    log_msg "$1" "$2" "OK"
}

log_error()
{
    log_msg "$1" "$2" "ERROR"
}
