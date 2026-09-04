#!/usr/bin/env bash
# modules/04_teacher_control.sh
# Installs the Ctrl+Alt+Q teacher dialog and configures the power button
# to suspend (not shutdown) for instant 3-5 second wake.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00_common.sh"

section "Module 4: Teacher control + instant wake"

require_user "${KIOSK_USER}"
require_cmd gsettings

# Install zenity if needed
if ! command -v zenity >/dev/null 2>&1; then
    sudo apt-get install -y zenity
fi

# ============================================================
# Part A: Install teacher dialog runtime script
# ============================================================
RUNTIME_SCRIPT="${SCRIPT_DIR}/../runtime/teacher-shutdown.sh"
TARGET_SCRIPT="/usr/local/bin/teacher-shutdown.sh"

[[ -f "${RUNTIME_SCRIPT}" ]] || die "Runtime script not found at ${RUNTIME_SCRIPT}"

log "Installing teacher shutdown dialog..."
sudo cp "${RUNTIME_SCRIPT}" "${TARGET_SCRIPT}"
sudo chmod +x "${TARGET_SCRIPT}"
ok "Teacher dialog installed"

# ============================================================
# Part B: Bind Ctrl+Alt+Q to the dialog
# ============================================================
log "Binding Ctrl+Alt+Q shortcut..."

SHORTCUT_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/roboticbell-shutdown/"
EXISTING=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null || echo "@as []")

if [[ "${EXISTING}" != *"roboticbell-shutdown"* ]]; then
    if [[ "${EXISTING}" == "@as []" || "${EXISTING}" == "[]" ]]; then
        NEW="['${SHORTCUT_PATH}']"
    else
        NEW="${EXISTING%]}, '${SHORTCUT_PATH}']"
    fi
    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "${NEW}"
fi

SCHEMA="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding"
gsettings set "${SCHEMA}:${SHORTCUT_PATH}" name "RoboticBell Teacher Shutdown"
gsettings set "${SCHEMA}:${SHORTCUT_PATH}" command "${TARGET_SCRIPT}"
gsettings set "${SCHEMA}:${SHORTCUT_PATH}" binding "<Control><Alt>q"
ok "Ctrl+Alt+Q shortcut bound"

# ============================================================
# Part C: Configure power button = suspend (instant wake)
# ============================================================
log "Configuring power button for instant-wake (suspend mode)..."

sudo mkdir -p /etc/systemd/logind.conf.d/
sudo tee /etc/systemd/logind.conf.d/50-kiosk-power.conf > /dev/null <<'EOF'
[Login]
HandlePowerKey=suspend
HandlePowerKeyLongPress=poweroff
HandleLidSwitch=suspend
HandleLidSwitchExternalPower=suspend
HandleSuspendKey=suspend
EOF

sudo systemctl restart systemd-logind 2>/dev/null || \
    warn "logind restart deferred - takes effect at next reboot"

gsettings set org.gnome.settings-daemon.plugins.power power-button-action 'suspend' 2>/dev/null || true
ok "Power button = Suspend (3-5 sec wake)"

# Verify suspend support
if [[ -r /sys/power/state ]] && grep -qE "mem|deep" /sys/power/state; then
    ok "Suspend-to-RAM verified supported by hardware"
else
    warn "Suspend-to-RAM may not be supported - check BIOS settings (S3 Sleep)"
fi

# Disable screen lock and idle suspend (would interrupt the kiosk display)
gsettings set org.gnome.desktop.screensaver lock-enabled false 2>/dev/null || true
gsettings set org.gnome.desktop.session idle-delay 0 2>/dev/null || true
ok "Idle screen lock disabled"

ok "Module 4 complete"
