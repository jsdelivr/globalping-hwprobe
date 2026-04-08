SUMMARY = "RAUC Update Bundle for NanoPi Zero2"
DESCRIPTION = "Creates a RAUC bundle for OTA updates"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit bundle

RAUC_BUNDLE_COMPATIBLE = "nanopi-zero2"
RAUC_BUNDLE_VERSION = "1.0.0"
RAUC_BUNDLE_DESCRIPTION = "NanoPi Zero2 System Update"
RAUC_BUNDLE_FORMAT = "verity"

RAUC_BUNDLE_SLOTS = "rootfs"
RAUC_SLOT_rootfs = "core-image-minimal"
RAUC_SLOT_rootfs[fstype] = "ext4"
# Enable adaptive updates - only download changed 4KB blocks
# Reduces typical update size to ~10% of full bundle
RAUC_SLOT_rootfs[adaptive] = "block-hash-index"

# Use development keys for signing (same keys as rauc-conf)
RAUC_KEY_FILE = "${THISDIR}/files/dev-ca.key.pem"
RAUC_CERT_FILE = "${THISDIR}/files/ca.cert.pem"

# Output filename
RAUC_BUNDLE_BASENAME = "nanopi-zero2-update"
