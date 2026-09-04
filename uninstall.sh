#!/usr/bin/env bash
# uninstall.sh - reverts the RoboticBell kiosk installation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/modules/00_common.sh"

[[ $EUID -ne 0 ]] || die "Don't run as root. Run as '${KIOSK_USER}'."

read -rp "This will REVERT the RoboticBell kiosk. Continue? [y/N] " ans
[[ "${ans,,}" == "y" ]] || { echo "Cancelled"; exit 0; }

sudo -v

# Stop services
section "Stopping services"
systemctl --user stop roboticbell-kiosk.service 2>/dev/null || true
systemctl --user disable roboticbell-kiosk.service 2>/dev/null || true
waydroid session stop 2>/dev/null || true
sudo systemctl stop waydroid-container 2>/dev/null || true
sudo systemctl disable waydroid-prewarm.service 2>/dev/null || true

# Remove user systemd unit
rm -f "${HOME}/.config/systemd/user/roboticbell-kiosk.service"
systemctl --user daemon-reload

# Remove runtime scripts
section "Removing runtime files"
sudo rm -f /usr/local/bin/teacher-shutdown.sh
sudo rm -f /usr/local/bin/start-roboticbell-kiosk.sh
sudo rm -f /usr/local/bin/waydroid-prewarm.sh
sudo rm -f /etc/systemd/system/waydroid-prewarm.service
sudo rm -rf /etc/systemd/system/waydroid-container.service.d/
sudo rm -f /etc/udev/rules.d/99-esp32-waydroid.rules
sudo rm -f /etc/modprobe.d/blacklist-cdc-acm.conf
sudo rm -f /etc/systemd/logind.conf.d/50-kiosk-power.conf
sudo udevadm control --reload-rules
sudo systemctl daemon-reload
ok "Runtime files removed"

# Restore GNOME settings
section "Restoring GNOME settings"
gsettings set org.gnome.desktop.interface enable-animations true 2>/dev/null || true
gsettings set org.gnome.desktop.screensaver lock-enabled true 2>/dev/null || true
gsettings reset org.gnome.settings-daemon.plugins.power power-button-action 2>/dev/null || true
ok "GNOME settings restored"

# Restore GDM
section "Restoring GDM"
GDM_BAK=$(ls -t /etc/gdm3/custom.conf.bak.* 2>/dev/null | head -1 || true)
if [[ -n "${GDM_BAK}" && -f "${GDM_BAK}" ]]; then
    sudo cp "${GDM_BAK}" /etc/gdm3/custom.conf
    ok "GDM restored from ${GDM_BAK}"
else
    warn "No GDM backup found - edit /etc/gdm3/custom.conf manually if needed"
fi

# Restore GRUB
GRUB_BAK=$(ls -t /etc/default/grub.bak.* 2>/dev/null | head -1 || true)
if [[ -n "${GRUB_BAK}" && -f "${GRUB_BAK}" ]]; then
    sudo cp "${GRUB_BAK}" /etc/default/grub
    sudo update-grub 2>/dev/null || true
    ok "GRUB restored"
fi

# Restore vendor.img
section "Restoring vendor.img"
LATEST=$(ls -dt /var/lib/waydroid/backup_* 2>/dev/null | head -1 || true)
if [[ -n "${LATEST}" && -f "${LATEST}/vendor.img" ]]; then
    sudo cp -a "${LATEST}/vendor.img" /var/lib/waydroid/images/vendor.img
    ok "vendor.img restored"
fi

# Restart container for clean state
sudo systemctl start waydroid-container 2>/dev/null || true

ok "Uninstall complete. Reboot to fully revert."
