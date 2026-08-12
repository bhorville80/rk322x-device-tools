#!/system/bin/sh

echo "Heure actuelle BOX :"
date

if command -v toybox >/dev/null 2>&1; then
    echo ""
    echo "Pour régler l'heure depuis ADB :"
    echo "adb shell date -u -s YYYYMMDD.HHMMSS"
fi

exit 0
