#!/usr/bin/env bash
# modules/00_common.sh - shared helpers (sourced, not run directly)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ----- Configurable constants -----
KIOSK_USER="v-robotics7"
ESP32_VID="303a"
ESP32_PID="4001"
ROBOTIC_BELL_PACKAGE="com.vrobotics.roboticbell"
CONFIG_DIR="/etc/v-robotics"
HASH_FILE="${CONFIG_DIR}/teacher.hash"

log()     { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
ok()      { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()     { echo -e "${RED}[ERROR]${NC} $*" >&2; }
section() { echo -e "\n${BOLD}${BLUE}===== $* =====${NC}\n"; }
die()     { err "$*"; exit 1; }

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

require_user() {
    if [[ "$(whoami)" != "$1" ]]; then
        die "Run as user '$1' (currently $(whoami))"
    fi
}

ensure_config_dir() {
    sudo mkdir -p "${CONFIG_DIR}"
    sudo chown root:"${KIOSK_USER}" "${CONFIG_DIR}" 2>/dev/null || true
    sudo chmod 750 "${CONFIG_DIR}"
}
