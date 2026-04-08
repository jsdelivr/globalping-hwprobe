SUMMARY = "eMMC Programming Utility"
DESCRIPTION = "Automatically copies system image to eMMC with LED feedback"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://emmc-programmer.sh \
    file://led-control.sh \
    file://emmc-programmer.service \
"

RDEPENDS:${PN} = "bash util-linux"

inherit systemd

SYSTEMD_SERVICE:${PN} = "emmc-programmer.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/emmc-programmer.sh ${D}${bindir}/
    install -m 0755 ${WORKDIR}/led-control.sh ${D}${bindir}/

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/emmc-programmer.service ${D}${systemd_system_unitdir}/
}

FILES:${PN} = "${bindir}/* ${systemd_system_unitdir}/*"
