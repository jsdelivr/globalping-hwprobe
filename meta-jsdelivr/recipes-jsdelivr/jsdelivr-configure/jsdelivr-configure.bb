
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"



SRC_URI = "file://sshd_config_readonly_jsdelivr "

S = "${WORKDIR}"

inherit useradd 

GROUPADD_PARAM:${PN} = "docker"

USERADD_PARAM:${PN} = "-m -u 1200 -d /home/logs -r -p '' -G docker logs "

USERADD_PACKAGES = "${PN} "

do_install() {
        install -d ${D}${sysconfdir}/ssh
        install -m 644 ${WORKDIR}/sshd_config_readonly_jsdelivr ${D}${sysconfdir}/ssh
}



FILES_${PN} = "/home/logs/*"

INHIBIT_PACKAGE_DEBUG_SPLIT = "1"

DIRFILES = "1"