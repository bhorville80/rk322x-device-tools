#!/system/bin/sh

svc wifi disable

settings put global bluetooth_on 0

stop bluetooth 2>/dev/null
stop com.android.bluetooth 2>/dev/null

ifconfig wlan0 down 2>/dev/null
ifconfig p2p0 down 2>/dev/null
hciconfig hci0 down 2>/dev/null

exit 0
