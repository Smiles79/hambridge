#!/bin/bash
# =============================================================================
#  lib/bluetooth.sh
#  Configures the BlueZ Bluetooth stack so the Pi is permanently
#  discoverable and auto-enables on boot.
#
#  Also sets the Pi's system hostname to match the chosen BT device name
#  so it's easily identifiable on the network as well as over Bluetooth.
#
#  Uses HB_BT_NAME (set during radio selection in install.sh).
# =============================================================================

hb_configure_bluetooth() {
    hb_step "Configuring Bluetooth"

    # ── Permanent discoverability ─────────────────────────────────────────────
    # DiscoverableTimeout = 0 means discoverable forever (not just 3 minutes)
    if grep -q "DiscoverableTimeout" "$HB_BT_CONF" 2>/dev/null; then
        sed -i 's/^#*DiscoverableTimeout.*/DiscoverableTimeout = 0/' "$HB_BT_CONF"
    else
        echo -e "\n[General]\nDiscoverableTimeout = 0" >> "$HB_BT_CONF"
    fi

    # ── Auto-enable Bluetooth on boot ─────────────────────────────────────────
    if grep -q "AutoEnable" "$HB_BT_CONF" 2>/dev/null; then
        sed -i 's/^#*AutoEnable.*/AutoEnable=true/' "$HB_BT_CONF"
    else
        echo -e "\n[Policy]\nAutoEnable=true" >> "$HB_BT_CONF"
    fi

    # ── Set system hostname to match BT name ──────────────────────────────────
    # This makes the Pi show up as the same name on both Bluetooth and the
    # local network (e.g. ssh pi@HamBridge.local)
    hostnamectl set-hostname "$HB_BT_NAME" 2>/dev/null || true

    hb_success "Bluetooth configured"
    hb_info    "Device will appear as: $HB_BT_NAME"
    hb_info    "SSH hostname: $HB_BT_NAME.local"
}
