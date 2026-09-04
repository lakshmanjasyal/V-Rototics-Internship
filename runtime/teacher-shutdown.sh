#!/usr/bin/env bash
# runtime/teacher-shutdown.sh - installed to /usr/local/bin/
# Triggered by Ctrl+Alt+Q. Prompts for password, then shows action menu.
# Sleep is the recommended daily action (wakes in 3-5 sec).

set -euo pipefail

HASH_FILE="/etc/v-robotics/teacher.hash"

if [[ ! -r "${HASH_FILE}" ]]; then
    zenity --error --title="Configuration Error" \
        --text="Teacher password not configured.\nFile missing: ${HASH_FILE}" \
        --width=400
    exit 1
fi

STORED_HASH=$(cat "${HASH_FILE}" | tr -d '[:space:]')

PASS=$(zenity --password \
    --title="Teacher Authentication" \
    --text="Enter teacher password:" \
    2>/dev/null) || exit 0

[[ -z "${PASS}" ]] && exit 0

INPUT_HASH=$(printf '%s' "${PASS}" | sha256sum | awk '{print $1}')

if [[ "${INPUT_HASH}" != "${STORED_HASH}" ]]; then
    zenity --error --title="Access Denied" \
        --text="Incorrect password.\nAttempt has been logged." \
        --width=300 2>/dev/null
    logger -t teacher-shutdown "Failed password attempt by user $(whoami)"
    exit 1
fi

CHOICE=$(zenity --list \
    --title="Robot Power Management" \
    --text="<b>Sleep is recommended for daily use</b>\n(wakes in 3-5 seconds)" \
    --column="Action" --column="Description" \
    "Sleep"     "RECOMMENDED - Quick wake when needed" \
    "Restart"   "Reboot the robot (takes ~30 sec)" \
    "Shut Down" "Turn OFF completely (weekly use only)" \
    "Cancel"    "Return to RoboticBell" \
    --width=520 --height=300 \
    --hide-header 2>/dev/null) || exit 0

case "${CHOICE}" in
    "Sleep")
        systemctl suspend ;;
    "Restart")
        zenity --question --title="Confirm Restart" \
            --text="Restart will take about 30 seconds.\nAre you sure?" \
            --width=320 2>/dev/null && systemctl reboot ;;
    "Shut Down")
        zenity --question --title="Confirm Shutdown" \
            --text="Next power-on will take 30+ seconds.\nFor daily use, choose Sleep instead.\n\nReally shut down?" \
            --width=400 2>/dev/null && systemctl poweroff ;;
    *)
        exit 0 ;;
esac
