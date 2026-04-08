#!/bin/bash
#
# Complete build script for NanoPi Zero2 Yocto image
# This script orchestrates the entire build process:
# 1. Build U-Boot from source (if binaries missing) - MUST be first for bitbake parsing
# 2. Build Yocto SDK (if not already built)
# 3. Rebuild U-Boot with Yocto SDK (optional, for consistency)
# 4. Build final bootable image with WIC
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Save project directory
PROJECT_DIR="$(pwd)"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}NanoPi Zero2 Complete Image Builder${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check we're in the right directory
if [ ! -d "sources/poky" ]; then
    echo -e "${RED}Error: Must be run from Yocto build root directory${NC}"
    echo "Expected to find: sources/poky"
    exit 1
fi

# Check FriendlyElec sources exist
if [ ! -d "sources/uboot-rockchip" ]; then
    echo -e "${RED}Error: FriendlyElec U-Boot sources not found${NC}"
    echo "Expected to find: sources/uboot-rockchip"
    echo "Run setup-friendlyelec-sources.sh first"
    exit 1
fi

if [ ! -d "sources/rkbin" ]; then
    echo -e "${RED}Error: rkbin repository not found${NC}"
    echo "Expected to find: sources/rkbin"
    echo "Run setup-friendlyelec-sources.sh first"
    exit 1
fi

# Step 0: Check if U-Boot binaries exist - MUST exist before any bitbake
# Bitbake parses ALL recipes before building, so U-Boot files must exist
UBOOT_FILES_DIR="meta-nanopi-zero2/recipes-bsp/u-boot/files"
DUMMY_UBOOT_CREATED=0
if [ ! -f "$UBOOT_FILES_DIR/idbloader.img" ] || [ ! -f "$UBOOT_FILES_DIR/uboot.img" ]; then
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}Step 0: Creating dummy U-Boot files${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}(Required for bitbake to parse recipes)${NC}"
    echo ""

    # Create dummy files so bitbake can parse recipes
    mkdir -p "$UBOOT_FILES_DIR"
    dd if=/dev/zero of="$UBOOT_FILES_DIR/idbloader.img" bs=1K count=312 2>/dev/null
    dd if=/dev/zero of="$UBOOT_FILES_DIR/uboot.img" bs=1M count=4 2>/dev/null
    DUMMY_UBOOT_CREATED=1

    echo -e "${GREEN}✓ Dummy U-Boot files created (will be replaced after SDK build)${NC}"
    echo ""
fi

# Step 1: Check for/Build SDK
echo -e "${GREEN}Step 1: Checking for Yocto SDK...${NC}"
SDK_DIR="sdk"
SDK_SETUP_SCRIPT="$SDK_DIR/environment-setup-cortexa53-crypto-poky-linux"
SDK_INSTALLER=$(ls build/tmp/deploy/sdk/poky-glibc-x86_64-meta-toolchain-*.sh 2>/dev/null | head -1 || true)

if [ -f "$SDK_SETUP_SCRIPT" ]; then
    echo -e "${GREEN}✓ SDK already installed in $SDK_DIR${NC}"
elif [ -n "$SDK_INSTALLER" ]; then
    echo -e "${YELLOW}SDK installer found: $SDK_INSTALLER${NC}"
    echo -e "${YELLOW}Installing SDK to $SDK_DIR...${NC}"
    "$SDK_INSTALLER" -d "$(pwd)/$SDK_DIR" -y
else
    echo -e "${YELLOW}SDK not found, building it...${NC}"
    echo -e "${YELLOW}This will take some time (10-30 minutes)${NC}"
    PROJECT_DIR="$(pwd)"
    mkdir -p build/conf
    [ ! -f build/conf/local.conf ] && cp meta-jsdelivr/build_conf/local.conf build/conf/
    [ ! -f build/conf/bblayers.conf ] && cp meta-jsdelivr/build_conf/bblayers.conf build/conf/
    source sources/poky/oe-init-build-env build
    bitbake meta-toolchain

    # After sourcing, we're in the build directory, so adjust path
    SDK_INSTALLER=$(ls tmp/deploy/sdk/poky-glibc-x86_64-meta-toolchain-*.sh | head -1)
    echo -e "${GREEN}SDK built: $SDK_INSTALLER${NC}"
    echo -e "${YELLOW}Installing SDK to $SDK_DIR...${NC}"
    cd "$PROJECT_DIR"
    "$PROJECT_DIR/build/$SDK_INSTALLER" -d "$PROJECT_DIR/$SDK_DIR" -y
