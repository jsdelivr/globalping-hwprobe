require recipes-core/images/core-image-minimal.bb

DESCRIPTION = "Minimal image for programming eMMC with LED feedback and bundled baseonly production image"

# Ensure core-image-minimal-baseonly is built first (needed for production-image-bundle-baseonly)
do_rootfs[depends] += "core-image-minimal-baseonly:do_image_complete"

# Add eMMC programmer, custom hostname, and bundled baseonly production WIC image
IMAGE_INSTALL += "emmc-programmer emmc-programmer-hostname production-image-bundle-baseonly"

# Override extlinux.conf with SD card specific version
# This ensures programmer boots from SD card even when eMMC has valid rootfs
IMAGE_INSTALL += "u-boot-extlinux-programmer"

# Remove unnecessary packages to minimize size
IMAGE_INSTALL:remove = "docker tini iptables skopeo"
IMAGE_INSTALL:remove = "jsdelivr-service jsdelivr-scripts jsdelivr-configure jsdelivr-basecontainer"
IMAGE_INSTALL:remove += "jsdelivr-container-manager jsdelivr-optional-containers"
IMAGE_INSTALL:remove += "jsdelivr-container-crowdsec jsdelivr-container-netdata jsdelivr-container-wireguard"
IMAGE_INSTALL:remove = "python3-core python3-flask"
IMAGE_INSTALL:remove = "strace htop mc lsof nano jq"
# RAUC OTA services must not run on programmer image - rauc-mark-good validates
# Docker (not installed here) and triggers reboot -f on failure, causing reboot loops
IMAGE_INSTALL:remove += "rauc rauc-handlers"

# Keep essential tools
# xz is required for decompressing production.wic.xz (handles >4GB files correctly)
IMAGE_INSTALL:append = " e2fsprogs util-linux xz"
