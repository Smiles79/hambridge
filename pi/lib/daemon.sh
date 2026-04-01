#!/bin/bash
# =============================================================================
#  lib/daemon.sh
#  Copies hambridge.py into the install directory.
#
#  Radio parameters are no longer set here — they are sent from the Android
#  app at connection time via the set_radio command. The Pi daemon is fully
#  radio-agnostic and requires no radio configuration at install time.
# =============================================================================

hb_install_daemon() {
    hb_step "Installing bridge daemon"

    mkdir -p "$HB_INSTALL_DIR"

    # Copy the main daemon script from the repo
    # HB_REPO_DIR is set by install.sh to the downloaded repo directory
    cp "$HB_REPO_DIR/pi/hambridge.py" "$HB_DAEMON_SCRIPT"

    chown -R "$HB_INSTALL_USER:$HB_INSTALL_USER" "$HB_INSTALL_DIR"
    chmod +x "$HB_DAEMON_SCRIPT"

    hb_success "Daemon installed to $HB_DAEMON_SCRIPT"
    hb_info    "Radio model is configured in the Android app — not here"
    hb_info    "The app sends CAT parameters to the Pi on every connection"
}
