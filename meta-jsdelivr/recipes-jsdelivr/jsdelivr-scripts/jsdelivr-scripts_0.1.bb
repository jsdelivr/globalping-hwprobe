
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"


SRC_URI += "file://jsdelivr-startWorld.sh"
SRC_URI += "file://jsdelivr-firstBoot.sh"
SRC_URI += "file://jsdelivr-mandatoryReboot.sh"
SRC_URI += "file://jsdelivr-systemMonitor.sh"
SRC_URI += "file://jsdelivr-systemWatchdog.sh"
SRC_URI += "file://jsdelivr-updateContainer.sh"
SRC_URI += "file://jsdelivr-maxPower.sh"
SRC_URI += "file://jsdelivr-normalPower.sh"
SRC_URI += "file://jsdelivr-updateContainerAuto.sh"
SRC_URI += "file://jsdelivr-grabDevLogs.sh"




S = "${WORKDIR}"

RDEPENDS:${PN} += "bash"

#bitbake task
#created a directory /home/root for target install the script
do_install() {
             install -d ${D}${bindir}
             install -m 0755 ${WORKDIR}/jsdelivr-startWorld.sh ${D}${bindir}
             install -m 0755 ${WORKDIR}/jsdelivr-firstBoot.sh ${D}${bindir}

             install -m 0755 ${WORKDIR}/jsdelivr-mandatoryReboot.sh ${D}${bindir}
             install -m 0755 ${WORKDIR}/jsdelivr-systemMonitor.sh ${D}${bindir}
             install -m 0755 ${WORKDIR}/jsdelivr-systemWatchdog.sh ${D}${bindir}
             install -m 0755 ${WORKDIR}/jsdelivr-updateContainer.sh ${D}${bindir}

             install -m 0755 ${WORKDIR}/jsdelivr-maxPower.sh ${D}${bindir}
             install -m 0755 ${WORKDIR}/jsdelivr-normalPower.sh ${D}${bindir}
             install -m 0755 ${WORKDIR}/jsdelivr-updateContainerAuto.sh ${D}${bindir}
             install -m 0755 ${WORKDIR}/jsdelivr-grabDevLogs.sh ${D}${bindir}

}

#Pack the path
FILES_${PN} += "${bindir}"

