#!/bin/sh
# Generate hostname for emmc-programmer: emmc-programmer-XXXX (where XXXX is 2 random hex bytes)
# This runs on each boot to set a unique hostname

# Generate 2 random hex bytes (4 hex characters)
RANDOM_HEX=$(dd if=/dev/urandom bs=2 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')

# Create hostname: emmc-programmer-XXXX
HOSTNAME="emmc-programmer-${RANDOM_HEX}"

# Set the hostname directly using hostname command
# This works without systemd-hostnamed being ready
hostname "$HOSTNAME"

# Also try hostnamectl if available (for persistent hostname)
hostnamectl set-hostname "$HOSTNAME" 2>/dev/null || true

echo "Set hostname to: $HOSTNAME"
