#!/bin/bash
# =============================================================================
#  install.sh
#  HamBridge installer — entry point.
#
#  Usage (from GitHub):
#    curl -sSL https://raw.githubusercontent.com/Smiles79/hambridge/main/install.sh \
#      | sudo bash
#
#  Usage (local copy):
#    sudo bash install.sh
#
#  What this script does:
#    1. Checks it is running as root
#    2. Works out who the real (non-root) user is
#    3. Sources lib/config.sh for shared variables and helpers
#    4. Asks which radio setup is being used
#    5. Asks for a Bluetooth device name
#    6. Confirms settings before making any changes
#    7. Calls each lib/ script in order to perform the installation
#    8. Prints a summary with useful commands
# =============================================================================

set -e  # exit immediately on any error

# ── Locate repo dir ───────────────────────────────────────────────────────────
# Determines whether we are running from a local checkout or being piped
# from curl. In both cases we end up with a full repo in HB_REPO_DIR before
# any other step runs.
#
# Detection: check if lib/config.sh exists alongside the current script.
# BASH_SOURCE[0] works whether the script is run directly or via sudo bash.
# When piped from curl, BASH_SOURCE[0] is empty so the -f test fails and
# we fall through to downloading the repo.

HB_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"

if [ -n "$HB_SCRIPT_DIR" ] && [ -f "$HB_SCRIPT_DIR/lib/config.sh" ]; then
    # Running from a local copy that has the full repo structure
    HB_REPO_DIR="$HB_SCRIPT_DIR"
else
    # No local lib/ found — download the full repo from GitHub
    HB_REPO_DIR="/tmp/hambridge-install"
    rm -rf "$HB_REPO_DIR"
    mkdir -p "$HB_REPO_DIR"
    echo "Downloading HamBridge..."
    curl -sSL https://github.com/Smiles79/hambridge/archive/main.tar.gz \
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
# If invoked via sudo, install files for the original user not root
if [ -n "$SUDO_USER" ]; then
    export HB_INSTALL_USER="$SUDO_USER"
else
    export HB_INSTALL_USER="pi"
fi
export HB_INSTALL_HOME
HB_INSTALL_HOME=$(eval echo ~"$HB_INSTALL_USER")

# ── Load shared config ────────────────────────────────────────────────────────
# shellcheck source=lib/config.sh
source "$HB_REPO_DIR/lib/config.sh"

# ── Banner ────────────────────────────────────────────────────────────────────
echo -e "${HB_BOLD}"
echo "  ██╗  ██╗ █████╗ ███╗   ███╗"
echo "  ██║  ██║██╔══██╗████╗ ████║"
echo "  ███████║███████║██╔████╔██║"
echo "  ██╔══██║██╔══██║██║╚██╔╝██║"
echo "  ██║  ██║██║  ██║██║ ╚═╝ ██║"
echo "  ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝"
echo -e "${HB_NC}"
echo -e "  ${HB_CYAN}HamBridge — Ham Radio Recorder Bridge${HB_NC}"
echo -e "  Installer v1.0"
echo ""
hb_info "Installing for user: $HB_INSTALL_USER"
hb_info "Install directory:   $HB_INSTALL_DIR"

# =============================================================================
#  Radio selection
# =============================================================================
hb_step "Radio and Interface Selection"
echo ""
echo "  Which radio and interface are you using?"
echo ""
echo "  1) Yaesu FT-891 + DR-891"
echo "  2) Yaesu FT-747GX + Digirig Mobile"
echo ""
read -rp "  Enter choice [1-2]: " HB_RADIO_CHOICE

case "$HB_RADIO_CHOICE" in
    1)
        export HB_RADIO_MODEL="FT-891"
        export HB_HAMLIB_MODEL="136"
        export HB_BAUD_RATE="38400"
        export HB_STOP_BITS="1"
        export HB_WRITE_DELAY="0"
        export HB_RIGCTLD_TIMEOUT="3"
        export HB_UDEV_VENDOR="10c4"    # Silicon Labs CP210x (FT-891 USB)
        export HB_UDEV_PRODUCT="ea70"
        hb_info "Selected: FT-891 + DR-891"
        ;;
    2)
        export HB_RADIO_MODEL="FT-747GX"
        export HB_HAMLIB_MODEL="105"
        export HB_BAUD_RATE="4800"
        export HB_STOP_BITS="2"
        export HB_WRITE_DELAY="50"
        export HB_RIGCTLD_TIMEOUT="5"
        export HB_UDEV_VENDOR="0403"    # FTDI (FT-747GX CAT cable)
        export HB_UDEV_PRODUCT="6001"
        hb_info "Selected: FT-747GX + Digirig Mobile"
        hb_warn "Reminder: 5.6K resistor required on CAT SO pin (DIN pin 3 to GND)"
        ;;
    *)
        hb_error "Invalid choice — run the installer again and enter 1 or 2"
        ;;
