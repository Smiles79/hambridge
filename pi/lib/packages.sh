#!/bin/bash
# =============================================================================
#  lib/packages.sh
#  Installs all required system packages via apt.
#  Called by install.sh after config.sh has been sourced.
# =============================================================================

hb_install_packages() {
    hb_step "Installing system packages"

    apt-get update -qq

    apt-get install -y -qq \
        python3-pip \
        python3-dev \
        libhamlib-utils \
        alsa-utils \
        bluetooth \
        bluez \
        python3-bluetooth \
        libbluetooth-dev \
        udev

    hb_success "System packages installed"
}
