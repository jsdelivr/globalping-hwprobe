LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"


#SRC_URI += "file://globalping-probe.frozen"
SRC_URI += "file://download-frozen-image-v2.sh"

S = "${WORKDIR}"

RDEPENDS:${PN} += "bash"
DEPENDS = "ca-certificates-native jq-native curl-native "

do_install[network] = "1"

do_install() {
	CURL_CA_BUNDLE=${STAGING_DIR_NATIVE}/etc/ssl/certs/ca-certificates.crt
	export CURL_CA_BUNDLE
	rm -rf globalping-probe.frozen
	bash ./download-frozen-image-v2.sh -d globalping-probe.frozen ghcr.io/jsdelivr/globalping-probe:latest
	tar -cC 'globalping-probe.frozen' . | gzip > globalping-probe.frozen.tar.gz
        install -d ${D}/JSDELIVR_BASE_CONTAINER
	install -m 644 ${WORKDIR}/globalping-probe.frozen.tar.gz  ${D}/JSDELIVR_BASE_CONTAINER
        install -d ${D}/${bindir}
	install -m 0755 ${WORKDIR}/download-frozen-image-v2.sh  ${D}/${bindir}
}




#Pack the path
FILES:${PN} += "/JSDELIVR_BASE_CONTAINER"
FILES:${PN} += "${bindir}"
