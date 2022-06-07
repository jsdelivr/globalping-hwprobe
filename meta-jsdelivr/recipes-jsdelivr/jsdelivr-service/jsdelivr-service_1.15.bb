SECTION = "devel"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit allarch  systemd


SRC_URI += "file://jsdelivr.service"
SRC_URI += "file://firstboot.service"
SRC_URI += "file://firstboot.sh"




# Keeps the sysvinit scripts out of the image if building
# where systemd is in use.
SYSTEMD_PACKAGES = "${PN}"
SYSTEMD_SERVICE:${PN} += "jsdelivr.service"
SYSTEMD_SERVICE:${PN} += "firstboot.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"


do_install() {
	install -d ${D}${systemd_unitdir}/system
	install -m 644 ${WORKDIR}/jsdelivr.service ${D}/${systemd_unitdir}/system
	install -m 644 ${WORKDIR}/firstboot.service ${D}/${systemd_unitdir}/system
	install -d ${D}${bindir}
	install -m 0755 ${WORKDIR}/firstboot.sh ${D}/${bindir}
}

FILES_${PN} += "${bindir}"
