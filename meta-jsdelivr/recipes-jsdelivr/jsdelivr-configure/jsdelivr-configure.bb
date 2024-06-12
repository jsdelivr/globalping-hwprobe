
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"



SRC_URI = "file://sshd_config_readonly_jsdelivr "

S = "${WORKDIR}"

inherit useradd 


USERADD_PACKAGES = "${PN}"

GROUPADD_PARAM:${PN} = " -g 800 docker"

USERADD_PARAM:${PN} = "-m -u 300 -d /home/logs -r -p '' -g docker logs; -m -u 301 -d /home/devlogs -r -p '' -g docker devlogs "


do_install() {
        install -d ${D}${sysconfdir}/ssh
        install -m 644 ${WORKDIR}/sshd_config_readonly_jsdelivr ${D}${sysconfdir}/ssh
}



FILES_${PN}  = "/home/logs/* /home/devlogs/*"

INHIBIT_PACKAGE_DEBUG_SPLIT = "1"

DIRFILES = "1"