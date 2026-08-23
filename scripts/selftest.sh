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

BASE="$(cd "$(dirname "$0")" && pwd)"

PASS=0
FAIL=0

t_ok() { printf '  [ OK ] %-42s\n' "$1"; PASS=$((PASS+1)); }
t_ko() { printf '  [ KO ] %-42s (%s)\n' "$1" "$2"; FAIL=$((FAIL+1)); }

check_rc()
{
    LABEL="$1"; shift
    EXPECTED="$1"; shift
    "$@" > /dev/null 2>&1
    RC=$?
    case " $EXPECTED " in
        *" $RC "*)
            t_ok "$LABEL"
            ;;
        *)
            t_ko "$LABEL" "rc=$RC attendu:$EXPECTED"
            ;;
    esac
}

main()
{
    echo ""
    echo "=== RK322X SELFTEST ==="

    echo ""
    echo "--- Modules ---"

    FOUND=0
    for B in "$BASE/core" /data/scripts/core; do
        [ -f "$B/runlog.sh" ] && [ -f "$B/config.sh" ] && FOUND=1 && break
    done
    if [ "$FOUND" -eq 1 ]; then
        t_ok "modules core (runlog, config)"
    else
        t_ko "modules core (runlog, config)" "introuvables"
    fi

    echo ""
    echo "--- Cle USB ---"

    USB_FOUND=""
    for d in /mnt/media_rw/*; do
        if [ -f "$d/deploy.sh" ]; then
            USB_FOUND="$d"
            break
        fi
    done
    if [ -n "$USB_FOUND" ]; then
        t_ok "cle USB detectee ($USB_FOUND)"
    else
        t_ko "cle USB detectee" "aucune"
    fi

    echo ""
    echo "--- Outils ---"

    check_rc "help"                "0" sh "$BASE/help.sh"
    check_rc "check_state"         "0 1" sh "$BASE/check_state.sh"
    check_rc "inspect_system"      "0" sh "$BASE/inspect_system.sh"
    check_rc "inspect_services"    "0" sh "$BASE/inspect_services.sh"
    check_rc "device_info"         "0" sh "$BASE/device_info.sh"
    check_rc "conf_check"          "0" sh "$BASE/conf_check.sh"
    check_rc "run_state"           "0" sh "$BASE/run_state.sh"
    check_rc "inspect_gui STATUS"  "0" sh "$BASE/inspect_gui.sh" STATUS
    check_rc "thermal STATUS"      "0" sh "$BASE/thermal.sh" STATUS
    check_rc "vitals STATUS"       "0" sh "$BASE/vitals.sh" STATUS
    check_rc "mem_tune STATUS"     "0" sh "$BASE/mem_tune.sh" STATUS
    check_rc "cut_services STATUS" "0" sh "$BASE/cut_services.sh" STATUS
    check_rc "system_rw STATUS"    "0" sh "$BASE/system_rw.sh" STATUS
    check_rc "motd STATUS"         "0" sh "$BASE/motd.sh" STATUS
    check_rc "net_diag"            "0 1" sh "$BASE/net_diag.sh"
    check_rc "sys_diag"            "0 1" sh "$BASE/sys_diag.sh"
    check_rc "sd_inspect"          "0 1 2" sh "$BASE/sd_inspect.sh"
    check_rc "set_time STATUS"     "0" sh "$BASE/set_time.sh" STATUS
    check_rc "sync_usb STATUS"     "0 1" sh "$BASE/sync_usb.sh" STATUS
    check_rc "disable_wireless ST" "0" sh "$BASE/disable_wireless.sh" STATUS
    check_rc "front_led STATUS"    "0" sh "$BASE/front_led.sh" STATUS
    SSH_SH=""
    for C in "$BASE/server/ssh_server.sh" "$BASE/../server/ssh_server.sh" \
             "/data/scripts/server/ssh_server.sh"; do
        [ -f "$C" ] && { SSH_SH="$C"; break; }
    done
    if [ -n "$SSH_SH" ]; then
        check_rc "ssh_server STATUS"   "0 1" sh "$SSH_SH" STATUS
    else
        t_ko "ssh_server STATUS" "script introuvable (deploy INSTALL)"
    fi
    check_rc "amorce"              "0" sh "$BASE/amorce.sh"
    check_rc "boot HELP"           "0" sh "$BASE/boot.sh" HELP
    check_rc "boot STATUS"         "0 1" sh "$BASE/boot.sh" STATUS
    check_rc "reboot HELP"         "0" sh "$BASE/reboot.sh" HELP
    check_rc "reboot STATUS"       "0" sh "$BASE/reboot.sh" STATUS
    check_rc "remote_map HELP"     "0" sh "$BASE/remote_map.sh" HELP
    check_rc "front_digit HELP"    "0" sh "$BASE/front_digit.sh" HELP
    check_rc "front_digit STATUS"  "0" sh "$BASE/front_digit.sh" STATUS
    check_rc "investigate HELP"    "0" sh "$BASE/investigate.sh" HELP
    check_rc "stress_ram HELP"     "0" sh "$BASE/stress_ram.sh" HELP
    check_rc "stress_ram STATUS"   "0 1" sh "$BASE/stress_ram.sh" STATUS
    check_rc "crowdsec HELP"          "0 1" sh "$BASE/crowdsec.sh" HELP
    check_rc "capture HELP"          "0 1" sh "$BASE/capture.sh" HELP
    check_rc "net_watch HELP"          "0 1" sh "$BASE/net_watch.sh" HELP
    check_rc "rotate_logs"         "0 1" sh "$BASE/rotate_logs.sh"
    check_rc "media"               "0" sh "$BASE/core/media.sh"
    check_rc "hdmi STATUS"         "0" sh "$BASE/hdmi.sh" STATUS

    if [ -f "$SCRIPTS_DIR_DEPLOY" ] || [ -f "/data/scripts/deploy.sh" ]; then
        DEPLOY_SH="/data/scripts/deploy.sh"
    elif [ -n "$USB_FOUND" ]; then
        DEPLOY_SH="$USB_FOUND/deploy.sh"
    fi
    if [ -n "$DEPLOY_SH" ] && [ -f "$DEPLOY_SH" ]; then
        check_rc "deploy HELP"     "0" sh "$DEPLOY_SH"
    else
        t_ko "deploy HELP" "deploy.sh introuvable"
    fi

    echo ""
    echo "=== RESUME ==="
    printf '  PASS : %-4s FAIL : %s\n' "$PASS" "$FAIL"
    echo ""

    if [ "$FAIL" -eq 0 ]; then
        return 0
    fi
    return 1
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
