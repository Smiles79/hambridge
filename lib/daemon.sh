#!/bin/bash
# =============================================================================
#  lib/daemon.sh
#  Places hambridge.py into the install directory.
#  The Python file is read from the same directory as this script
#  (i.e. the downloaded repo) and copied to HB_INSTALL_DIR.
#
#  Radio-specific settings (hamlib model, baud rate, etc.) are written
#  into a small settings block at the top of the installed copy so the
#  Python file itself stays generic and human-readable.
# =============================================================================

hb_install_daemon() {
    hb_step "Installing bridge daemon"

    mkdir -p "$HB_INSTALL_DIR"

    # ── Write the radio-specific settings file ────────────────────────────────
    # hambridge.py imports these at runtime from hambridge_settings.py
    # Edit this file after installation to change radio parameters
    # without touching the main daemon code.
    cat > "$HB_INSTALL_DIR/hambridge_settings.py" << EOF
# =============================================================================
#  hambridge_settings.py
#  Radio-specific settings for the HamBridge daemon.
#  Safe to edit by hand — changes take effect on next service restart.
#  After editing: sudo systemctl restart hambridge
# =============================================================================

# ── Radio ─────────────────────────────────────────────────────────────────────
RADIO_MODEL     = "$HB_RADIO_MODEL"
HAMLIB_MODEL    = $HB_HAMLIB_MODEL          # hamlib rig number
BAUD_RATE       = $HB_BAUD_RATE             # CAT baud rate
STOP_BITS       = $HB_STOP_BITS             # serial stop bits (1 or 2)
WRITE_DELAY     = $HB_WRITE_DELAY           # ms between bytes (0 = default)
CAT_DEVICE      = "/dev/$HB_CAT_DEVICE_ALIAS"
CAT_TIMEOUT     = $HB_RIGCTLD_TIMEOUT       # seconds to wait for CAT response

# ── Bluetooth ─────────────────────────────────────────────────────────────────
BT_SERVICE_NAME = "$HB_BT_NAME"

# ── Audio ─────────────────────────────────────────────────────────────────────
SAMPLE_RATE     = 48000                     # Hz
CHANNELS        = 1                         # mono
SAMPLE_WIDTH    = 2                         # bytes (16-bit)
CHUNK_SIZE      = 4096                      # bytes per audio frame sent to phone
EOF

    # ── Copy the main daemon script ───────────────────────────────────────────
    # HB_REPO_DIR is set by install.sh to the directory containing this repo
    cp "$HB_REPO_DIR/hambridge.py" "$HB_DAEMON_SCRIPT"

    chown -R "$HB_INSTALL_USER:$HB_INSTALL_USER" "$HB_INSTALL_DIR"
    chmod +x "$HB_DAEMON_SCRIPT"

    hb_success "Daemon installed to $HB_DAEMON_SCRIPT"
    hb_success "Settings written to $HB_INSTALL_DIR/hambridge_settings.py"
    hb_info    "Edit hambridge_settings.py to change radio parameters"
}
