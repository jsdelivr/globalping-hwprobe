#!/bin/bash
#
# Standalone U-Boot builder for NanoPi Zero2 (RK3528)
# This script builds FriendlyElec's U-Boot 2017.09 outside of Yocto
# and packages the binaries for consumption by Yocto WIC
#

set -e

# Configuration
UBOOT_REPO="https://github.com/friendlyarm/uboot-rockchip.git"
UBOOT_BRANCH="nanopi5-v2017.09"
UBOOT_VERSION="2017.09"
RKBIN_REPO="https://github.com/rockchip-linux/rkbin.git"
WORK_DIR="${PWD}/uboot-build-standalone"
OUTPUT_DIR="${WORK_DIR}/output"
BOARD="nanopi_zero2"

# ARM64 cross-compiler - try Yocto SDK first, then system
YOCTO_BUILD="${PWD}/build"
SDK_PATH="${YOCTO_BUILD}/tmp/deploy/sdk"

# Check for installed Yocto SDK
if [ -d "/opt/poky" ]; then
    ENV_SETUP=$(ls /opt/poky/environment-setup-* 2>/dev/null | head -1)
    if [ -n "$ENV_SETUP" ]; then
        echo "Using installed Yocto SDK from /opt/poky"
        source "$ENV_SETUP"
        CROSS_COMPILE="aarch64-poky-linux-"
    fi
elif [ -d "/opt/poky" ] && ls /opt/poky/environment-setup-*poky-linux 2>/dev/null | grep -q .; then
    echo "Using installed Yocto SDK from /opt/poky"
    SDK_SETUP=$(ls /opt/poky/environment-setup-*poky-linux 2>/dev/null | head -1)
    source "${SDK_SETUP}"
    CROSS_COMPILE="aarch64-poky-linux-"
# Check for Yocto SDK installer
elif [ -f "${SDK_PATH}/poky-glibc-x86_64-meta-toolchain-cortexa53-crypto-nanopi-zero2-toolchain"*.sh ]; then
    SDK_INSTALLER=$(ls -t ${SDK_PATH}/poky-glibc-x86_64-meta-toolchain-*.sh 2>/dev/null | head -1)
    echo "Found Yocto SDK installer: ${SDK_INSTALLER}"
    echo "To install: ${SDK_INSTALLER}"
    echo "Then run this script again"
    exit 1
# Use system cross-compiler
elif command -v aarch64-linux-gnu-gcc &> /dev/null; then
    # Use system cross-compiler
    CROSS_COMPILE="aarch64-linux-gnu-"
    echo "Using system cross-compiler: ${CROSS_COMPILE}"
else
    echo "Error: No ARM64 cross-compiler found"
    echo "Options:"
    echo "  1. Build and install Yocto SDK: bitbake meta-toolchain"
    echo "  2. Install system compiler: sudo apt-get install gcc-aarch64-linux-gnu"
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}NanoPi Zero2 U-Boot Standalone Builder${NC}"
echo -e "${GREEN}========================================${NC}"

# Create work directory
mkdir -p "${WORK_DIR}"
mkdir -p "${OUTPUT_DIR}"

cd "${WORK_DIR}"

# Clone or update rkbin repository (required by make.sh)
if [ -d "rkbin" ]; then
    echo -e "${YELLOW}Updating existing rkbin repository...${NC}"
    cd rkbin
    git fetch origin
    git pull origin master
    cd ..
else
    echo -e "${YELLOW}Cloning rkbin repository...${NC}"
    git clone --depth 1 ${RKBIN_REPO} rkbin
fi

# Clone or update U-Boot repository
if [ -d "uboot-rockchip" ]; then
    echo -e "${YELLOW}Updating existing U-Boot repository...${NC}"
    cd uboot-rockchip
    git fetch origin
    git checkout ${UBOOT_BRANCH}
    git pull origin ${UBOOT_BRANCH}
else
    echo -e "${YELLOW}Cloning U-Boot repository...${NC}"
    git clone --depth 1 -b ${UBOOT_BRANCH} ${UBOOT_REPO} uboot-rockchip
    cd uboot-rockchip
fi

echo -e "${GREEN}Building U-Boot for ${BOARD}...${NC}"

# Clean previous build
make distclean || true

# Use FriendlyElec's make.sh which handles Rockchip boot files
# This will create: rk3528_spl_loader_*.bin (idbloader) and uboot.img (FIT image)
./make.sh CROSS_COMPILE=${CROSS_COMPILE} ${BOARD}

# Check for required output files
# FriendlyElec's U-Boot generates different filenames:
# - rk3528_spl_loader_*.bin instead of idbloader.img
# - uboot.img (FIT image with ATF/OP-TEE/U-Boot)
REQUIRED_FILES=()
MISSING_FILES=()

# Find SPL loader (idbloader equivalent)
SPL_LOADER=$(ls rk3528_spl_loader_*.bin 2>/dev/null | head -1)
if [ -z "${SPL_LOADER}" ]; then
    MISSING_FILES+=("rk3528_spl_loader_*.bin (idbloader)")
else
    echo -e "${GREEN}Found SPL loader: ${SPL_LOADER}${NC}"
    REQUIRED_FILES+=("${SPL_LOADER}")
fi

# Check for uboot.img (FIT image)
if [ ! -f "uboot.img" ]; then
    MISSING_FILES+=("uboot.img")
else
    REQUIRED_FILES+=("uboot.img")
fi

if [ ${#MISSING_FILES[@]} -ne 0 ]; then
    echo -e "${RED}Error: Missing required files: ${MISSING_FILES[*]}${NC}"
    echo "Available files in build directory:"
    ls -lh *.img *.bin 2>/dev/null || echo "No .img or .bin files found"
    exit 1
fi

# Copy binaries to output directory
echo -e "${GREEN}Copying binaries to output directory...${NC}"
# Copy SPL loader as idbloader.img (standard WIC name)
if [ -n "${SPL_LOADER}" ]; then
    cp -v "${SPL_LOADER}" "${OUTPUT_DIR}/idbloader.img"
fi
# Copy uboot.img (already correct name)
if [ -f "uboot.img" ]; then
    cp -v "uboot.img" "${OUTPUT_DIR}/"
fi

# Create version info file
cat > "${OUTPUT_DIR}/VERSION.txt" <<EOF
U-Boot Version: ${UBOOT_VERSION}
Board: ${BOARD}
Branch: ${UBOOT_BRANCH}
Built on: $(date)
Commit: $(git rev-parse HEAD)
EOF

# Create tarball for Yocto
cd "${OUTPUT_DIR}"
TARBALL_NAME="u-boot-nanopi-zero2-prebuilt-${UBOOT_VERSION}.tar.gz"
tar -czf "${WORK_DIR}/${TARBALL_NAME}" *

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Build completed successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Output files:"
ls -lh "${OUTPUT_DIR}"/*
echo ""
echo "Tarball created: ${WORK_DIR}/${TARBALL_NAME}"
echo ""
echo "To use with Yocto:"
echo "1. Copy ${TARBALL_NAME} to your Yocto downloads directory or recipe files directory"
echo "2. Update your U-Boot recipe to use this tarball"
echo ""
echo -e "${YELLOW}Suggested Yocto recipe location:${NC}"
echo "   meta-nanopi-zero2/recipes-bsp/u-boot/files/${TARBALL_NAME}"
