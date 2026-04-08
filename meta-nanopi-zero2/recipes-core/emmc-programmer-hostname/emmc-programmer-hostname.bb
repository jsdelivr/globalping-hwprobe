SUMMARY = "eMMC Programmer hostname configuration"
DESCRIPTION = "Sets hostname to emmc-programmer-XXXX where XXXX is 2 random hex bytes"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit systemd

SRC_URI = " \
    file://set-emmc-hostname.sh \
    file://emmc-programmer-hostname.service \
"

S = "${WORKDIR}"

SYSTEMD_SERVICE:${PN} = "emmc-programmer-hostname.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_install() {
    # Install the hostname script
    install -d ${D}${sbindir}
    install -m 0755 ${WORKDIR}/set-emmc-hostname.sh ${D}${sbindir}/set-emmc-hostname.sh

    # Install systemd service
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/emmc-programmer-hostname.service ${D}${systemd_system_unitdir}/
}

FILES:${PN} = " \
    ${sbindir}/set-emmc-hostname.sh \
    ${systemd_system_unitdir}/emmc-programmer-hostname.service \
"
