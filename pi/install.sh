#!/bin/bash
# =============================================================================
#  HamBridge installer — tarball-based, fully local
# =============================================================================

set -e

# ── Helper functions ─────────────────────────────────────────────────────────
hb_on_error() {
    local line="$1"
    echo ""
    echo -e "\033[0;31m[ERROR]\033[0m Installation failed at line $line."
    echo -e "\033[0;31m[ERROR]\033[0m Check the output above for details."
    echo ""
    echo "  To see more detail, re-run with:"
    echo "    sudo bash -x install.sh"
    echo ""
}
trap 'hb_on_error $LINENO' ERR

hb_try() { "$@" || true; }

hb_info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
hb_step() { echo -e "\n\033[1;32m==> $*\033[0m"; }

# ── Locate repo directory ────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HB_REPO_DIR="$SCRIPT_DIR"
export HB_REPO_DIR

# ── Root check ───────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Please run as root: sudo bash install.sh"
    exit 1
fi

# ── Detect install user ───────────────────────────────────────────────────────
HB_INSTALL_USER="${SUDO_USER:-pi}"
export HB_INSTALL_USER

HB_INSTALL_HOME=$(eval echo ~"$HB_INSTALL_USER")
export HB_INSTALL_HOME

# ── Load shared config and libraries ─────────────────────────────────────────
source "$HB_REPO_DIR/pi/lib/config.sh"
source "$HB_REPO_DIR/pi/lib/packages.sh"
source "$HB_REPO_DIR/pi/lib/udev.sh"
source "$HB_REPO_DIR/pi/lib/daemon.sh"
source "$HB_REPO_DIR/pi/lib/systemd.sh"
source "$HB_REPO_DIR/pi/lib/bluetooth.sh"

# ── Banner ───────────────────────────────────────────────────────────────────
echo -e "${HB_BOLD}${HB_CYAN}"
echo "  ██╗  ██╗ █████╗ ███╗   ███╗██████╗ ██████╗ ██╗██████╗  ██████╗ ███████╗"
echo "  ██║  ██║██╔══██╗████╗ ████║██╔══██╗██╔══██╗██║██╔══██╗██╔════╝ ██╔════╝"
echo "  ███████║███████║██╔████╔██║██████╔╝██████╔╝██║██║  ██║██║  ███╗█████╗  "
echo "  ██╔══██║██╔══██║██║╚██╔╝██║██╔══██╗██╔══██╗██║██║  ██║██║   ██║██╔══╝  "
echo "  ██║  ██║██║  ██║██║ ╚═╝ ██║██████╔╝██║  ██║██║██████╔╝╚██████╔╝███████╗"
echo "  ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝╚═════╝ ╚═╝  ╚═╝╚═╝╚═════╝  ╚═════╝ ╚══════╝"
echo -e "${HB_NC}"
echo -e "  ${HB_CYAN}Ham Radio Recorder Bridge — Installer v1.0${HB_NC}"
echo ""
hb_info "Installing for user: $HB_INSTALL_USER"
hb_info "Install directory:   $HB_INSTALL_DIR"

# ── Confirm before making any changes ────────────────────────────────────────
hb_step "Configuration"
echo ""
echo -e "  ${HB_BOLD}Ready to install with these settings:${HB_NC}"
echo ""
echo "    Bluetooth name:  HamBridge"
echo "    CAT device:      /dev/hambridge"
echo "    Install user:    $HB_INSTALL_USER"
echo "    Install dir:     $HB_INSTALL_DIR"
echo "    Interfaces:      DR-891 and Digirig Mobile (both supported)"
echo ""
read -rp "  Proceed? [y/N]: " HB_CONFIRM
[[ "$HB_CONFIRM" =~ ^[Yy]$ ]] || { hb_info "Aborted — no changes made."; exit 0; }

# ── Run installation steps ──────────────────────────────────────────────────
hb_install_packages
hb_install_udev
hb_install_daemon
hb_install_systemd
hb_configure_bluetooth

cp "$HB_REPO_DIR/pi/diagnose.sh"  "$HB_DIAGNOSE_SCRIPT"
cp "$HB_REPO_DIR/pi/uninstall.sh" "$HB_UNINSTALL_SCRIPT"
chmod +x "$HB_DIAGNOSE_SCRIPT" "$HB_UNINSTALL_SCRIPT"
chown "$HB_INSTALL_USER:$HB_INSTALL_USER" \
    "$HB_DIAGNOSE_SCRIPT" "$HB_UNINSTALL_SCRIPT"

hb_try hb_start_service

# ── Summary ───────────────────────────────────────────────────────────────
echo ""
echo -e "${HB_BOLD}${HB_GREEN}════════════════════════════════════════${HB_NC}"
echo -e "${HB_BOLD}${HB_GREEN}  HamBridge installation complete!${HB_NC}"
echo -e "${HB_BOLD}${HB_GREEN}════════════════════════════════════════${HB_NC}"
echo ""
echo -e "  ${HB_BOLD}Bluetooth name:${HB_NC} $HB_BT_NAME"
echo -e "  ${HB_BOLD}Install dir:${HB_NC}    $HB_INSTALL_DIR"
echo ""
echo -e "  ${HB_BOLD}Useful commands:${HB_NC}"
echo ""
echo -e "  Service status:  ${HB_CYAN}sudo systemctl status hambridge${HB_NC}"
echo -e "  Live logs:       ${HB_CYAN}sudo journalctl -u hambridge -f${HB_NC}"
echo -e "  Diagnostics:     ${HB_CYAN}bash $HB_DIAGNOSE_SCRIPT${HB_NC}"
echo -e "  Uninstall:       ${HB_CYAN}bash $HB_UNINSTALL_SCRIPT${HB_NC}"
echo ""
echo -e "  ${HB_BOLD}Next steps:${HB_NC}"
echo ""
echo -e "  1. Connect hardware (radio + interface + Pi)"
echo -e "  2. Reboot:           ${HB_CYAN}sudo reboot${HB_NC}"
echo -e "  3. Pair phone to '${HB_BT_NAME}' in Android Bluetooth settings"
echo -e "  4. Open HamBridge app → Settings → select your radio"
echo -e "  5. Run diagnostics to confirm everything is working"
echo ""