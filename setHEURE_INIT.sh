#!/system/bin/sh

TIME="080820262026.02"

echo "Heure actuelle :"
date

echo "Réglage de l'heure : 08/08/2026 20:26:02 GMT"

su -c "date $TIME"

echo "Heure après réglage :"
date

exit 0
