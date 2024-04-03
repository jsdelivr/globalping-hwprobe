LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"


S = "${WORKDIR}"

RDEPENDS:${PN} += "bash"
DEPENDS = "ca-certificates-native jq-native curl-native skopeo-native "

do_install[network] = "1"

do_install() {
	CURL_CA_BUNDLE=${STAGING_DIR_NATIVE}/etc/ssl/certs/ca-certificates.crt
	export CURL_CA_BUNDLE
	rm -rf globalping-probe.frozen
	skopeo --override-arch arm copy docker://globalping/globalping-probe:latest docker-archive:globalping-probe.frozen:globalping-probe
        install -d ${D}/JSDELIVR_BASE_CONTAINER
	install -m 644 ${WORKDIR}/globalping-probe.frozen  ${D}/JSDELIVR_BASE_CONTAINER
        #install -d ${D}/${bindir}
	#install -m 0755 ${WORKDIR}/download-frozen-image-v2.sh  ${D}/${bindir}
}




#Pack the path
FILES:${PN} += "/JSDELIVR_BASE_CONTAINER"
FILES:${PN} += "${bindir}"
