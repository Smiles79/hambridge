#!/bin/bash
# =============================================================================
#  diagnose.sh
#  HamBridge diagnostics — run this any time something isn't working.
#  Checks every component of the system and reports pass/fail clearly.
#
#  Usage: bash ~/hambridge/diagnose.sh
# =============================================================================

HB_CYAN='\033[0;36m'
HB_GREEN='\033[0;32m'
HB_RED='\033[0;31m'
HB_YELLOW='\033[1;33m'
HB_BOLD='\033[1m'
HB_NC='\033[0m'

hb_pass() { echo -e "  ${HB_GREEN}✓${HB_NC}  $1"; }
hb_fail() { echo -e "  ${HB_RED}✗${HB_NC}  $1"; }
hb_warn() { echo -e "  ${HB_YELLOW}!${HB_NC}  $1"; }
hb_info() { echo -e "      ${HB_CYAN}→${HB_NC} $1"; }

echo ""
echo -e "${HB_BOLD}${HB_CYAN}══════════════════════════════════════════${HB_NC}"
echo -e "${HB_BOLD}${HB_CYAN}  HamBridge Diagnostics${HB_NC}"
echo -e "${HB_BOLD}${HB_CYAN}══════════════════════════════════════════${HB_NC}"
echo ""

# ── 1. USB serial devices ─────────────────────────────────────────────────────
echo -e "${HB_BOLD}USB Serial Devices${HB_NC}"
HB_USB_DEVS=$(ls /dev/ttyUSB* 2>/dev/null)
if [ -n "$HB_USB_DEVS" ]; then
    hb_pass "ttyUSB devices found:"
    for dev in $HB_USB_DEVS; do
        HB_VID=$(udevadm info -a -n "$dev" 2>/dev/null | grep idVendor | head -1 | tr -d ' "' | cut -d= -f2)
        HB_PID=$(udevadm info -a -n "$dev" 2>/dev/null | grep idProduct | head -1 | tr -d ' "' | cut -d= -f2)
        hb_info "$dev  (vendor=$HB_VID product=$HB_PID)"
    done
else
    hb_fail "No ttyUSB devices found"
    hb_info "Check: cable connections, radio is powered on, USB hub"
fi
echo ""

# ── 2. CAT port alias ─────────────────────────────────────────────────────────
echo -e "${HB_BOLD}CAT Port Alias${HB_NC}"
if [ -e "/dev/hamradiocat" ]; then
    HB_TARGET=$(readlink -f /dev/hamradiocat)
    hb_pass "/dev/hamradiocat → $HB_TARGET"
else
    hb_fail "/dev/hamradiocat not found"
    hb_info "Check: /etc/udev/rules.d/99-hamradio.rules exists"
    hb_info "Fix:   sudo udevadm control --reload-rules && sudo udevadm trigger"
fi
echo ""

# ── 3. Audio devices ──────────────────────────────────────────────────────────
echo -e "${HB_BOLD}Audio Devices${HB_NC}"
HB_AUDIO=$(arecord -l 2>/dev/null | grep -i "usb\|digirig\|card" || true)
if [ -n "$HB_AUDIO" ]; then
    hb_pass "USB audio device found:"
    echo "$HB_AUDIO" | while IFS= read -r line; do
        hb_info "$line"
    done
else
    hb_fail "No USB audio device found"
    hb_info "Check: Digirig / DR-891 is plugged in and USB hub is powered"
fi
echo ""

# ── 4. HamBridge service ──────────────────────────────────────────────────────
echo -e "${HB_BOLD}HamBridge Service${HB_NC}"
HB_SVC_STATUS=$(systemctl is-active hambridge 2>/dev/null)
if [ "$HB_SVC_STATUS" = "active" ]; then
    hb_pass "hambridge.service is running"
    HB_SVC_PID=$(systemctl show hambridge --property=MainPID --value 2>/dev/null)
    hb_info "PID: $HB_SVC_PID"
elif systemctl list-unit-files 2>/dev/null | grep -q "hambridge"; then
    hb_fail "hambridge.service is installed but not running ($HB_SVC_STATUS)"
    hb_info "Start:  sudo systemctl start hambridge"
    hb_info "Logs:   sudo journalctl -u hambridge -n 30"
