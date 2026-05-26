SUMMARY = "wireguard Container - Frozen Docker Image"
DESCRIPTION = "Custom container: linuxserver/wireguard:latest"
HOMEPAGE = "https://github.com/jsdelivr/globalping-hwprobe"
SECTION = "containers"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

S = "${WORKDIR}"

inherit allarch

DEPENDS = "ca-certificates-native curl-native skopeo-native"

# Requires optional containers infrastructure
RDEPENDS:${PN} = "jsdelivr-optional-containers"

do_install[network] = "1"

do_install() {
	CURL_CA_BUNDLE=${STAGING_DIR_NATIVE}/etc/ssl/certs/ca-certificates.crt
	export CURL_CA_BUNDLE

	# Pull container image
	rm -rf wireguard.frozen
	skopeo --override-arch arm64 copy \
		docker://linuxserver/wireguard:latest \
		docker-archive:wireguard.frozen:linuxserver/wireguard:latest

	# Install to optional containers directory
	install -d ${D}/JSDELIVR_BASE_CONTAINER/optional
	install -m 0644 ${WORKDIR}/wireguard.frozen \
		${D}/JSDELIVR_BASE_CONTAINER/optional/
}

FILES:${PN} = "/JSDELIVR_BASE_CONTAINER/optional/wireguard.frozen"
