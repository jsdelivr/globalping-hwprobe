SUMMARY = "jsdelivr Container Manager - Multi-container support system"
DESCRIPTION = "Provides scripts and infrastructure for loading and managing optional Docker containers alongside globalping-probe"
HOMEPAGE = "https://github.com/jsdelivr/globalping-hwprobe"
SECTION = "scripts"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit allarch

SRC_URI = "file://jsdelivr-container-loader.sh"

# No dependency on Docker recipe, as it's already provided by the image
RDEPENDS:${PN} = "bash docker jq"

do_install() {
    # Install container loader script
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/jsdelivr-container-loader.sh ${D}${bindir}/
}

FILES:${PN} = "${bindir}/jsdelivr-container-loader.sh"
