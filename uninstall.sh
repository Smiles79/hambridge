#!/bin/bash
# =============================================================================
#  uninstall.sh
#  Cleanly removes everything the HamBridge installer created.
#  System packages (hamlib, bluez, etc.) are left in place since they
#  may be used by other software.
#
#  Usage: bash ~/hambridge/uninstall.sh
# =============================================================================

HB_RED='\033[0;31m'
HB_GREEN='\033[0;32m'
HB_YELLOW='\033[1;33m'
HB_CYAN='\033[0;36m'
HB_BOLD='\033[1m'
HB_NC='\033[0m'

echo ""
echo -e "${HB_BOLD}HamBridge Uninstaller${HB_NC}"
echo ""
echo -e "${HB_YELLOW}This will remove:${HB_NC}"
echo "  - hambridge systemd service"
echo "  - /etc/udev/rules.d/99-hamradio.rules"
echo "  - ~/hambridge/ directory (including hambridge.py and settings)"
echo ""
echo -e "${HB_CYAN}System packages will NOT be removed.${HB_NC}"
echo ""
read -rp "Proceed? [y/N]: " HB_CONFIRM
[[ "$HB_CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

echo ""

# ── Stop and disable service ──────────────────────────────────────────────────
echo -n "Stopping hambridge service ... "
sudo systemctl stop hambridge 2>/dev/null && echo "stopped" || echo "not running"

echo -n "Disabling hambridge service ... "
sudo systemctl disable hambridge 2>/dev/null && echo "disabled" || echo "not enabled"

echo -n "Removing service file ... "
sudo rm -f /etc/systemd/system/hambridge.service
sudo systemctl daemon-reload
echo "done"

# ── Remove udev rule ──────────────────────────────────────────────────────────
echo -n "Removing udev rule ... "
sudo rm -f /etc/udev/rules.d/99-hamradio.rules
sudo udevadm control --reload-rules
sudo udevadm trigger
echo "done"

# ── Remove install directory ──────────────────────────────────────────────────
HB_INSTALL_DIR="$(cd "$(dirname "$0")" && pwd)"
echo -n "Removing $HB_INSTALL_DIR ... "
rm -rf "$HB_INSTALL_DIR"
echo "done"

echo ""
echo -e "${HB_GREEN}HamBridge has been uninstalled.${HB_NC}"
echo ""
echo "System packages were left in place."
echo "To also remove them:"
echo "  sudo apt remove hamlib-utils python3-bluetooth bluez alsa-utils"
echo ""
