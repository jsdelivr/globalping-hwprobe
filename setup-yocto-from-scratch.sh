#!/bin/bash
#
# Complete Yocto setup from scratch for NanoPi Zero2
#
# This script sets up the entire build environment including:
# 1. Clone all required Yocto layers (Scarthgap 5.0.12)
# 2. Configure build directory
# 3. Clone FriendlyElec sources (reproducible build)
# 4. Build the bootable image
#
# Usage:
#   ./setup-yocto-from-scratch.sh [--skip-build] [-y|--yes]
#

set -eo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
YOCTO_RELEASE="scarthgap"
PROJECT_DIR="${PWD}"
SOURCES_DIR="${PROJECT_DIR}/sources"
BUILD_DIR="${PROJECT_DIR}/build"
DOWNLOADS_DIR="${PROJECT_DIR}/downloads"
SSTATE_DIR="${PROJECT_DIR}/sstate-cache"

# Parse arguments
SKIP_BUILD=0
AUTO_YES=0
for arg in "$@"; do
    case "$arg" in
        --skip-build) SKIP_BUILD=1 ;;
        -y|--yes) AUTO_YES=1 ;;
    esac
done

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE} NanoPi Zero2 - Complete Yocto Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "This will set up:"
echo "  - Yocto ${YOCTO_RELEASE} layers"
echo "  - FriendlyElec sources (kernel, U-Boot)"
echo "  - Build environment"
if [ $SKIP_BUILD -eq 0 ]; then
    echo "  - Build bootable image"
else
    echo "  - (Skipping build)"
fi
echo ""
if [ $AUTO_YES -eq 0 ]; then
    read -p "Continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# Helper function to clone or update git repo
clone_or_update() {
    local url=$1
    local dir=$2
    local branch=$3

    if [ -d "$dir/.git" ]; then
        echo -e "${YELLOW}Updating existing: $(basename $dir)${NC}"
        cd "$dir"
        git fetch origin
        git checkout "$branch"
        git pull origin "$branch"
        cd - >/dev/null
    else
        echo -e "${GREEN}Cloning: $(basename $dir)${NC}"
        git clone -b "$branch" "$url" "$dir"
    fi
}

# Step 1: Clone Yocto layers
echo -e "${GREEN}Step 1: Cloning Yocto layers (${YOCTO_RELEASE})...${NC}"
mkdir -p "${SOURCES_DIR}"

clone_or_update \
    "https://github.com/yoctoproject/poky.git" \
    "${SOURCES_DIR}/poky" \
    "${YOCTO_RELEASE}"

clone_or_update \
    "https://github.com/openembedded/meta-openembedded.git" \
    "${SOURCES_DIR}/meta-openembedded" \
    "${YOCTO_RELEASE}"

clone_or_update \
    "https://github.com/YoeDistro/meta-arm.git" \
    "${SOURCES_DIR}/meta-arm" \
    "${YOCTO_RELEASE}"

clone_or_update \
    "https://github.com/YoeDistro/meta-rockchip.git" \
    "${SOURCES_DIR}/meta-rockchip" \
    "${YOCTO_RELEASE}"

clone_or_update \
    "https://github.com/lgirdk/meta-virtualization.git" \
    "${SOURCES_DIR}/meta-virtualization" \
    "${YOCTO_RELEASE}"

clone_or_update \
    "https://github.com/rauc/meta-rauc.git" \
    "${SOURCES_DIR}/meta-rauc" \
    "${YOCTO_RELEASE}"

echo -e "${GREEN}✓ Yocto layers ready${NC}"
echo ""

# Create symlinks for custom layers in sources/
echo -e "${GREEN}Creating symlinks for custom layers in sources/...${NC}"
ln -sfn ../meta-jsdelivr "${SOURCES_DIR}/meta-jsdelivr"
ln -sfn ../meta-nanopi-zero2 "${SOURCES_DIR}/meta-nanopi-zero2"

# Step 2: Initialize build directory
echo -e "${GREEN}Step 2: Initializing build directory...${NC}"

# Copy build configs from meta-jsdelivr/build_conf/ if not already present
mkdir -p "${BUILD_DIR}/conf"
[ ! -f "${BUILD_DIR}/conf/local.conf" ] && cp "${PROJECT_DIR}/meta-jsdelivr/build_conf/local.conf" "${BUILD_DIR}/conf/"
[ ! -f "${BUILD_DIR}/conf/bblayers.conf" ] && cp "${PROJECT_DIR}/meta-jsdelivr/build_conf/bblayers.conf" "${BUILD_DIR}/conf/"

cd "${PROJECT_DIR}"
source "${SOURCES_DIR}/poky/oe-init-build-env" "${BUILD_DIR}"

echo -e "${GREEN}✓ Build directory initialized with configs from meta-jsdelivr/build_conf/${NC}"
echo ""

