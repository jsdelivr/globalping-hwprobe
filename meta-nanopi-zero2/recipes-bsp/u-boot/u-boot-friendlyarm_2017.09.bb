SUMMARY = "FriendlyElec U-Boot for NanoPi Zero2"
DESCRIPTION = "U-Boot from FriendlyElec's uboot-rockchip repository"
HOMEPAGE = "https://github.com/friendlyarm/uboot-rockchip"
SECTION = "bootloader"
LICENSE = "GPL-2.0-or-later"
LIC_FILES_CHKSUM = "file://Licenses/README;md5=a2c678cfd4a4d97135585cad908541c6"

require recipes-bsp/u-boot/u-boot.inc

DEPENDS += "dtc-native bc-native bison-native flex-native"

SRCREV = "${AUTOREV}"
SRC_URI = "git://github.com/friendlyarm/uboot-rockchip.git;protocol=https;branch=nanopi5-v2017.09"

S = "${WORKDIR}/git"

UBOOT_MACHINE = "nanopi5_defconfig"

COMPATIBLE_MACHINE = "nanopi-zero2"

# U-Boot 2017.09 is quite old, but should work with Python 3
# Note: Some older U-Boot scripts may expect Python 2, but most work with Python 3

# Extra make arguments for Rockchip
EXTRA_OEMAKE += "BL31=${DEPLOY_DIR_IMAGE}/bl31-rk3528.elf"

do_configure:prepend() {
    # Clean source directory to avoid "not clean" error with out-of-tree builds
    cd ${S}
    if [ -f ${S}/.config -o -d ${S}/include/config ]; then
        oe_runmake mrproper
    fi
}

do_compile:prepend() {
    # Ensure BL31 is available
    if [ ! -f ${DEPLOY_DIR_IMAGE}/bl31-rk3528.elf ]; then
        bbwarn "BL31 binary not found, U-Boot may not build correctly"
    fi
}

# Deploy additional Rockchip-specific files
do_deploy:append() {
    # Deploy idbloader (TPL+SPL combined)
    if [ -f ${B}/idbloader.img ]; then
        install -m 644 ${B}/idbloader.img ${DEPLOYDIR}/idbloader.img
    fi

    # Deploy trust.img if it exists
    if [ -f ${B}/trust.img ]; then
        install -m 644 ${B}/trust.img ${DEPLOYDIR}/trust.img
    fi

    # Deploy u-boot.itb (FIT image with ATF)
    if [ -f ${B}/u-boot.itb ]; then
        install -m 644 ${B}/u-boot.itb ${DEPLOYDIR}/u-boot.itb
    fi
}
