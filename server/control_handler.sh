#!/system/bin/sh

USB="/mnt/media_rw/4E28-7C59"
INCOMING="$USB/incoming"

REQUEST="$(head -n 1)"

case "$REQUEST" in
    *"/api/HELP"*)
        touch "$INCOMING/HELP"
        ;;

    *"/api/SEND_LOGS"*)
        touch "$INCOMING/SEND_LOGS"
        ;;

    *"/api/PURGE_LOG"*)
        touch "$INCOMING/PURGE_LOG"
        ;;

    *"/api/SYNC"*)
        touch "$INCOMING/SYNC"
        ;;

    *)
        ;;
esac

printf 'HTTP/1.1 200 OK\r\n'
printf 'Content-Type: text/plain\r\n'
printf 'Connection: close\r\n'
printf '\r\n'
printf 'OK\r\n'