# Return to project directory
cd "${PROJECT_DIR}"

# Step 3: Clone FriendlyElec sources
echo -e "${GREEN}Step 3: Cloning FriendlyElec sources...${NC}"
if [ -x "./setup-friendlyelec-sources.sh" ]; then
    ./setup-friendlyelec-sources.sh
    echo -e "${GREEN}✓ FriendlyElec sources cloned${NC}"
else
    echo -e "${YELLOW}Warning: setup-friendlyelec-sources.sh not found, skipping${NC}"
fi
echo ""

# Step 4: Build SDK (required for U-Boot compilation)
echo -e "${GREEN}Step 4: Building Yocto SDK for cross-compilation...${NC}"
echo -e "${YELLOW}This will take 10-30 minutes on first build${NC}"

SDK_DIR="${PROJECT_DIR}/sdk"
SDK_SETUP_SCRIPT="$SDK_DIR/environment-setup-cortexa53-crypto-poky-linux"

if [ -f "$SDK_SETUP_SCRIPT" ]; then
    echo -e "${GREEN}✓ SDK already installed${NC}"
else
    # Create dummy U-Boot files so bitbake can parse recipes
    UBOOT_FILES_DIR="meta-nanopi-zero2/recipes-bsp/u-boot/files"
    mkdir -p "$UBOOT_FILES_DIR"
    if [ ! -f "$UBOOT_FILES_DIR/idbloader.img" ]; then
        dd if=/dev/zero of="$UBOOT_FILES_DIR/idbloader.img" bs=1K count=312 2>/dev/null
    fi
    if [ ! -f "$UBOOT_FILES_DIR/uboot.img" ]; then
        dd if=/dev/zero of="$UBOOT_FILES_DIR/uboot.img" bs=1M count=4 2>/dev/null
    fi

    # Build SDK
    cd "${PROJECT_DIR}"
    mkdir -p "${BUILD_DIR}/conf"
    [ ! -f "${BUILD_DIR}/conf/local.conf" ] && cp "${PROJECT_DIR}/meta-jsdelivr/build_conf/local.conf" "${BUILD_DIR}/conf/"
    [ ! -f "${BUILD_DIR}/conf/bblayers.conf" ] && cp "${PROJECT_DIR}/meta-jsdelivr/build_conf/bblayers.conf" "${BUILD_DIR}/conf/"
    source "${SOURCES_DIR}/poky/oe-init-build-env" "${BUILD_DIR}"
    bitbake meta-toolchain

    # Install SDK
    SDK_INSTALLER=$(ls tmp/deploy/sdk/poky-glibc-x86_64-meta-toolchain-*.sh 2>/dev/null | head -1)
    if [ -n "$SDK_INSTALLER" ]; then
        echo -e "${YELLOW}Installing SDK to ${SDK_DIR}...${NC}"
        cd "${PROJECT_DIR}"
        "${PROJECT_DIR}/build/$SDK_INSTALLER" -d "$SDK_DIR" -y
        echo -e "${GREEN}✓ SDK installed${NC}"
    else
        echo -e "${RED}Error: SDK installer not found${NC}"
        exit 1
    fi
fi
echo ""

# Step 5: Create toolchain symlinks for U-Boot build
echo -e "${GREEN}Step 5: Setting up toolchain symlinks...${NC}"
cd "${PROJECT_DIR}"
TOOLCHAIN_DIR="$SDK_DIR/sysroots/x86_64-pokysdk-linux/usr/bin/aarch64-poky-linux"
if [ -d "$TOOLCHAIN_DIR" ]; then
    cd "$TOOLCHAIN_DIR"
    for tool in gcc g++ ld ar as nm objcopy objdump ranlib strip readelf size strings addr2line c++filt elfedit gprof; do
        if [ -f "aarch64-poky-linux-$tool" ] && [ ! -f "aarch64-linux-gnu-$tool" ]; then
            ln -sf "aarch64-poky-linux-$tool" "aarch64-linux-gnu-$tool"
        fi
    done
    cd "${PROJECT_DIR}"
    echo -e "${GREEN}✓ Toolchain symlinks created${NC}"
else
    echo -e "${RED}Error: Toolchain directory not found${NC}"
    exit 1
fi
echo ""

# Step 6: Build U-Boot from source
echo -e "${GREEN}Step 6: Building U-Boot from FriendlyElec sources...${NC}"
echo -e "${YELLOW}This includes ATF, OP-TEE, and all firmware components${NC}"

