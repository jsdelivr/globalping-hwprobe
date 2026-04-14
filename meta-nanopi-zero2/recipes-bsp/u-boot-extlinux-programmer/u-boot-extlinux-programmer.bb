SUMMARY = "Override extlinux.conf for eMMC programmer image"
DESCRIPTION = "Provides extlinux.conf with explicit SD card root device (/dev/mmcblk0p3) \
to ensure programmer image boots from SD card even when eMMC contains a valid rootfs."
HOMEPAGE = "https://github.com/jsdelivr/globalping-hwprobe"
SECTION = "bootloader"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# This recipe REPLACES the extlinux.conf from u-boot-nanopi-zero2-prebuilt
RPROVIDES:${PN} = "u-boot-extlinux"
RREPLACES:${PN} = "u-boot-nanopi-zero2-prebuilt-extlinux"
RCONFLICTS:${PN} = "u-boot-nanopi-zero2-prebuilt-extlinux"

COMPATIBLE_MACHINE = "nanopi-zero2"

SRC_URI = "file://extlinux.conf"

S = "${WORKDIR}"

do_install() {
    install -d ${D}/boot/extlinux
    install -m 0644 ${WORKDIR}/extlinux.conf ${D}/boot/extlinux/extlinux.conf
}

FILES:${PN} = "/boot/extlinux/extlinux.conf"
