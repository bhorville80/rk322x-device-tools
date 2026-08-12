#!/system/bin/sh

find_deploy_usb()
{
    for d in /mnt/media_rw/*; do
        [ -d "$d" ] || continue
        [ -f "$d/deploy.sh" ] || continue

        USB_DIR="$d"
        USB_ID="$(basename "$d")"

        export USB_DIR
        export USB_ID

        return 0
    done

    return 1
}