fi

# Step 2: Create toolchain symlinks
echo -e "${GREEN}Step 2: Setting up toolchain symlinks...${NC}"
TOOLCHAIN_DIR="$SDK_DIR/sysroots/x86_64-pokysdk-linux/usr/bin/aarch64-poky-linux"
if [ -d "$TOOLCHAIN_DIR" ]; then
    cd "$TOOLCHAIN_DIR"
    for tool in gcc g++ ld ar as nm objcopy objdump ranlib strip readelf size strings addr2line c++filt elfedit gprof; do
        if [ -f "aarch64-poky-linux-$tool" ] && [ ! -f "aarch64-linux-gnu-$tool" ]; then
            ln -sf "aarch64-poky-linux-$tool" "aarch64-linux-gnu-$tool"
        fi
    done
    cd - > /dev/null
    echo -e "${GREEN}✓ Toolchain symlinks created${NC}"
else
    echo -e "${RED}Error: Toolchain directory not found: $TOOLCHAIN_DIR${NC}"
    exit 1
fi

# Step 3: Build U-Boot from source
echo -e "${GREEN}Step 3: Building U-Boot from source...${NC}"
echo -e "${YELLOW}This includes ATF, OP-TEE, and all firmware components${NC}"

# Run U-Boot build in a subshell to avoid polluting environment
(
    cd sources/uboot-rockchip
    source "../../$SDK_SETUP_SCRIPT"

    # Clean previous build
    make clean > /dev/null 2>&1 || true

    # Build U-Boot
    echo -e "${YELLOW}Running FriendlyElec make.sh...${NC}"
    ./make.sh nanopi_zero2

    if [ ! -f "uboot.img" ] || [ ! -f "../rkbin/idblock.img" ]; then
        echo -e "${RED}Error: U-Boot build failed${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ U-Boot built successfully${NC}"
    echo "  - idblock.img: $(ls -lh ../rkbin/idblock.img | awk '{print $5}')"
    echo "  - uboot.img: $(ls -lh uboot.img | awk '{print $5}')"
)

# Check if U-Boot build succeeded (subshell exit code)
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: U-Boot build failed${NC}"
    exit 1
fi

# Step 4: Copy U-Boot binaries to Yocto recipe
echo -e "${GREEN}Step 4: Installing U-Boot binaries to Yocto recipe...${NC}"

# Backup existing binaries if they exist
if [ -f "meta-nanopi-zero2/recipes-bsp/u-boot/files/idbloader.img" ]; then
    BACKUP_SUFFIX="backup-$(date +%Y%m%d-%H%M%S)"
    echo -e "${YELLOW}Backing up existing binaries to *.$BACKUP_SUFFIX${NC}"
    cp meta-nanopi-zero2/recipes-bsp/u-boot/files/idbloader.img \
       meta-nanopi-zero2/recipes-bsp/u-boot/files/idbloader.img.$BACKUP_SUFFIX
    cp meta-nanopi-zero2/recipes-bsp/u-boot/files/uboot.img \
       meta-nanopi-zero2/recipes-bsp/u-boot/files/uboot.img.$BACKUP_SUFFIX
fi

# Copy source-built binaries (idblock.img is named idbloader.img in Yocto)
cp sources/rkbin/idblock.img \
   meta-nanopi-zero2/recipes-bsp/u-boot/files/idbloader.img
cp sources/uboot-rockchip/uboot.img \
   meta-nanopi-zero2/recipes-bsp/u-boot/files/uboot.img

echo -e "${GREEN}✓ Source-built U-Boot binaries installed${NC}"

# Step 5: Build final images
echo -e "${GREEN}Step 5: Building final bootable images...${NC}"
cd "$PROJECT_DIR"
mkdir -p build/conf
[ ! -f build/conf/local.conf ] && cp meta-jsdelivr/build_conf/local.conf build/conf/
[ ! -f build/conf/bblayers.conf ] && cp meta-jsdelivr/build_conf/bblayers.conf build/conf/
source sources/poky/oe-init-build-env build

