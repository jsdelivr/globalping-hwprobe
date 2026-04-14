SUMMARY = "Globalping probe system configuration"
HOMEPAGE = "https://github.com/jsdelivr/globalping-hwprobe"
SECTION = "base"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://sshd_config_readonly_jsdelivr \
    file://80-wired-jsdelivr.network \
    file://resolved-jsdelivr.conf \
    file://timesyncd-jsdelivr.conf \
"

S = "${WORKDIR}"

inherit useradd

USERADD_PACKAGES = "${PN}"

GROUPADD_PARAM:${PN} = " -g 800 docker"

USERADD_PARAM:${PN} = "-m -u 300 -d /home/logs -r -p '' -g docker logs; -m -u 301 -d /home/devlogs -r -p '' -g docker devlogs "


do_install() {
    # SSH config
    install -d ${D}${sysconfdir}/ssh
    install -m 644 ${WORKDIR}/sshd_config_readonly_jsdelivr ${D}${sysconfdir}/ssh

    # Create home directories for users (will be populated by useradd at runtime)
    install -d ${D}/home/logs
    install -d ${D}/home/devlogs

    # Network configuration - baked into image for A/B update compatibility
    # This replaces the runtime modification in jsdelivr-firstBoot.sh
    install -d ${D}${sysconfdir}/systemd/network
    install -m 644 ${WORKDIR}/80-wired-jsdelivr.network ${D}${sysconfdir}/systemd/network/80-wired.network

    # Systemd resolved drop-in config
    install -d ${D}${sysconfdir}/systemd/resolved.conf.d
    install -m 644 ${WORKDIR}/resolved-jsdelivr.conf ${D}${sysconfdir}/systemd/resolved.conf.d/jsdelivr.conf

    # Systemd timesyncd drop-in config
    install -d ${D}${sysconfdir}/systemd/timesyncd.conf.d
    install -m 644 ${WORKDIR}/timesyncd-jsdelivr.conf ${D}${sysconfdir}/systemd/timesyncd.conf.d/jsdelivr.conf

    # Create directory for device identity on persist partition
    # The actual files are created at first boot and stored on /persist
    install -d ${D}/persist
}

FILES:${PN} = " \
    ${sysconfdir}/ssh/sshd_config_readonly_jsdelivr \
    ${sysconfdir}/systemd/network/80-wired.network \
    ${sysconfdir}/systemd/resolved.conf.d/jsdelivr.conf \
    ${sysconfdir}/systemd/timesyncd.conf.d/jsdelivr.conf \
    /home/logs \
    /home/devlogs \
    /persist \
"

# Ensure this runs after systemd
RDEPENDS:${PN} = "systemd"

INHIBIT_PACKAGE_DEBUG_SPLIT = "1"
