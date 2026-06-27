#!/bin/bash
#
# Standalone U-Boot builder for NanoPi Zero2 (RK3528)
# Builds FriendlyElec's U-Boot 2017.09 outside Yocto and packages the binaries.
#
# Reproducible builds: set UBOOT_REV / RKBIN_REV to specific commit SHAs to pin
# the exact source revisions. When unset, the script tracks branch tips
# (legacy behaviour). Either way, both commit SHAs are recorded in VERSION.txt
# and the tarball name so the artifact provenance is always traceable.
#

set -eo pipefail

# Configuration
UBOOT_REPO="https://github.com/friendlyarm/uboot-rockchip.git"
UBOOT_BRANCH="nanopi5-v2017.09"
UBOOT_VERSION="2017.09"
UBOOT_REV="${UBOOT_REV:-}"      # commit SHA pin; empty -> use branch tip
RKBIN_REPO="https://github.com/rockchip-linux/rkbin.git"
RKBIN_REV="${RKBIN_REV:-}"      # commit SHA pin; empty -> use master tip
WORK_DIR="${PWD}/uboot-build-standalone"
OUTPUT_DIR="${WORK_DIR}/output"
BOARD="nanopi_zero2"

# ARM64 cross-compiler - try Yocto SDK first, then system
YOCTO_BUILD="${PWD}/build"
SDK_PATH="${YOCTO_BUILD}/tmp/deploy/sdk"

ENV_SETUP=""
if [ -d "/opt/poky" ]; then
    ENV_SETUP=$(find /opt/poky -maxdepth 1 -name 'environment-setup-*' -print -quit 2>/dev/null)
fi
if [ -n "$ENV_SETUP" ]; then
    echo "Using installed Yocto SDK from /opt/poky"
    source "$ENV_SETUP"
    CROSS_COMPILE="aarch64-poky-linux-"
elif SDK_INSTALLER=$(find "${SDK_PATH}" -maxdepth 1 -name 'poky-glibc-x86_64-meta-toolchain-*.sh' -print -quit 2>/dev/null) && [ -n "$SDK_INSTALLER" ]; then
    echo "Found Yocto SDK installer: ${SDK_INSTALLER}"
    echo "To install: ${SDK_INSTALLER}"
    echo "Then run this script again"
    exit 1
elif command -v aarch64-linux-gnu-gcc &> /dev/null; then
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
    if [ -n "$RKBIN_REV" ]; then
        git -C rkbin fetch origin "$RKBIN_REV"
        git -C rkbin checkout --detach "$RKBIN_REV"
    else
        git -C rkbin fetch origin
        git -C rkbin pull origin master
    fi
else
    echo -e "${YELLOW}Cloning rkbin repository...${NC}"
    if [ -n "$RKBIN_REV" ]; then
        # Full clone (no --depth) so the pinned SHA is reachable.
        git clone "$RKBIN_REPO" rkbin
        git -C rkbin checkout --detach "$RKBIN_REV"
    else
        git clone --depth 1 "$RKBIN_REPO" rkbin
    fi
fi

# Clone or update U-Boot repository
if [ -d "uboot-rockchip" ]; then
    echo -e "${YELLOW}Updating existing U-Boot repository...${NC}"
    if [ -n "$UBOOT_REV" ]; then
        git -C uboot-rockchip fetch origin "$UBOOT_REV"
        git -C uboot-rockchip checkout --detach "$UBOOT_REV"
    else
        git -C uboot-rockchip fetch origin
        git -C uboot-rockchip checkout "$UBOOT_BRANCH"
        git -C uboot-rockchip pull origin "$UBOOT_BRANCH"
    fi
    cd uboot-rockchip
else
    echo -e "${YELLOW}Cloning U-Boot repository...${NC}"
    if [ -n "$UBOOT_REV" ]; then
        git clone "$UBOOT_REPO" uboot-rockchip
        git -C uboot-rockchip checkout --detach "$UBOOT_REV"
    else
        git clone --depth 1 -b "$UBOOT_BRANCH" "$UBOOT_REPO" uboot-rockchip
    fi
    cd uboot-rockchip
fi

# Capture the actual commits that were checked out so VERSION.txt and the
# tarball name reflect what was built, whether pinned or branch-tip.
UBOOT_COMMIT=$(git -C "${WORK_DIR}/uboot-rockchip" rev-parse HEAD)
RKBIN_COMMIT=$(git -C "${WORK_DIR}/rkbin" rev-parse HEAD)
UBOOT_SHORT=${UBOOT_COMMIT:0:8}
RKBIN_SHORT=${RKBIN_COMMIT:0:8}
echo -e "${GREEN}Source: U-Boot ${UBOOT_SHORT} + rkbin ${RKBIN_SHORT}${NC}"

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
U-Boot commit: ${UBOOT_COMMIT}
rkbin commit:  ${RKBIN_COMMIT}
EOF

# Create tarball for Yocto. Name includes both short SHAs so two builds with
# different source content cannot share a filename.
cd "${OUTPUT_DIR}"
TARBALL_NAME="u-boot-nanopi-zero2-prebuilt-${UBOOT_VERSION}-${UBOOT_SHORT}-${RKBIN_SHORT}.tar.gz"
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
