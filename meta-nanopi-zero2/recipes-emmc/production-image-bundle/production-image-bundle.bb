SUMMARY = "Production WIC image bundle for eMMC programming"
DESCRIPTION = "Packages the core-image-minimal WIC image for flashing to eMMC"
HOMEPAGE = "https://github.com/jsdelivr/globalping-hwprobe"
SECTION = "base"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# This recipe depends on core-image-minimal being built
# We need the WIC file from the deploy directory
do_install[depends] = "core-image-minimal:do_image_complete"

DEPLOY_DIR_IMAGE = "${TOPDIR}/tmp/deploy/images/${MACHINE}"

do_install() {
    install -d ${D}/opt/images

    # Find the WIC file (it should be a symlink to the timestamped version)
    WIC_FILE="${DEPLOY_DIR_IMAGE}/core-image-minimal-${MACHINE}.rootfs.wic"

    if [ -f "$WIC_FILE" ]; then
        echo "Found production WIC: $WIC_FILE"

        # Get WIC size before compression (needed for verification)
        # Store as exact byte count for reliable verification on target
        # Use -L to follow symlink (WIC_FILE is a symlink to timestamped file)
        WIC_SIZE=$(stat -Lc%s "$WIC_FILE")
        WIC_SIZE_MB=$(echo "$WIC_SIZE" | awk '{printf "%.0f", $1/1024/1024}')

        # Compress the WIC with xz (handles files > 4GB correctly, unlike gzip)
        # Using -T0 for multi-threaded compression, -6 for good balance of speed/ratio
        echo "Compressing WIC image with xz..."
        xz -T0 -6 -c "$WIC_FILE" > ${D}/opt/images/production.wic.xz

        # Create a version/info file with exact size for verification
        echo "Production Image: core-image-minimal" > ${D}/opt/images/production.info
        echo "Machine: ${MACHINE}" >> ${D}/opt/images/production.info
        echo "Build Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')" >> ${D}/opt/images/production.info
        echo "Distro: ${DISTRO} ${DISTRO_VERSION}" >> ${D}/opt/images/production.info
        echo "Image Size: ${WIC_SIZE_MB} MB" >> ${D}/opt/images/production.info
        # Store exact byte size for verification (xz handles >4GB but we store for safety)
        echo "Image Size Bytes: ${WIC_SIZE}" >> ${D}/opt/images/production.info
    else
        bbfatal "core-image-minimal WIC file not found at $WIC_FILE"
    fi
}

FILES:${PN} = "/opt/images/*"

# This is a large package, don't try to strip binaries
INHIBIT_PACKAGE_STRIP = "1"
INHIBIT_PACKAGE_DEBUG_SPLIT = "1"

# Allow large files
INSANE_SKIP:${PN} = "installed-vs-shipped"
