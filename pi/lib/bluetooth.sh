#!/bin/bash
# =============================================================================
#  lib/bluetooth.sh
#  Configures the BlueZ Bluetooth stack so the Pi is permanently
#  discoverable and auto-enables on boot.
# =============================================================================

hb_configure_bluetooth() {
    hb_step "Configuring Bluetooth"

    # ── Unblock Bluetooth via rfkill ──────────────────────────────────────────
    # On fresh Pi OS installs Bluetooth is often soft-blocked by rfkill.
    # This unblocks it now and ensures it stays unblocked after reboot.
    rfkill unblock bluetooth 2>/dev/null || true

    # ── Permanent discoverability in main.conf ────────────────────────────────
    # DiscoverableTimeout = 0 means discoverable forever
    if grep -q "DiscoverableTimeout" "$HB_BT_CONF" 2>/dev/null; then
        sed -i 's/^#*DiscoverableTimeout.*/DiscoverableTimeout = 0/' "$HB_BT_CONF"
    else
        echo -e "\n[General]\nDiscoverableTimeout = 0" >> "$HB_BT_CONF"
    fi

    # ── Always re-enable Bluetooth on boot ────────────────────────────────────
    if grep -q "AutoEnable" "$HB_BT_CONF" 2>/dev/null; then
        sed -i 's/^#*AutoEnable.*/AutoEnable=true/' "$HB_BT_CONF"
    else
        echo -e "\n[Policy]\nAutoEnable=true" >> "$HB_BT_CONF"
    fi

    # ── Set Bluetooth adapter name ────────────────────────────────────────────
    if grep -q "^Name" "$HB_BT_CONF" 2>/dev/null; then
        sed -i "s/^Name.*/Name = $HB_BT_NAME/" "$HB_BT_CONF"
    else
        sed -i "/\[General\]/a Name = $HB_BT_NAME" "$HB_BT_CONF"
    fi

    # ── Restart bluetoothd and activate discoverable now ─────────────────────
    systemctl restart bluetooth
    sleep 2

    # Make discoverable and pairable immediately using bluetoothctl
    bluetoothctl << 'BTEOF'
power on
discoverable on
pairable on
BTEOF

    # ── Write a systemd service to re-enable discoverable on every boot ───────
    # bluetoothd resets discoverable on restart, so we run this after boot
    cat > /etc/systemd/system/hambridge-bt-discoverable.service << EOF
[Unit]
Description=HamBridge Bluetooth Discoverable
After=bluetooth.target hambridge.service
Wants=bluetooth.target

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 5
ExecStart=/usr/bin/bluetoothctl discoverable on
ExecStart=/usr/bin/bluetoothctl pairable on
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable hambridge-bt-discoverable

    # ── Set system hostname ───────────────────────────────────────────────────
    hostnamectl set-hostname "$HB_BT_NAME" 2>/dev/null || true

    hb_success "Bluetooth configured and discoverable"
    hb_info    "Device name: $HB_BT_NAME"
    hb_info    "Discoverable on every boot via hambridge-bt-discoverable.service"
}