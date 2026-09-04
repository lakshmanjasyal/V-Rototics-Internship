#!/usr/bin/env bash
# modules/02_autologin.sh
# Configures GDM3 auto-login so the robot reaches the desktop without a password.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00_common.sh"

section "Module 2: Auto-login for ${KIOSK_USER}"

GDM_CONF="/etc/gdm3/custom.conf"

[[ -f "${GDM_CONF}" ]] || die "${GDM_CONF} not found. Is GDM3 installed?"
id "${KIOSK_USER}" >/dev/null 2>&1 || die "User '${KIOSK_USER}' does not exist"

sudo cp -a "${GDM_CONF}" "${GDM_CONF}.bak.$(date +%Y%m%d_%H%M%S)"
ok "Backed up ${GDM_CONF}"

log "Configuring auto-login..."
sudo python3 - "${GDM_CONF}" "${KIOSK_USER}" <<'PYEOF'
import sys, configparser
path, user = sys.argv[1], sys.argv[2]
cp = configparser.ConfigParser()
cp.optionxform = str
cp.read(path)
if 'daemon' not in cp:
    cp['daemon'] = {}
cp['daemon']['AutomaticLoginEnable'] = 'true'
cp['daemon']['AutomaticLogin'] = user
with open(path, 'w') as f:
    cp.write(f, space_around_delimiters=False)
PYEOF

if sudo grep -q "AutomaticLogin=${KIOSK_USER}" "${GDM_CONF}"; then
    ok "Auto-login configured for ${KIOSK_USER}"
else
    die "Auto-login verification failed"
fi

sudo systemctl set-default graphical.target >/dev/null 2>&1 || true
ok "Module 2 complete"
