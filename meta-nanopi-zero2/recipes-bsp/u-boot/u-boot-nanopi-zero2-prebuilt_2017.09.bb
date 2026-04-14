SUMMARY = "Pre-built U-Boot binaries for NanoPi Zero2"
DESCRIPTION = "Pre-compiled U-Boot bootloader from FriendlyElec for RK3528, built outside Yocto"
HOMEPAGE = "https://github.com/friendlyarm/uboot-rockchip"
SECTION = "bootloader"
LICENSE = "GPL-2.0-or-later"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-2.0-or-later;md5=fed54355545ffd980b814dab4a3b312c"

# U-Boot 2017.09 is too old for modern Yocto, so we build it outside
# using build-uboot-standalone.sh script and consume the tarball here

PROVIDES = "virtual/bootloader u-boot"
RPROVIDES:${PN} = "u-boot u-boot-extlinux"

PACKAGE_ARCH = "${MACHINE_ARCH}"
COMPATIBLE_MACHINE = "nanopi-zero2"

# Using FriendlyElec reference bootloaders for testing
SRC_URI = " \
    file://idbloader.img \
    file://uboot.img \
"

S = "${WORKDIR}"

inherit deploy

do_install() {
    # Create extlinux directory structure for compatibility
    install -d ${D}/boot/extlinux

    # Create extlinux.conf for RAUC A/B boot support
    # Initial image is Slot A (rootfs-a partition)
    # When RAUC installs to Slot B, post-install handler updates extlinux.conf
    # rauc.slot= kernel parameter identifies which slot booted
    cat > ${D}/boot/extlinux/extlinux.conf <<EOF
# Extlinux configuration for NanoPi Zero2 (RAUC A/B Boot - Slot A)
# This partition: rootfs-a (Slot A)
# RAUC post-install handler will update this for Slot B installations
label Yocto Linux Slot A
    kernel /boot/Image
    fdt /boot/rk3528-nanopi-rev01.dtb
    append root=PARTLABEL=rootfs-a rauc.slot=a rootwait rootfstype=ext4 console=ttyFIQ0,1500000n8 earlycon=uart8250,mmio32,0xff9f0000
EOF
}

PACKAGES = "${PN} ${PN}-extlinux"
FILES:${PN}-extlinux = "/boot/extlinux/extlinux.conf"
RPROVIDES:${PN}-extlinux = "u-boot-extlinux"

do_deploy() {
    # Deploy U-Boot binaries from extracted tarball
    # The tarball is extracted to ${WORKDIR} by bitbake

    if [ -f ${WORKDIR}/idbloader.img ]; then
        install -D -m 644 ${WORKDIR}/idbloader.img ${DEPLOYDIR}/idbloader.img
    else
        bbwarn "idbloader.img not found in tarball"
    fi

    if [ -f ${WORKDIR}/uboot.img ]; then
        install -D -m 644 ${WORKDIR}/uboot.img ${DEPLOYDIR}/uboot.img
    else
        bbwarn "uboot.img not found in tarball"
    fi

    # trust.img or u-boot.itb (different Rockchip boot flow variants)
    if [ -f ${WORKDIR}/trust.img ]; then
        install -D -m 644 ${WORKDIR}/trust.img ${DEPLOYDIR}/trust.img
    fi

    if [ -f ${WORKDIR}/u-boot.itb ]; then
        install -D -m 644 ${WORKDIR}/u-boot.itb ${DEPLOYDIR}/u-boot.itb
    fi

    # Also copy version info if present
    if [ -f ${WORKDIR}/VERSION.txt ]; then
        install -D -m 644 ${WORKDIR}/VERSION.txt ${DEPLOYDIR}/u-boot-version.txt
    fi
}

addtask deploy after do_install before do_build
