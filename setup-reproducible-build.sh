#!/bin/bash
# Master script to setup reproducible build environment
# This fetches all sources and builds components from known-good versions

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================================"
echo "NanoPi Zero2 Reproducible Build Setup"
echo "========================================================"
echo
echo "This script will:"
echo "  1. Clone FriendlyElec source repositories"
echo "  2. Record version information"
echo "  3. Optionally build U-Boot from source"
echo "  4. Optionally pin kernel version"
echo
echo "Prerequisites:"
echo "  - Git installed"
echo "  - Cross-compiler (from Yocto or system)"
echo "  - ~2GB disk space for sources"
echo
read -p "Continue? [Y/n] " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Step 1: Setup FriendlyElec sources
echo
echo "========================================================"
echo "Step 1: Cloning FriendlyElec Repositories"
echo "========================================================"
echo
if [ -f "${SCRIPT_DIR}/setup-friendlyelec-sources.sh" ]; then
    bash "${SCRIPT_DIR}/setup-friendlyelec-sources.sh"
else
    echo "ERROR: setup-friendlyelec-sources.sh not found!"
    exit 1
fi

# Check if sources were cloned successfully
if [ ! -d "${SCRIPT_DIR}/sources/uboot-rockchip" ]; then
    echo "ERROR: Source setup failed!"
    exit 1
fi

# Display version information
echo
echo "========================================================"
echo "Version Information"
echo "========================================================"
cat "${SCRIPT_DIR}/sources/versions.txt"
echo

# Step 2: Ask about U-Boot build
echo
echo "========================================================"
echo "Step 2: U-Boot Build"
echo "========================================================"
echo
echo "Current status: Using pre-built U-Boot binaries"
echo
echo "Options:"
echo "  1. Keep using pre-built binaries (recommended for now)"
echo "  2. Build U-Boot from source (experimental)"
echo
read -p "Choose option [1/2]: " -n 1 -r UBOOT_CHOICE
echo

case $UBOOT_CHOICE in
    2)
        echo
        echo "Building U-Boot from source..."
        if [ -f "${SCRIPT_DIR}/build-uboot-from-source.sh" ]; then
            bash "${SCRIPT_DIR}/build-uboot-from-source.sh"

            # Ask if user wants to update Yocto layer
            echo
            read -p "Copy built binaries to Yocto layer? [y/N] " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                cp "${SCRIPT_DIR}/uboot-output"/*.img \
                   "${SCRIPT_DIR}/meta-nanopi-zero2/recipes-bsp/u-boot/files/"
                echo "✓ Binaries copied to Yocto layer"
            fi
        else
            echo "ERROR: build-uboot-from-source.sh not found!"
        fi
        ;;
    *)
        echo "Keeping pre-built U-Boot binaries"
        ;;
esac

# Step 3: Ask about kernel version pinning
echo
echo "========================================================"
echo "Step 3: Kernel Version Pinning"
echo "========================================================"
echo
echo "Current status: Using AUTOREV (latest commit)"
echo
echo "Options:"
echo "  1. Keep using AUTOREV (gets latest kernel on each build)"
echo "  2. Pin to current commit (reproducible builds)"
echo
read -p "Choose option [1/2]: " -n 1 -r KERNEL_CHOICE
echo

case $KERNEL_CHOICE in
    2)
        echo
        echo "Pinning kernel version..."
        if [ -f "${SCRIPT_DIR}/update-kernel-srcrev.sh" ]; then
            bash "${SCRIPT_DIR}/update-kernel-srcrev.sh"
        else
            echo "ERROR: update-kernel-srcrev.sh not found!"
        fi
        ;;
    *)
        echo "Keeping AUTOREV for kernel"
        ;;
esac

# Summary
echo
echo "========================================================"
echo "Setup Complete!"
echo "========================================================"
echo
echo "Build environment is ready."
echo
echo "Configuration:"
echo "  - FriendlyElec sources: ${SCRIPT_DIR}/sources (uboot-rockchip, rkbin, kernel-rockchip)"
echo "  - U-Boot: $([ "$UBOOT_CHOICE" = "2" ] && echo "Built from source" || echo "Pre-built binaries")"
echo "  - Kernel: $([ "$KERNEL_CHOICE" = "2" ] && echo "Pinned version" || echo "AUTOREV")"
echo
echo "Version manifest: sources/build-manifest.json"
echo

# Create/update .gitignore
if ! grep -q "^uboot-output/" "${SCRIPT_DIR}/.gitignore" 2>/dev/null; then
    echo "Adding uboot-output to .gitignore..."
    echo -e "\n# U-Boot build output\nuboot-output/" >> "${SCRIPT_DIR}/.gitignore"
fi

# Next steps
echo
echo "Next Steps:"
echo "============"
echo
echo "1. Review version information:"
echo "   cat sources/versions.txt"
echo "   cat sources/build-manifest.json"
echo
echo "2. Build Yocto image:"
echo "   source sources/poky/oe-init-build-env build"
echo "   bitbake core-image-minimal"
echo
echo "3. Commit version information:"
echo "   git add sources/build-manifest.json"
echo "   git add sources/versions.txt"
echo "   git commit -m 'Add build version manifest'"
echo
echo "4. Document in README.md:"
echo "   - Exact commit hashes used"
echo "   - Build date and results"
echo
echo "For help, see: MIGRATION_PLAN.md"
echo
