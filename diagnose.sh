#!/usr/bin/env bash
# diagnose.sh - troubleshoot a deployed RoboticBell kiosk
#
# Usage:
#   ./diagnose.sh           Check everything, print report
#   ./diagnose.sh --fix     Check and attempt auto-fix
#   ./diagnose.sh --report  Save logs + configs for remote support

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

MODE="check"
case "${1:-}" in
    --fix)    MODE="fix" ;;
    --report) MODE="report" ;;
    --help|-h)
        cat <<EOF
RoboticBell Kiosk Diagnostic Tool

Usage:
  ./diagnose.sh              Check all systems, show report
  ./diagnose.sh --fix        Check AND attempt safe automatic repairs
  ./diagnose.sh --report     Save support bundle (logs, configs) to /tmp/
  ./diagnose.sh --help       Show this help
EOF
        exit 0 ;;
esac

TOTAL=0; PASSED=0; FAILED=0; FIXED=0
declare -a ISSUES=()

header() {
    echo ""
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}  $*${NC}"
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════${NC}"
}

check_start() {
    TOTAL=$((TOTAL + 1))
    printf "  ${CYAN}[%02d]${NC} %-55s " "${TOTAL}" "$1"
}

pass() { PASSED=$((PASSED + 1)); echo -e "${GREEN}PASS${NC}"; }

fail() {
    FAILED=$((FAILED + 1))
    echo -e "${RED}FAIL${NC}"
    local issue="$1" cause="$2" fix="$3" auto="${4:-}"
    ISSUES+=("${TOTAL}|${issue}|${fix}")
    echo -e "       ${YELLOW}Issue:${NC}  ${issue}"
    echo -e "       ${YELLOW}Cause:${NC}  ${cause}"
    echo -e "       ${YELLOW}Fix:${NC}    ${fix}"
    if [[ "${MODE}" == "fix" && -n "${auto}" ]]; then
        echo -e "       ${BLUE}Auto-fixing...${NC}"
        if eval "${auto}" 2>&1 | sed 's/^/         /'; then
            echo -e "       ${GREEN}Auto-fix applied${NC}"
            FIXED=$((FIXED + 1))
        else
            echo -e "       ${RED}Auto-fix failed${NC}"
        fi
    fi
}

warn() { echo -e "${YELLOW}WARN${NC}  $*"; }

# ============================================================
# REPORT MODE
# ============================================================
if [[ "${MODE}" == "report" ]]; then
    DIR="/tmp/roboticbell-diag-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "${DIR}"
    echo "Collecting diagnostic bundle..."

    {
        echo "=== System ==="; uname -a; cat /etc/os-release 2>/dev/null
        echo "=== Uptime ==="; uptime
        echo "=== Memory ==="; free -h
        echo "=== Disk ==="; df -h
        echo "=== Session ==="; echo "USER=$(whoami) XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-unset}"
    } > "${DIR}/system.txt" 2>&1

    {
        echo "=== lsusb ==="; lsusb
        echo "=== /dev/bus/usb ==="; ls -la /dev/bus/usb/ 2>/dev/null
        echo "=== Loaded cdc modules ==="; lsmod | grep -i cdc
    } > "${DIR}/usb.txt" 2>&1

    {
        echo "=== waydroid status ==="; waydroid status 2>&1
        echo "=== Container ==="; sudo systemctl status waydroid-container --no-pager 2>&1
        echo "=== Pre-warm ==="; sudo systemctl status waydroid-prewarm --no-pager 2>&1
        echo "=== USB feature ==="; waydroid shell -- pm list features 2>/dev/null | grep usb
        echo "=== Packages ==="; waydroid shell -- pm list packages 2>/dev/null
        echo "=== boot_completed ==="; waydroid shell -- getprop sys.boot_completed 2>/dev/null
        echo "=== Properties ==="
        waydroid prop get persist.waydroid.udev
        waydroid prop get persist.waydroid.uevent
    } > "${DIR}/waydroid.txt" 2>&1

    sudo journalctl -u waydroid-container --no-pager -n 200 > "${DIR}/jrn-container.txt" 2>&1
    sudo journalctl -u waydroid-prewarm --no-pager -n 200 > "${DIR}/jrn-prewarm.txt" 2>&1
    journalctl --user -u roboticbell-kiosk --no-pager -n 200 > "${DIR}/jrn-kiosk.txt" 2>&1
    sudo cp /var/lib/waydroid/waydroid.log "${DIR}/waydroid.log" 2>/dev/null
    dmesg | tail -200 > "${DIR}/dmesg.txt" 2>&1

    sudo cat /etc/gdm3/custom.conf > "${DIR}/gdm.conf" 2>&1
    sudo cat /etc/udev/rules.d/99-esp32-waydroid.rules > "${DIR}/esp32.rules" 2>&1
    cat /etc/modprobe.d/blacklist-cdc-acm.conf > "${DIR}/cdc-blacklist.conf" 2>&1

    "$0" > "${DIR}/check-report.txt" 2>&1

    BUNDLE="/tmp/roboticbell-diag-$(date +%Y%m%d_%H%M%S).tar.gz"
    tar czf "${BUNDLE}" -C /tmp "$(basename ${DIR})"
    rm -rf "${DIR}"

    echo ""
    echo -e "${GREEN}Bundle saved to: ${BUNDLE}${NC}"
    echo "Send to support@vrobotics.in"
    exit 0