esac

# =============================================================================
#  Bluetooth device name
# =============================================================================
echo ""
read -rp "  Bluetooth name for this Pi [default: HamBridge]: " HB_BT_NAME_INPUT
export HB_BT_NAME="${HB_BT_NAME_INPUT:-HamBridge}"

# =============================================================================
#  Confirm before making any changes
# =============================================================================
echo ""
echo -e "  ${HB_BOLD}Ready to install with these settings:${HB_NC}"
echo ""
echo "    Radio:           $HB_RADIO_MODEL"
echo "    hamlib model:    $HB_HAMLIB_MODEL"
echo "    Baud rate:       $HB_BAUD_RATE bps"
echo "    CAT device:      /dev/$HB_CAT_DEVICE_ALIAS"
echo "    Bluetooth name:  $HB_BT_NAME"
echo "    Install user:    $HB_INSTALL_USER"
echo "    Install dir:     $HB_INSTALL_DIR"
echo ""
read -rp "  Proceed? [y/N]: " HB_CONFIRM
[[ "$HB_CONFIRM" =~ ^[Yy]$ ]] || { hb_info "Aborted — no changes made."; exit 0; }

# =============================================================================
#  Run installation steps
# =============================================================================

# shellcheck source=lib/packages.sh
source "$HB_REPO_DIR/lib/packages.sh"
hb_install_packages

# shellcheck source=lib/udev.sh
source "$HB_REPO_DIR/lib/udev.sh"
hb_install_udev

# shellcheck source=lib/daemon.sh
source "$HB_REPO_DIR/lib/daemon.sh"
hb_install_daemon

# shellcheck source=lib/systemd.sh
source "$HB_REPO_DIR/lib/systemd.sh"
hb_install_systemd

# shellcheck source=lib/bluetooth.sh
source "$HB_REPO_DIR/lib/bluetooth.sh"
hb_configure_bluetooth

# Copy tools alongside the daemon
cp "$HB_REPO_DIR/diagnose.sh"  "$HB_DIAGNOSE_SCRIPT"
cp "$HB_REPO_DIR/uninstall.sh" "$HB_UNINSTALL_SCRIPT"
chmod +x "$HB_DIAGNOSE_SCRIPT" "$HB_UNINSTALL_SCRIPT"
chown "$HB_INSTALL_USER:$HB_INSTALL_USER" \
    "$HB_DIAGNOSE_SCRIPT" "$HB_UNINSTALL_SCRIPT"
hb_success "Tools installed"

hb_start_service

# =============================================================================
#  Summary
# =============================================================================
echo ""
echo -e "${HB_BOLD}${HB_GREEN}════════════════════════════════════════${HB_NC}"
echo -e "${HB_BOLD}${HB_GREEN}  HamBridge installation complete!${HB_NC}"
echo -e "${HB_BOLD}${HB_GREEN}════════════════════════════════════════${HB_NC}"
echo ""
echo -e "  ${HB_BOLD}Radio:${HB_NC}          $HB_RADIO_MODEL"
echo -e "  ${HB_BOLD}Bluetooth name:${HB_NC} $HB_BT_NAME"
echo -e "  ${HB_BOLD}Install dir:${HB_NC}    $HB_INSTALL_DIR"
echo ""
echo -e "  ${HB_BOLD}Useful commands:${HB_NC}"
echo ""
echo -e "  Service status:  ${HB_CYAN}sudo systemctl status hambridge${HB_NC}"
echo -e "  Live logs:       ${HB_CYAN}sudo journalctl -u hambridge -f${HB_NC}"
echo -e "  Diagnostics:     ${HB_CYAN}bash $HB_DIAGNOSE_SCRIPT${HB_NC}"
echo -e "  Edit settings:   ${HB_CYAN}nano $HB_INSTALL_DIR/hambridge_settings.py${HB_NC}"
echo -e "  Apply changes:   ${HB_CYAN}sudo systemctl restart hambridge${HB_NC}"
echo -e "  Uninstall:       ${HB_CYAN}bash $HB_UNINSTALL_SCRIPT${HB_NC}"
echo ""
echo -e "  ${HB_BOLD}Next steps:${HB_NC}"
echo ""
echo -e "  1. Connect hardware ($HB_RADIO_MODEL + interface + Pi)"
echo -e "  2. Reboot:           ${HB_CYAN}sudo reboot${HB_NC}"
echo -e "  3. Pair phone to '${HB_BT_NAME}' in Android Bluetooth settings"
echo -e "  4. Run diagnostics to confirm everything is working"
echo -e "  5. Open the HamBridge app on your phone"
echo ""