else
    hb_fail "hambridge.service is not installed"
    hb_info "Re-run the installer: sudo bash install.sh"
fi
echo ""

# ── 5. rigctld ────────────────────────────────────────────────────────────────
echo -e "${HB_BOLD}rigctld${HB_NC}"
if pgrep -x rigctld > /dev/null; then
    hb_pass "rigctld is running"
    HB_RIGCTLD_CMD=$(ps aux | grep rigctld | grep -v grep | sed 's/.*rigctld/rigctld/' | head -1)
    hb_info "$HB_RIGCTLD_CMD"
else
    hb_fail "rigctld is not running"
    hb_info "Usually started automatically by hambridge.service"
    hb_info "Check: sudo systemctl start hambridge"
fi
echo ""

# ── 6. Bluetooth ──────────────────────────────────────────────────────────────
echo -e "${HB_BOLD}Bluetooth${HB_NC}"
HB_BT_STATUS=$(systemctl is-active bluetooth 2>/dev/null)
if [ "$HB_BT_STATUS" = "active" ]; then
    hb_pass "bluetooth.service is running"
else
    hb_fail "Bluetooth is not running"
    hb_info "Fix: sudo systemctl start bluetooth"
fi
HB_BT_INFO=$(hciconfig 2>/dev/null | grep -E "hci[0-9]|BD Address|UP|DOWN" || true)
if [ -n "$HB_BT_INFO" ]; then
    echo "$HB_BT_INFO" | while IFS= read -r line; do
        hb_info "$line"
    done
else
    hb_warn "No Bluetooth adapter found (hciconfig returned nothing)"
fi
echo ""

# ── 7. Settings file ──────────────────────────────────────────────────────────
echo -e "${HB_BOLD}Settings${HB_NC}"
HB_SETTINGS="$HOME/hambridge/hambridge_settings.py"
if [ -f "$HB_SETTINGS" ]; then
    hb_pass "hambridge_settings.py found"
    HB_RADIO=$(grep "^RADIO_MODEL" "$HB_SETTINGS" | cut -d'"' -f2)
    HB_MODEL=$(grep "^HAMLIB_MODEL" "$HB_SETTINGS" | awk '{print $3}')
    HB_BAUD=$(grep "^BAUD_RATE" "$HB_SETTINGS" | awk '{print $3}')
    hb_info "Radio: $HB_RADIO  |  hamlib: $HB_MODEL  |  baud: $HB_BAUD"
else
    hb_fail "hambridge_settings.py not found at $HB_SETTINGS"
    hb_info "Re-run the installer to regenerate it"
fi
echo ""

# ── 8. Live CAT test ──────────────────────────────────────────────────────────
echo -e "${HB_BOLD}Live CAT Test${HB_NC}"
if [ -e "/dev/hamradiocat" ] && pgrep -x rigctld > /dev/null; then
    # Detect model and baud from running rigctld process
    if ps aux | grep rigctld | grep -qv grep | grep -q "\-s 4800"; then
        HB_TEST_BAUD=4800; HB_TEST_MODEL=105
    else
        HB_TEST_BAUD=38400; HB_TEST_MODEL=136
    fi
    echo -n "  Querying radio frequency ... "
    HB_FREQ=$(timeout 7 rigctl -m "$HB_TEST_MODEL" -r /dev/hamradiocat -s "$HB_TEST_BAUD" f 2>/dev/null || true)
    if [ -n "$HB_FREQ" ]; then
        HB_FREQ_MHZ=$(echo "scale=4; $HB_FREQ / 1000000" | bc 2>/dev/null || echo "$HB_FREQ Hz")
        echo -e "${HB_GREEN}OK${HB_NC}"
        hb_info "Frequency: ${HB_FREQ_MHZ} MHz"
    else
        echo -e "${HB_RED}FAILED${HB_NC}"
        hb_info "Check: radio is powered on, CAT cable connected"
        hb_info "FT-747GX: verify 5.6K resistor on SO pin"
    fi
else
    hb_warn "Skipped — CAT device or rigctld not available"
fi
echo ""

echo -e "${HB_BOLD}${HB_CYAN}══════════════════════════════════════════${HB_NC}"
echo ""
