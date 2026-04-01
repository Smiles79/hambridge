#!/bin/bash
# =============================================================================
#  lib/config.sh
#  Shared configuration variables and helper functions.
#  All variables prefixed HB_ and functions prefixed hb_ to avoid
#  clashing with anything in the calling shell environment.
# =============================================================================

# ── Paths ─────────────────────────────────────────────────────────────────────
HB_INSTALL_DIR="$HB_INSTALL_HOME/hambridge"
HB_LIB_DIR="$HB_INSTALL_DIR/pi/lib"
HB_DAEMON_SCRIPT="$HB_INSTALL_DIR/pi/hambridge.py"
HB_DIAGNOSE_SCRIPT="$HB_INSTALL_DIR/pi/diagnose.sh"
HB_UNINSTALL_SCRIPT="$HB_INSTALL_DIR/pi/uninstall.sh"
HB_SERVICE_FILE="/etc/systemd/system/hambridge.service"
HB_UDEV_RULE_FILE="/etc/udev/rules.d/99-hamradio.rules"
HB_BT_CONF="/etc/bluetooth/main.conf"

# ── Service ───────────────────────────────────────────────────────────────────
HB_SERVICE_NAME="hambridge"
HB_CAT_DEVICE_ALIAS="hambridge"
HB_BT_NAME="HamBridge"

# ── Colours ───────────────────────────────────────────────────────────────────
HB_RED='\033[0;31m'
HB_GREEN='\033[0;32m'
HB_YELLOW='\033[1;33m'
HB_BLUE='\033[0;34m'
HB_CYAN='\033[0;36m'
HB_BOLD='\033[1m'
HB_NC='\033[0m'

# ── Logging helpers ───────────────────────────────────────────────────────────
hb_info()    { echo -e "${HB_CYAN}[INFO]${HB_NC}  $1"; }
hb_success() { echo -e "${HB_GREEN}[OK]${HB_NC}    $1"; }
hb_warn()    { echo -e "${HB_YELLOW}[WARN]${HB_NC}  $1"; }
hb_error()   { echo -e "${HB_RED}[ERROR]${HB_NC} $1"; exit 1; }
hb_step()    { echo -e "\n${HB_BOLD}${HB_BLUE}==>${HB_NC}${HB_BOLD} $1${HB_NC}"; }
