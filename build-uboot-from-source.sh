#!/bin/bash
# Build U-Boot from FriendlyElec source for NanoPi Zero2 (RK3528)
# This builds U-Boot outside of Yocto due to 2017.09 compatibility issues

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCES_DIR="${SCRIPT_DIR}/sources"
UBOOT_DIR="${SOURCES_DIR}/uboot-rockchip"
RKBIN_DIR="${SOURCES_DIR}/rkbin"
OUTPUT_DIR="${SCRIPT_DIR}/uboot-output"

echo "============================================"
echo "Building U-Boot for NanoPi Zero2 (RK3528)"
echo "============================================"
echo

# Check if sources exist
if [ ! -d "${SOURCES_DIR}" ]; then
    echo "ERROR: FriendlyElec sources not found!"
    echo "Please run ./setup-friendlyelec-sources.sh first"
    exit 1
fi

if [ ! -d "${UBOOT_DIR}" ]; then
    echo "ERROR: U-Boot source not found at ${UBOOT_DIR}"
    echo "Please run ./setup-friendlyelec-sources.sh first"
    exit 1
fi

if [ ! -d "${RKBIN_DIR}" ]; then
    echo "ERROR: rkbin not found at ${RKBIN_DIR}"
    echo "Please run ./setup-friendlyelec-sources.sh first"
    exit 1
fi

# Check for cross-compiler
if [ -z "${CROSS_COMPILE}" ]; then
    # Try to find Yocto SDK
    if [ -f "${SCRIPT_DIR}/sources/poky/oe-init-build-env" ]; then
        echo "Setting up Yocto build environment for cross-compiler..."
        cd "${SCRIPT_DIR}"
        source sources/poky/oe-init-build-env build > /dev/null

        # Get cross-compiler from Yocto
        CROSS_COMPILE=$(bitbake -e | grep "^TARGET_PREFIX=" | cut -d'"' -f2)
        export CROSS_COMPILE

        if [ -z "${CROSS_COMPILE}" ]; then
            echo "ERROR: Could not determine cross-compiler from Yocto"
            exit 1
        fi
    else
        echo "ERROR: CROSS_COMPILE not set and Yocto environment not found"
        echo "Please set CROSS_COMPILE environment variable"
        echo "Example: export CROSS_COMPILE=aarch64-linux-gnu-"
        exit 1
    fi
fi

echo "Using cross-compiler: ${CROSS_COMPILE}"
echo "U-Boot source: ${UBOOT_DIR}"
echo "rkbin location: ${RKBIN_DIR}"
echo

# Clean previous build
echo "=== Cleaning previous build ==="
cd "${UBOOT_DIR}"
make distclean || true
echo

# Configure for NanoPi Zero2 / RK3528
echo "=== Configuring U-Boot ==="
# Note: FriendlyElec uses nanopi5_defconfig for RK3528-based boards
make nanopi5_defconfig
echo

# Build U-Boot
echo "=== Building U-Boot ==="
make -j$(nproc) CROSS_COMPILE=${CROSS_COMPILE}
echo

# Create output directory
mkdir -p "${OUTPUT_DIR}"

# Package bootloaders
echo "=== Packaging bootloaders ==="

# The U-Boot build should produce:
# - u-boot.bin or u-boot.itb
# - spl/u-boot-spl.bin (for idbloader)

if [ ! -f "u-boot.bin" ] && [ ! -f "u-boot.itb" ]; then
    echo "ERROR: U-Boot binary not found!"
    echo "Expected u-boot.bin or u-boot.itb in ${UBOOT_DIR}"
    exit 1
fi

# For RK3528, we need to create:
# 1. idbloader.img = ddr init + miniloader (or SPL)
# 2. uboot.img = U-Boot proper (possibly FIT with ATF/OP-TEE)

# Check if there's a make.sh script from FriendlyElec
if [ -f "./make.sh" ]; then
    echo "Using FriendlyElec make.sh for packaging..."
    ./make.sh nanopi5

    # Copy outputs
    if [ -f "idbloader.img" ]; then
        cp idbloader.img "${OUTPUT_DIR}/"
        echo "✓ Created idbloader.img ($(stat -c%s idbloader.img) bytes)"
    fi

    if [ -f "uboot.img" ]; then
        cp uboot.img "${OUTPUT_DIR}/"
        echo "✓ Created uboot.img ($(stat -c%s uboot.img) bytes)"
    fi