echo -e "${YELLOW}Building production image with all containers (core-image-minimal)...${NC}"
bitbake core-image-minimal

echo -e "${YELLOW}Building base-only image (only globalping-probe, no optional containers)...${NC}"
bitbake core-image-minimal-baseonly

echo -e "${YELLOW}Building eMMC programmer image (full variant)...${NC}"
bitbake emmc-programmer-image

echo -e "${YELLOW}Building eMMC programmer image (baseonly variant)...${NC}"
bitbake emmc-programmer-image-baseonly

echo -e "${YELLOW}Building RAUC update bundle for OTA updates...${NC}"
bitbake rauc-update-bundle

echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✓ Build Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Build Summary:"
echo "  - SDK: $(readlink -f ../$SDK_DIR)"
echo "  - U-Boot source: $(readlink -f ../sources/uboot-rockchip)"
echo "  - U-Boot binaries: source-built with ATF + OP-TEE + firmware"
echo ""
echo "Output files:"
ls -lh build/tmp/deploy/images/nanopi-zero2/*-image*.wic 2>/dev/null || echo "WIC images in: build/tmp/deploy/images/nanopi-zero2/"
echo ""
echo -e "${GREEN}Production Image - Full (all containers enabled):${NC}"
echo "  sudo dd if=build/tmp/deploy/images/nanopi-zero2/core-image-minimal-nanopi-zero2.rootfs.wic of=/dev/sdX bs=4M status=progress && sync"
echo "  (Includes: globalping-probe + CrowdSec IPS + optional containers)"
echo ""
echo -e "${GREEN}Production Image - Base Only (globalping-probe only):${NC}"
echo "  sudo dd if=build/tmp/deploy/images/nanopi-zero2/core-image-minimal-baseonly-nanopi-zero2.rootfs.wic of=/dev/sdX bs=4M status=progress && sync"
echo "  (Includes: only base globalping-probe container, no optional containers)"
echo ""
echo -e "${GREEN}eMMC Programmer Image - Full (programs full image to eMMC):${NC}"
echo "  sudo dd if=build/tmp/deploy/images/nanopi-zero2/emmc-programmer-image-nanopi-zero2.rootfs.wic of=/dev/sdX bs=4M status=progress && sync"
echo "  (Flash to SD card, boot device, programs full image with CrowdSec)"
echo ""
echo -e "${GREEN}eMMC Programmer Image - Baseonly (programs minimal image to eMMC):${NC}"
echo "  sudo dd if=build/tmp/deploy/images/nanopi-zero2/emmc-programmer-image-baseonly-nanopi-zero2.rootfs.wic of=/dev/sdX bs=4M status=progress && sync"
echo "  (Flash to SD card, boot device, programs baseonly image without CrowdSec)"
echo ""
echo -e "${GREEN}RAUC Update Bundle (for OTA updates):${NC}"
RAUC_BUNDLE=$(ls -1 tmp/deploy/images/nanopi-zero2/rauc-update-bundle-nanopi-zero2*.raucb 2>/dev/null | grep -v '^l' | head -1)
if [ -n "$RAUC_BUNDLE" ]; then
    echo "  Bundle: $RAUC_BUNDLE ($(ls -lh $RAUC_BUNDLE | awk '{print $5}'))"
    echo "  Install via: scp $RAUC_BUNDLE debug@<device-ip>:/docker_persist/"
    echo "  On device:   sudo rauc install /docker_persist/$(basename $RAUC_BUNDLE)"
else
    echo "  Bundle: tmp/deploy/images/nanopi-zero2/rauc-update-bundle-nanopi-zero2.raucb"
fi
echo ""
echo "  (Replace /dev/sdX with your SD card device)"
echo ""
echo -e "${YELLOW}To rebuild U-Boot only:${NC}"
echo "  cd sources/uboot-rockchip"
echo "  source ../../$SDK_SETUP_SCRIPT"
echo "  make clean && ./make.sh nanopi_zero2"
echo "  cp ../rkbin/idblock.img ../../meta-nanopi-zero2/recipes-bsp/u-boot/files/idbloader.img"
echo "  cp uboot.img ../../meta-nanopi-zero2/recipes-bsp/u-boot/files/uboot.img"