fi

# ============================================================
# Header
# ============================================================
clear
cat <<'EOF'
  ____       _           _   _      ____       _ _
 |  _ \ ___ | |__   ___ | |_(_) ___| __ )  ___| | |
 | |_) / _ \| '_ \ / _ \| __| |/ __|  _ \ / _ \ | |
 |  _ < (_) | |_) | (_) | |_| | (__| |_) |  __/ | |
 |_| \_\___/|_.__/ \___/ \__|_|\___|____/ \___|_|_|

         Kiosk Diagnostic Tool
EOF
echo ""
[[ "${MODE}" == "fix" ]] && echo -e "${BOLD}${YELLOW}Mode: AUTO-FIX${NC}" || echo -e "${BOLD}${BLUE}Mode: CHECK ONLY${NC}"

sudo -n true 2>/dev/null || { echo "Some checks need sudo."; sudo -v; }

# ============================================================
# Section 1: Environment
# ============================================================
header "1. Environment"

check_start "Running as non-root user"
[[ $EUID -ne 0 ]] && pass || fail "Running as root" "Use kiosk user" "Run as the kiosk user, not root"

check_start "Wayland session active"
if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then pass
else fail "Not in Wayland (got ${XDG_SESSION_TYPE:-empty})" "Waydroid needs Wayland" "Log out, choose Ubuntu on Wayland at GDM"
fi

check_start "Required commands present"
M=""
for c in waydroid systemctl gsettings zenity; do command -v "$c" >/dev/null || M="${M} ${c}"; done
[[ -z "${M}" ]] && pass || fail "Missing:${M}" "Packages not installed" "sudo apt install -y${M}" "sudo apt install -y${M}"

check_start "Disk space available (>=2GB free)"
FREE=$(df / --output=avail -BG | tail -1 | tr -d ' G')
[[ ${FREE:-0} -ge 2 ]] && pass || fail "Only ${FREE}GB free" "Low disk space" "sudo apt autoremove; journalctl --vacuum-size=100M"

check_start "RAM available (>=1.5GB free)"
FREE=$(free -m | awk 'NR==2{print $7}')
[[ ${FREE:-0} -ge 1500 ]] && pass || fail "Only ${FREE}MB free" "Low memory" "Close apps or add RAM"

# ============================================================
# Section 2: Waydroid
# ============================================================
header "2. Waydroid"

check_start "Waydroid installed"
command -v waydroid >/dev/null && pass || fail "Waydroid not installed" "Package missing" \
    "curl -L https://repo.waydro.id | sudo bash && sudo apt install waydroid && sudo waydroid init"