if [ -d "sources/uboot-rockchip" ] && [ -d "sources/rkbin" ]; then
    (
        cd sources/uboot-rockchip
        source "$SDK_SETUP_SCRIPT"

        # Clean previous build
        make clean > /dev/null 2>&1 || true

        # Build U-Boot
        echo -e "${YELLOW}Running FriendlyElec make.sh nanopi_zero2...${NC}"
        ./make.sh nanopi_zero2

        if [ ! -f "uboot.img" ] || [ ! -f "../rkbin/idblock.img" ]; then
            echo -e "${RED}Error: U-Boot build failed${NC}"
            exit 1
        fi

        echo -e "${GREEN}✓ U-Boot built successfully${NC}"
    )

    # Copy U-Boot binaries to Yocto recipe
    echo -e "${YELLOW}Installing U-Boot binaries to Yocto recipe...${NC}"
    cp sources/rkbin/idblock.img \
       meta-nanopi-zero2/recipes-bsp/u-boot/files/idbloader.img
    cp sources/uboot-rockchip/uboot.img \
       meta-nanopi-zero2/recipes-bsp/u-boot/files/uboot.img
    echo -e "${GREEN}✓ U-Boot binaries installed${NC}"
else
    echo -e "${RED}Error: FriendlyElec sources not found${NC}"
    exit 1
fi
echo ""

# Step 7: Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✓ Setup Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}Project structure:${NC}"
echo "  sources/              - All sources (Yocto layers, FriendlyElec repos, symlinks to custom layers)"
echo "  build/               - Build directory (conf/ copied from meta-jsdelivr/build_conf/)"
echo "  sdk/                 - Yocto cross-compilation SDK"
echo "  meta-nanopi-zero2/   - Custom NanoPi Zero2 layer (symlinked in sources/)"
echo "  meta-jsdelivr/       - Custom Globalping layer (symlinked in sources/)"
echo ""
echo -e "${YELLOW}Build configuration:${NC}"
echo "  Machine: nanopi-zero2"
echo "  Yocto: ${YOCTO_RELEASE}"
echo "  Kernel: FriendlyElec 6.1.118 (pinned)"
echo "  U-Boot: FriendlyElec 2017.09 (built from source)"
echo ""

# Step 8: Optional image build
if [ $SKIP_BUILD -eq 0 ]; then
    echo -e "${YELLOW}Starting image build (this will take 1-3 hours)...${NC}"
    echo ""
    echo "Images to build:"
    echo "  1. core-image-minimal (production full)"
    echo "  2. core-image-minimal-baseonly (production base)"
    echo "  3. emmc-programmer-image (SD card programmer full)"
    echo "  4. emmc-programmer-image-baseonly (SD card programmer base)"
    echo "  5. rauc-update-bundle (OTA update bundle)"
    echo ""
    REPLY="y"
    if [ $AUTO_YES -eq 0 ]; then
        read -p "Continue with build? (y/N) " -n 1 -r
        echo
    fi
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cd "${PROJECT_DIR}"
        source "${SOURCES_DIR}/poky/oe-init-build-env" "${BUILD_DIR}"

        echo -e "${GREEN}Building core-image-minimal (1/5)...${NC}"
        bitbake core-image-minimal

        echo -e "${GREEN}Building core-image-minimal-baseonly (2/5)...${NC}"
        bitbake core-image-minimal-baseonly

        echo -e "${GREEN}Building emmc-programmer-image (3/5)...${NC}"
        bitbake emmc-programmer-image

        echo -e "${GREEN}Building emmc-programmer-image-baseonly (4/5)...${NC}"
        bitbake emmc-programmer-image-baseonly

        echo -e "${GREEN}Building rauc-update-bundle (5/5)...${NC}"
        bitbake rauc-update-bundle

        echo -e "${BLUE}========================================${NC}"
        echo -e "${GREEN}✓ Build Complete!${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo ""
        echo "Generated images:"
        ls -lh tmp/deploy/images/nanopi-zero2/*.wic* 2>/dev/null || true
        ls -lh tmp/deploy/images/nanopi-zero2/*.raucb 2>/dev/null || true
        echo ""
        echo "To flash production image to SD card:"
        echo "  sudo dd if=tmp/deploy/images/nanopi-zero2/core-image-minimal-nanopi-zero2.rootfs.wic of=/dev/sdX bs=4M status=progress"
        echo ""
        echo "To flash eMMC programmer to SD card:"
        echo "  sudo dd if=tmp/deploy/images/nanopi-zero2/emmc-programmer-image-nanopi-zero2.rootfs.wic of=/dev/sdX bs=4M status=progress"
        echo ""
        echo "  (Replace /dev/sdX with your SD card device)"
    fi
else
    echo -e "${YELLOW}To build all images later:${NC}"
    echo "  source sources/poky/oe-init-build-env build"
    echo "  bitbake core-image-minimal core-image-minimal-baseonly emmc-programmer-image emmc-programmer-image-baseonly rauc-update-bundle"
fi

echo ""
echo -e "${GREEN}Done!${NC}"
