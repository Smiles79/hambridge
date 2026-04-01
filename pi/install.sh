#!/bin/bash
# =============================================================================
#  install.sh
#  HamBridge installer — entry point.
# =============================================================================

set -e

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

# ── Locate repo dir (IMPROVED) ───────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"

if git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "==> Using LOCAL repository"
    HB_REPO_DIR="$SCRIPT_DIR"
else
    echo "==> Using REMOTE repository"

    BRANCH="${1:-main}"
    HB_REPO_DIR="/tmp/hambridge-install"

    rm -rf "$HB_REPO_DIR"
    mkdir -p "$HB_REPO_DIR"

    echo "Downloading HamBridge (branch: $BRANCH)..."
    curl -sSL "https://github.com/Smiles79/hambridge/archive/${BRANCH}.tar.gz" \
        -o /tmp/hambridge.tar.gz

    tar -xz -C "$HB_REPO_DIR" --strip-components=1 -f /tmp/hambridge.tar.gz
    rm -f /tmp/hambridge.tar.gz
fi

export HB_REPO_DIR

# ── Root check ────────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Please run as root: sudo bash install.sh"
    exit 1
fi

# ── Detect install user ───────────────────────────────────────────────────────
if [ -n "$SUDO_USER" ]; then
    export HB_INSTALL_USER="$SUDO_USER"
else
    export HB_INSTALL_USER="pi"
fi

export HB_INSTALL_HOME
HB_INSTALL_HOME=$(eval echo ~"$HB_INSTALL_USER")

# ── Load shared config ────────────────────────────────────────────────────────
source "$HB_REPO_DIR/pi/lib/config.sh"

# ── Banner ────────────────────────────────────────────────────────────────────
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

# =============================================================================
#  Confirm before making any changes
# =============================================================================
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

# =============================================================================
#  Run installation steps
# =============================================================================

source "$HB_REPO_DIR/pi/lib/packages.sh"
hb_install_packages

source "$HB_REPO_DIR/pi/lib/udev.sh"
hb_install_udev

source "$HB_REPO_DIR/pi/lib/daemon.sh"
hb_install_daemon

source "$HB_REPO_DIR/pi/lib/systemd.sh"
hb_install_systemd

source "$HB_REPO_DIR/pi/lib/bluetooth.sh"
hb_configure_bluetooth

cp "$HB_REPO_DIR/pi/diagnose.sh"  "$HB_DIAGNOSE_SCRIPT"
cp "$HB_REPO_DIR/pi/uninstall.sh" "$HB_UNINSTALL_SCRIPT"
chmod +x "$HB_DIAGNOSE_SCRIPT" "$HB_UNINSTALL_SCRIPT"
chown "$HB_INSTALL_USER:$HB_INSTALL_USER" \
    "$HB_DIAGNOSE_SCRIPT" "$HB_UNINSTALL_SCRIPT"

hb_try hb_start_service

# =============================================================================
#  Summary
# =============================================================================
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