check_start "Container service enabled"
systemctl is-enabled waydroid-container >/dev/null 2>&1 && pass || \
    fail "waydroid-container not enabled" "Won't auto-start" "sudo systemctl enable waydroid-container" \
    "sudo systemctl enable waydroid-container"

check_start "Container service running"
systemctl is-active waydroid-container >/dev/null 2>&1 && pass || \
    fail "Container not running" "Stopped" "sudo systemctl start waydroid-container" \
    "sudo systemctl start waydroid-container"

check_start "vendor.img exists and valid"
if [[ -f /var/lib/waydroid/images/vendor.img ]]; then
    SZ=$(stat -c%s /var/lib/waydroid/images/vendor.img)
    [[ ${SZ} -gt 100000000 ]] && pass || fail "vendor.img truncated (${SZ} bytes)" "Corrupted" "sudo waydroid init -f"
else
    fail "vendor.img missing" "Waydroid not initialized" "sudo waydroid init"
fi

check_start "Android boot completed"
BOOT=$(waydroid shell -- getprop sys.boot_completed 2>/dev/null | tr -d '\r\n ')
[[ "${BOOT}" == "1" ]] && pass || \
    fail "Android not booted (got '${BOOT:-empty}')" "Still booting OR container stopped" \
    "Wait 60 sec and re-check. If still failing: sudo systemctl restart waydroid-container"

# ============================================================
# Section 3: USB
# ============================================================
header "3. USB Passthrough"

check_start "ESP32 detected by host"
lsusb | grep -qi "303a:4001" && pass || \
    fail "ESP32 not in lsusb" "Cable issue or device unpowered" "Check USB cable, try different port"

check_start "USB host feature flag in Android"
N=$(waydroid shell -- pm list features 2>/dev/null | grep -c usb.host)
[[ ${N} -ge 1 ]] && pass || \
    fail "android.hardware.usb.host not declared" "vendor.img modification missing" \
    "cd ~/roboticbell-kiosk && bash modules/01_waydroid_usb.sh" \
    "cd ~/roboticbell-kiosk 2>/dev/null && bash modules/01_waydroid_usb.sh"

check_start "uevent forwarding enabled"
V=$(waydroid prop get persist.waydroid.uevent 2>/dev/null | tr -d '\r\n ')
[[ "${V}" == "true" ]] && pass || \
    fail "persist.waydroid.uevent not true (got '${V:-empty}')" "Hotplug not forwarded to Android" \
    "waydroid prop set persist.waydroid.uevent true && waydroid prop set persist.waydroid.udev true" \
    "waydroid prop set persist.waydroid.uevent true && waydroid prop set persist.waydroid.udev true"

check_start "udev rule installed"
[[ -f /etc/udev/rules.d/99-esp32-waydroid.rules ]] && pass || \
    fail "ESP32 udev rule missing" "Device node has root-only perms" \
    "cd ~/roboticbell-kiosk && bash modules/01_waydroid_usb.sh" \
    "cd ~/roboticbell-kiosk 2>/dev/null && bash modules/01_waydroid_usb.sh"

check_start "cdc_acm NOT loaded"
lsmod | grep -q cdc_acm && \
    fail "cdc_acm is loaded" "May claim ESP32 before Android can" \
    "sudo modprobe -r cdc_acm" "sudo modprobe -r cdc_acm 2>/dev/null" || pass

check_start "ESP32 visible inside Waydroid"
N=$(waydroid shell -- ls /dev/bus/usb/ 2>/dev/null | wc -l)
[[ ${N} -ge 1 ]] && pass || \
    fail "No USB devices in container" "USB host feature missing OR no replug since boot" \
    "Unplug and replug the ESP32, wait 3 sec, re-check"

# ============================================================
# Section 4: RoboticBell app
# ============================================================
header "4. RoboticBell App"

check_start "RoboticBell APK installed in Waydroid"
waydroid shell -- pm list packages 2>/dev/null | grep -q "com.vrobotics.roboticbell" && pass || \
    fail "com.vrobotics.roboticbell not installed" "APK never installed" \
    "Download from https://roboticbell.vrobotics.in/downloads/ then: waydroid app install /path/to/RoboticBell.apk"

