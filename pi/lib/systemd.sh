#!/bin/bash
# =============================================================================
#  lib/systemd.sh
#  Creates the systemd service unit file for hambridge and enables it
#  so the bridge daemon starts automatically on every boot.
#
#  The service runs as HB_INSTALL_USER (not root) for safety.
#  It depends on bluetooth.target so Bluetooth is ready before the
#  daemon tries to advertise its RFCOMM service.
# =============================================================================

hb_install_systemd() {
    hb_step "Creating systemd service"

    cat > "$HB_SERVICE_FILE" << EOF
[Unit]
Description=HamBridge — Ham Radio Recorder Bridge ($HB_RADIO_MODEL)
After=bluetooth.target
Wants=bluetooth.target

[Service]
ExecStart=/usr/bin/python3 $HB_DAEMON_SCRIPT
Restart=on-failure
RestartSec=5
User=$HB_INSTALL_USER

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$HB_SERVICE_NAME"

    hb_success "Service enabled: $HB_SERVICE_NAME"
    hb_info    "Service file: $HB_SERVICE_FILE"
    hb_info    "Starts automatically on every boot"
}

hb_start_service() {
    hb_step "Starting service"

    systemctl start "$HB_SERVICE_NAME" \
        || hb_warn "Service failed to start — run diagnose.sh to investigate"

    sleep 2
    rfkill unblock bluetooth
    bluetoothctl power on
    bluetoothctl discoverable on
    bluetoothctl pairable on

    local HB_STATUS
    HB_STATUS=$(systemctl is-active "$HB_SERVICE_NAME" 2>/dev/null)

    if [ "$HB_STATUS" = "active" ]; then
        hb_success "Service is running"
    else
        hb_warn "Service is not yet active"
        hb_info  "This is normal if the radio/interface isn't connected yet"
        hb_info  "The service will start automatically on reboot with hardware connected"
    fi
}
