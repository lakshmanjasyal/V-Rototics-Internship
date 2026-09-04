#!/usr/bin/env bash
# install.sh - RoboticBell Kiosk installer (lean version)
#
# Runs 4 modules: USB passthrough, auto-login, kiosk auto-launch, teacher control.
# Idempotent: safe to re-run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/modules/00_common.sh"

# ----- Pre-flight -----
section "RoboticBell Kiosk Installer"

[[ $EUID -ne 0 ]] || die "Don't run as root. Run as '${KIOSK_USER}'."
require_user "${KIOSK_USER}"

if [[ "${XDG_SESSION_TYPE:-}" != "wayland" ]]; then
    warn "Not in Wayland session (got: ${XDG_SESSION_TYPE:-unset})"
    warn "Waydroid requires Wayland - install will continue but verify after reboot"
fi

require_cmd waydroid
require_cmd python3
require_cmd sha256sum

log "Acquiring sudo..."
sudo -v || die "sudo authentication failed"
( while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null ) &
KEEPALIVE=$!
trap 'kill ${KEEPALIVE} 2>/dev/null || true' EXIT

ok "Pre-flight checks passed"

# ----- Teacher password -----
section "Teacher password setup"
ensure_config_dir

if [[ -f "${HASH_FILE}" ]]; then
    read -rp "Teacher password is already set. Change it? [y/N] " ans
    [[ "${ans,,}" == "y" ]] && SET=1 || SET=0
else
    SET=1
fi

if [[ "${SET}" == "1" ]]; then
    while true; do
        read -rsp "Enter NEW teacher password: " p1; echo
        read -rsp "Confirm:                     " p2; echo
        [[ -z "${p1}" ]] && { err "Password cannot be empty"; continue; }
        [[ "${p1}" != "${p2}" ]] && { err "Passwords do not match"; continue; }
        if [[ ${#p1} -lt 6 ]]; then
            read -rp "Password is short - use anyway? [y/N] " ans
            [[ "${ans,,}" == "y" ]] || continue
        fi
        break
    done
    HASH=$(printf '%s' "${p1}" | sha256sum | awk '{print $1}')
    echo "${HASH}" | sudo tee "${HASH_FILE}" > /dev/null
    sudo chown root:"${KIOSK_USER}" "${HASH_FILE}"
    sudo chmod 640 "${HASH_FILE}"
    unset p1 p2
    ok "Teacher password saved"
fi

# ----- Run modules -----
MODULES=(
    "01_waydroid_usb.sh"
    "02_autologin.sh"
    "03_kiosk.sh"
    "04_teacher_control.sh"
)

for m in "${MODULES[@]}"; do
    bash "${SCRIPT_DIR}/modules/${m}" || die "Module ${m} failed"
done

# ----- Done -----
section "Installation complete"

cat <<EOF

Summary:
  Kiosk user:        ${KIOSK_USER}
  Auto-login:        ENABLED
  Waydroid:          auto-starts at boot (pre-warmed)
  RoboticBell:       auto-launches at login
  Power button:      = Suspend (3-5 sec wake)
  Teacher shortcut:  Ctrl+Alt+Q

Next step:
  sudo reboot

After reboot, expected behaviour:
  - System auto-logs in as ${KIOSK_USER}
  - Waydroid + RoboticBell appear in ~30-45 sec on first boot
  - Daily: press power button to sleep, press again to wake in 3-5 sec
  - Teachers press Ctrl+Alt+Q + password to manage power

If anything is wrong after reboot, run:
  ./diagnose.sh         (check what is broken)
  ./diagnose.sh --fix   (attempt auto-repair)
EOF