check_start "Teacher password set"
[[ -f /etc/v-robotics/teacher.hash ]] && pass || \
    fail "Teacher password file missing" "Ctrl+Alt+Q will show error" \
    "cd ~/roboticbell-kiosk && ./install.sh (prompts for password)"

check_start "Teacher shutdown script installed"
[[ -x /usr/local/bin/teacher-shutdown.sh ]] && pass || \
    fail "/usr/local/bin/teacher-shutdown.sh missing" "Ctrl+Alt+Q won't work" \
    "cd ~/roboticbell-kiosk && bash modules/04_teacher_control.sh"

# ============================================================
# Section 5: Auto-start chain
# ============================================================
header "5. Auto-start Chain"

check_start "GDM auto-login configured"
sudo grep -qE "^AutomaticLogin\s*=\s*v-robotics" /etc/gdm3/custom.conf 2>/dev/null && pass || \
    fail "GDM auto-login not configured" "Must manually log in" \
    "cd ~/roboticbell-kiosk && bash modules/02_autologin.sh"

check_start "Kiosk user service enabled"
systemctl --user is-enabled roboticbell-kiosk.service >/dev/null 2>&1 && pass || \
    fail "roboticbell-kiosk.service not enabled" "Won't auto-start at login" \
    "cd ~/roboticbell-kiosk && bash modules/03_kiosk.sh"

check_start "User lingering enabled"
loginctl show-user "$(whoami)" 2>/dev/null | grep -q "Linger=yes" && pass || \
    fail "User lingering not enabled" "Services may not start before login" \
    "sudo loginctl enable-linger $(whoami)" "sudo loginctl enable-linger $(whoami)"

check_start "Pre-warm service enabled (fast boot)"
systemctl is-enabled waydroid-prewarm.service >/dev/null 2>&1 && pass || \
    fail "Pre-warm service not installed" "Boot will be slower" \
    "cd ~/roboticbell-kiosk && bash modules/03_kiosk.sh"

# ============================================================
# Section 6: Power
# ============================================================
header "6. Power Management"

check_start "Suspend-to-RAM supported"
[[ -r /sys/power/state ]] && grep -qE "mem|deep" /sys/power/state 2>/dev/null && pass || \
    fail "Suspend not available" "BIOS may have S3 disabled" "Enable S3 Sleep in BIOS"

check_start "Power button = suspend"
[[ -f /etc/systemd/logind.conf.d/50-kiosk-power.conf ]] && \
    grep -q "HandlePowerKey=suspend" /etc/systemd/logind.conf.d/50-kiosk-power.conf && pass || \
    fail "Power button not set to suspend" "Daily wake won't be instant" \
    "cd ~/roboticbell-kiosk && bash modules/04_teacher_control.sh"

# ============================================================
# Summary
# ============================================================
header "Summary"

echo ""
echo -e "  Total checks: ${TOTAL}"
echo -e "  ${GREEN}Passed:${NC}       ${PASSED}"
echo -e "  ${RED}Failed:${NC}       ${FAILED}"
[[ "${MODE}" == "fix" ]] && echo -e "  ${BLUE}Auto-fixed:${NC}   ${FIXED}"
echo ""

if [[ ${FAILED} -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}All checks passed.${NC}"
    echo ""
    echo "If still having issues:"
    echo "  1. Unplug + replug ESP32"
    echo "  2. sudo reboot"
    echo "  3. ./diagnose.sh --report  (then email bundle to support)"
else
    echo -e "${RED}${BOLD}${FAILED} problem(s) found.${NC}"
    echo ""
    echo "Quick fixes:"
    for i in "${ISSUES[@]}"; do
        IFS='|' read -r n t f <<< "$i"
        echo -e "  ${RED}[$n]${NC} ${t}"
        echo -e "        ${BOLD}${f}${NC}"
        echo ""
    done
    [[ "${MODE}" != "fix" ]] && echo -e "${YELLOW}Try: ./diagnose.sh --fix${NC}"
    echo ""
    echo "For support: ./diagnose.sh --report"
fi
echo ""
exit ${FAILED}
