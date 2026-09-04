#!/usr/bin/env bash
# modules/03_kiosk.sh
# Auto-starts Waydroid + RoboticBell at boot.
# Includes pre-warm service so Android boots in parallel with Linux
# (this gives the fastest possible startup).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00_common.sh"

section "Module 3: Kiosk auto-launch + speedup"

require_user "${KIOSK_USER}"

# ============================================================
# Part A: Make Waydroid container start AT BOOT (not on demand)
# This is the biggest single speedup - Android boots in parallel
# with Linux startup.
# ============================================================

log "Making waydroid-container start at boot..."
sudo systemctl enable waydroid-container >/dev/null 2>&1 || true

sudo mkdir -p /etc/systemd/system/waydroid-container.service.d/
sudo tee /etc/systemd/system/waydroid-container.service.d/override.conf > /dev/null <<'EOF'
[Unit]
Wants=network.target
After=network.target
DefaultDependencies=yes

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
ok "Waydroid container set to start at boot"

# ============================================================
# Part B: Pre-warm service - boots Android during Linux boot
# ============================================================

log "Installing pre-warm service..."

sudo tee /usr/local/bin/waydroid-prewarm.sh > /dev/null <<'EOF'
#!/bin/bash
# Pre-warm: start Android boot in parallel with Linux boot
set -e
for i in {1..30}; do
    systemctl is-active --quiet waydroid-container && break
    sleep 1
done
sudo systemctl start waydroid-container || true
for i in {1..90}; do
    if /usr/bin/waydroid shell -- getprop sys.boot_completed 2>/dev/null | grep -q 1; then
        echo "Android pre-warmed and ready"
        exit 0
    fi
    sleep 2
done
exit 0
EOF
sudo chmod +x /usr/local/bin/waydroid-prewarm.sh

sudo tee /etc/systemd/system/waydroid-prewarm.service > /dev/null <<EOF
[Unit]
Description=Pre-warm Waydroid Android at boot
After=waydroid-container.service network.target
Requires=waydroid-container.service
Before=gdm.service display-manager.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/waydroid-prewarm.sh
RemainAfterExit=yes
TimeoutSec=180

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable waydroid-prewarm.service >/dev/null 2>&1
ok "Pre-warm service installed (Android boots during Linux boot)"

# ============================================================
# Part C: Kiosk launcher script
# This runs AFTER user login. Android is already booted, so this just
# attaches the Wayland UI and launches the RoboticBell app.
# ============================================================

log "Installing kiosk launcher script..."

sudo tee /usr/local/bin/start-roboticbell-kiosk.sh > /dev/null <<EOF
#!/bin/bash
# Fast kiosk launcher - Android is already pre-warmed.
set -e

# Start Waydroid session (attaches Android to user's Wayland display)
/usr/bin/waydroid session start &
SESSION_PID=\$!

# Quick check that Android is ready (should be, thanks to pre-warm)
for i in {1..30}; do
    if /usr/bin/waydroid shell -- getprop sys.boot_completed 2>/dev/null | grep -q 1; then
        break
    fi
    sleep 1
done

# Open the Android UI full-screen
/usr/bin/waydroid show-full-ui &
sleep 2

# Launch the RoboticBell app
/usr/bin/waydroid app launch ${ROBOTIC_BELL_PACKAGE}

# Keep service alive
wait \${SESSION_PID}
EOF
sudo chmod +x /usr/local/bin/start-roboticbell-kiosk.sh
ok "Kiosk launcher installed"

# ============================================================
# Part D: User systemd service to run the launcher at login
# ============================================================

log "Installing user systemd service..."
USER_SYSTEMD_DIR="${HOME}/.config/systemd/user"
mkdir -p "${USER_SYSTEMD_DIR}"

cat > "${USER_SYSTEMD_DIR}/roboticbell-kiosk.service" <<EOF
[Unit]
Description=RoboticBell kiosk auto-launch
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/local/bin/start-roboticbell-kiosk.sh
ExecStop=/usr/bin/waydroid session stop
Restart=always
RestartSec=10

[Install]
WantedBy=graphical-session.target
EOF

# Enable user lingering so user services can start before manual login
sudo loginctl enable-linger "${KIOSK_USER}"

systemctl --user daemon-reload
systemctl --user enable roboticbell-kiosk.service
ok "Kiosk service enabled (will auto-start at login)"

# ============================================================
# Part E: Small system tweaks for faster boot
# ============================================================

log "Disabling GNOME animations and unused services for faster boot..."
gsettings set org.gnome.desktop.interface enable-animations false 2>/dev/null || true

# Disable services not needed on a robot
for svc in apport.service bluetooth.service cups.service cups-browsed.service \
           ModemManager.service avahi-daemon.service unattended-upgrades.service; do
    sudo systemctl disable "${svc}" 2>/dev/null || true
done

# Hide GRUB boot menu
if [[ -f /etc/default/grub ]]; then
    sudo cp /etc/default/grub /etc/default/grub.bak.$(date +%Y%m%d_%H%M%S)
    sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
    if grep -q "^GRUB_TIMEOUT_STYLE" /etc/default/grub; then
        sudo sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' /etc/default/grub
    else
        echo "GRUB_TIMEOUT_STYLE=hidden" | sudo tee -a /etc/default/grub > /dev/null
    fi
    sudo update-grub 2>/dev/null || true
fi
ok "Boot optimizations applied"

ok "Module 3 complete"
