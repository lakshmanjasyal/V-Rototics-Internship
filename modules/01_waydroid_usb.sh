#!/usr/bin/env bash
# modules/01_waydroid_usb.sh
# Configures Waydroid so ESP32 USB device is accessible from Android apps.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00_common.sh"

section "Module 1: Waydroid USB passthrough"

VENDOR_IMG="/var/lib/waydroid/images/vendor.img"
MOUNT_POINT="/mnt/waydroid_vendor"

require_cmd waydroid
require_cmd e2fsck
require_cmd resize2fs
require_cmd tune2fs

# --- Backup ---
BACKUP="/var/lib/waydroid/backup_$(date +%Y%m%d_%H%M%S)"
log "Backing up vendor.img to ${BACKUP}"
sudo mkdir -p "${BACKUP}"
sudo cp -a "${VENDOR_IMG}" "${BACKUP}/vendor.img"
ok "Backup created"

# --- Set uevent forwarding properties (needs Waydroid running) ---
log "Setting uevent forwarding properties..."

if ! waydroid status 2>/dev/null | grep -q "Session:.*RUNNING"; then
    sudo systemctl start waydroid-container 2>/dev/null || true
    sleep 5
    waydroid session start >/dev/null 2>&1 &
    sleep 15
fi

waydroid prop set persist.waydroid.udev true
waydroid prop set persist.waydroid.uevent true
ok "Waydroid properties set"

# --- Stop Waydroid to modify vendor.img ---
log "Stopping Waydroid to modify vendor.img..."
waydroid session stop 2>/dev/null || true
sudo systemctl stop waydroid-container
sleep 3

sudo umount "${MOUNT_POINT}" 2>/dev/null || true

# Filesystem check and resize if needed
log "Checking vendor.img..."
sudo e2fsck -y -f "${VENDOR_IMG}" >/dev/null
FREE_BLOCKS=$(sudo tune2fs -l "${VENDOR_IMG}" | awk '/Free blocks:/ {print $3}')
if [[ "${FREE_BLOCKS}" -lt 1024 ]]; then
    log "Resizing vendor.img to 600M..."
    sudo resize2fs "${VENDOR_IMG}" 600M
fi

# Mount and inject the USB host feature flag
log "Mounting vendor.img and injecting USB host feature flag..."
sudo mkdir -p "${MOUNT_POINT}"
sudo mount -o loop "${VENDOR_IMG}" "${MOUNT_POINT}"

USB_HOST_XML="${MOUNT_POINT}/etc/permissions/android.hardware.usb.host.xml"
if [[ -f "${USB_HOST_XML}" ]]; then
    ok "USB host feature flag already present"
else
    sudo tee "${USB_HOST_XML}" > /dev/null <<'EOF'
<permissions>
    <feature name="android.hardware.usb.host"/>
</permissions>
EOF
    ok "USB host feature flag injected"
fi

sudo umount "${MOUNT_POINT}"
sudo e2fsck -y -f "${VENDOR_IMG}" >/dev/null
ok "vendor.img updated and verified"

# --- udev rule for ESP32 ---
log "Installing udev rule for ESP32..."
sudo tee "/etc/udev/rules.d/99-esp32-waydroid.rules" > /dev/null <<EOF
SUBSYSTEM=="usb", ATTR{idVendor}=="${ESP32_VID}", ATTR{idProduct}=="${ESP32_PID}", MODE="0666"
EOF
sudo udevadm control --reload-rules
sudo udevadm trigger
ok "udev rule installed"

# --- Blacklist cdc_acm ---
log "Blacklisting cdc_acm..."
sudo tee "/etc/modprobe.d/blacklist-cdc-acm.conf" > /dev/null <<'EOF'
blacklist cdc_acm
EOF
sudo modprobe -r cdc_acm 2>/dev/null || true
ok "cdc_acm blacklisted"

# Re-enable container
sudo systemctl enable waydroid-container >/dev/null 2>&1 || true
sudo systemctl start waydroid-container

ok "Module 1 complete"
