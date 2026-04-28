#!/bin/bash
#
# Clean all build artifacts for NanoPi Zero2 Yocto build
# This removes everything built, keeping only sources and configuration
#

set -eo pipefail

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

# Parse arguments
FULL_CLEAN=0
if [ "$1" == "--full" ]; then
    FULL_CLEAN=1
fi

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}NanoPi Zero2 Build Cleanup${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
echo "This will remove:"
echo "  - build/tmp/ (all built packages, images)"
echo "  - downloads/ (downloaded source tarballs)"
echo "  - sstate-cache/ (shared state cache)"
echo "  - build/cache/ (bitbake cache)"
echo "  - All other build/ subdirectories"
echo "  - sdk/ (Yocto SDK toolchain)"
echo "  - sources/uboot-rockchip build artifacts"
echo "  - sources/rkbin build artifacts"
if [ $FULL_CLEAN -eq 1 ]; then
    echo ""
    echo -e "  ${RED}--full mode: ALSO removing:${NC}"
    echo "  - sources/ (ALL cloned Yocto layers and FriendlyElec repos)"
    echo "  - build/conf/ (build configuration)"
    echo "  - uboot-output/ (standalone U-Boot build)"
    echo "  - uboot-build-standalone/ (standalone U-Boot work dir)"
fi
echo ""
echo "This will KEEP:"
echo "  - meta-nanopi-zero2/ (custom layer)"
echo "  - meta-jsdelivr/ (custom layer)"
echo "  - meta-nanopi-zero2/recipes-bsp/u-boot/files/ (source-built U-Boot binaries)"
if [ $FULL_CLEAN -eq 0 ]; then
    echo "  - sources/ (Yocto layers and FriendlyElec source repos)"
    echo "  - build/conf/local.conf (build configuration)"
    echo "  - build/conf/bblayers.conf (layer configuration)"
fi
echo "  - sd-fuse_rk3528/ (flash tools)"
echo ""

if [ $FULL_CLEAN -eq 1 ]; then
    echo -e "${RED}WARNING: --full will delete ALL cloned sources (~5GB+).${NC}"
    echo -e "${RED}You will need to re-run setup-yocto-from-scratch.sh to rebuild.${NC}"
    echo ""
fi

read -p "Continue? (yes/no): " response

if [ "$response" != "yes" ]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo -e "${GREEN}Cleaning Yocto build artifacts...${NC}"

# Backup configuration files
echo "Backing up configuration files..."
mkdir -p /tmp/yocto-config-backup
cp build/conf/local.conf /tmp/yocto-config-backup/ 2>/dev/null || true
cp build/conf/bblayers.conf /tmp/yocto-config-backup/ 2>/dev/null || true

# Clean entire build directory except conf/
if [ -d "build" ]; then
    echo "Removing all build/ contents except conf/..."
    # Remove everything in build/ except conf/
    find build/ -mindepth 1 -maxdepth 1 ! -name 'conf' -exec rm -rf {} +
fi

# Restore configuration files
echo "Restoring configuration files..."
mkdir -p build/conf
cp /tmp/yocto-config-backup/local.conf build/conf/ 2>/dev/null || true
cp /tmp/yocto-config-backup/bblayers.conf build/conf/ 2>/dev/null || true
rm -rf /tmp/yocto-config-backup

# Clean SDK
if [ -d "sdk" ]; then
    echo "Removing sdk/ (will be rebuilt by build-complete-image.sh)..."
    rm -rf sdk
fi

# Clean U-Boot build artifacts (keep source code)
if [ -d "sources/uboot-rockchip" ]; then
    echo "Cleaning U-Boot build artifacts..."
    cd sources/uboot-rockchip
    make clean > /dev/null 2>&1 || true
    rm -f *.img *.bin 2>/dev/null || true
    cd ../..
fi

if [ -d "sources/rkbin" ]; then
    echo "Cleaning rkbin build artifacts..."
    cd sources/rkbin
    rm -f idblock.img trust.img *.bin 2>/dev/null || true
    cd ../..
fi

# Note: We keep sources/ directory and source-built U-Boot binaries
# These are valuable and can be reused for faster rebuilds

# Clean downloads and sstate-cache (project root level)
if [ -d "downloads" ]; then
    echo "Removing downloads/ (will be rebuilt)..."
    rm -rf downloads
fi

if [ -d "sstate-cache" ]; then
    echo "Removing sstate-cache/ (will be rebuilt)..."
    rm -rf sstate-cache
fi

# Clean log files
rm -f sdk-build.log uboot-build.log image-build.log final-image-build.log uboot-make-sh.log build/*.log 2>/dev/null || true

# Full clean: remove sources, build config, and standalone U-Boot dirs
if [ $FULL_CLEAN -eq 1 ]; then
    echo ""
    echo -e "${RED}Performing full clean...${NC}"

    if [ -d "sources" ]; then
        echo "Removing sources/ (ALL cloned Yocto layers and FriendlyElec repos)..."
        rm -rf sources
    fi

    if [ -d "build/conf" ]; then
        echo "Removing build/conf/ (build configuration)..."
        rm -rf build/conf
    fi

    if [ -d "uboot-output" ]; then
        echo "Removing uboot-output/ (standalone U-Boot build)..."
        rm -rf uboot-output
    fi

    if [ -d "uboot-build-standalone" ]; then
        echo "Removing uboot-build-standalone/ (standalone U-Boot work dir)..."
        rm -rf uboot-build-standalone
    fi
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Cleaned:"
echo "  ✓ All build/ contents (except conf/)"
echo "  ✓ downloads/"
echo "  ✓ sstate-cache/"
echo "  ✓ sdk/ (Yocto SDK)"
echo "  ✓ U-Boot build artifacts"
echo "  ✓ rkbin build artifacts"
echo "  ✓ Log files"
if [ $FULL_CLEAN -eq 1 ]; then
    echo "  ✓ sources/ (ALL cloned repos)"
    echo "  ✓ build/conf/ (build configuration)"
    echo "  ✓ uboot-output/ (standalone U-Boot)"
    echo "  ✓ uboot-build-standalone/"
fi
echo ""
echo "Preserved:"
echo "  ✓ meta-nanopi-zero2/ (custom layer)"
echo "  ✓ meta-jsdelivr/ (custom layer)"
if [ $FULL_CLEAN -eq 0 ]; then
    echo "  ✓ build/conf/local.conf"
    echo "  ✓ build/conf/bblayers.conf"
    echo "  ✓ sources/ (Yocto layers, FriendlyElec repos, symlinks to custom layers)"
    echo "  ✓ meta-nanopi-zero2/recipes-bsp/u-boot/files/ (source-built U-Boot binaries)"
fi
echo "  ✓ sd-fuse_rk3528/ (flash tools)"
echo ""
if [ $FULL_CLEAN -eq 1 ]; then
    echo "To rebuild from scratch:"
    echo "  ./setup-yocto-from-scratch.sh"
else
    echo "To rebuild everything:"
    echo "  ./build-complete-image.sh"
    echo ""
    echo "Or manually step-by-step:"
    echo "  # 1. Build SDK"
    echo "  source sources/poky/oe-init-build-env build"
    echo "  bitbake meta-toolchain"
    echo "  # 2. Build U-Boot"
    echo "  cd sources/uboot-rockchip"
    echo "  source ../../sdk/environment-setup-cortexa53-crypto-poky-linux"
    echo "  ./make.sh nanopi_zero2"
    echo "  # 3. Build image"
    echo "  cd ../.."
    echo "  source sources/poky/oe-init-build-env build"
    echo "  bitbake core-image-minimal"
fi
