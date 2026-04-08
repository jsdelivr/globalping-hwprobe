# RAUC Boot Handlers for NanoPi Zero2
# Provides boot slot verification and mark-good services
#
# These handlers work with the legacy_boot GPT flag mechanism
# for A/B partition boot selection.

SUMMARY = "RAUC boot slot handlers for NanoPi Zero2"
DESCRIPTION = "Boot verification and mark-good scripts for RAUC A/B updates"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://rauc-boot-check.sh \
    file://rauc-mark-good.sh \
    file://rauc-boot-check.service \
    file://rauc-mark-good.service \
"

S = "${WORKDIR}"

inherit systemd

SYSTEMD_SERVICE:${PN} = "rauc-boot-check.service rauc-mark-good.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

do_install() {
    # Install scripts to /usr/lib/rauc
    install -d ${D}${libdir}/rauc
    install -m 0755 ${WORKDIR}/rauc-boot-check.sh ${D}${libdir}/rauc/
    install -m 0755 ${WORKDIR}/rauc-mark-good.sh ${D}${libdir}/rauc/

    # Install systemd service files
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/rauc-boot-check.service ${D}${systemd_system_unitdir}/
    install -m 0644 ${WORKDIR}/rauc-mark-good.service ${D}${systemd_system_unitdir}/
}

FILES:${PN} = " \
    ${libdir}/rauc/rauc-boot-check.sh \
    ${libdir}/rauc/rauc-mark-good.sh \
    ${systemd_system_unitdir}/rauc-boot-check.service \
    ${systemd_system_unitdir}/rauc-mark-good.service \
"

# Runtime dependencies
RDEPENDS:${PN} = " \
    rauc \
    parted \
"

# Our rauc-mark-good.service replaces the one from rauc-mark-good package
RCONFLICTS:${PN} = "rauc-mark-good"
RREPLACES:${PN} = "rauc-mark-good"
RPROVIDES:${PN} = "rauc-mark-good"