else
    echo "WARNING: make.sh not found, attempting manual packaging..."

    # Manual packaging using rkbin tools
    # This is complex and depends on RK3528 specific requirements
    # For now, warn the user
    echo "ERROR: Cannot package without make.sh"
    echo "The U-Boot built successfully but packaging failed"
    echo "Please check FriendlyElec documentation for RK3528 packaging"
    exit 1
fi

echo

# Verify outputs
echo "=== Verifying outputs ==="
VERIFY_FAILED=0

if [ ! -f "${OUTPUT_DIR}/idbloader.img" ]; then
    echo "✗ idbloader.img not created"
    VERIFY_FAILED=1
else
    IDBLOADER_SIZE=$(stat -c%s "${OUTPUT_DIR}/idbloader.img")
    echo "✓ idbloader.img: ${IDBLOADER_SIZE} bytes"

    # Should be around 304KB (311296 bytes)
    if [ ${IDBLOADER_SIZE} -lt 200000 ] || [ ${IDBLOADER_SIZE} -gt 500000 ]; then
        echo "  WARNING: Size seems unusual (expected ~304KB)"
    fi
fi

if [ ! -f "${OUTPUT_DIR}/uboot.img" ]; then
    echo "✗ uboot.img not created"
    VERIFY_FAILED=1
else
    UBOOT_SIZE=$(stat -c%s "${OUTPUT_DIR}/uboot.img")
    echo "✓ uboot.img: ${UBOOT_SIZE} bytes"

    # Should be around 4MB (4194304 bytes)
    if [ ${UBOOT_SIZE} -lt 3000000 ] || [ ${UBOOT_SIZE} -gt 5000000 ]; then
        echo "  WARNING: Size seems unusual (expected ~4MB)"
    fi
fi

if [ ${VERIFY_FAILED} -eq 1 ]; then
    echo
    echo "ERROR: Build verification failed"
    exit 1
fi

# Record build information
echo
echo "=== Recording build information ==="
cat > "${OUTPUT_DIR}/build-info.txt" << EOF
U-Boot Build Information
========================
Build Date: $(date)
Build Host: $(hostname)
Cross Compiler: ${CROSS_COMPILE}
GCC Version: $(${CROSS_COMPILE}gcc --version | head -1)

U-Boot Source:
  Directory: ${UBOOT_DIR}
  Branch: $(cd "${UBOOT_DIR}" && git rev-parse --abbrev-ref HEAD)
  Commit: $(cd "${UBOOT_DIR}" && git rev-parse HEAD)
  Date: $(cd "${UBOOT_DIR}" && git log -1 --format=%cd)
  Subject: $(cd "${UBOOT_DIR}" && git log -1 --format=%s)

rkbin:
  Directory: ${RKBIN_DIR}
  Commit: $(cd "${RKBIN_DIR}" && git rev-parse HEAD)

Output Files:
  idbloader.img: ${IDBLOADER_SIZE} bytes
  uboot.img: ${UBOOT_SIZE} bytes

Configuration: nanopi5_defconfig
EOF

echo
echo "============================================"
echo "Build Complete!"
echo "============================================"
echo
echo "Output directory: ${OUTPUT_DIR}"
echo
echo "Files created:"
echo "  - idbloader.img (${IDBLOADER_SIZE} bytes)"
echo "  - uboot.img (${UBOOT_SIZE} bytes)"
echo "  - build-info.txt"
echo
echo "Next steps:"
echo "  1. Copy bootloaders to Yocto layer:"
echo "     cp ${OUTPUT_DIR}/*.img meta-nanopi-zero2/recipes-bsp/u-boot/files/"
echo
echo "  2. Rebuild Yocto image:"
echo "     source sources/poky/oe-init-build-env build"
echo "     bitbake core-image-minimal"
echo
echo "  3. Test on hardware"
echo
