SUMMARY = "Speedtest Tracker Container - Frozen Docker Image"
DESCRIPTION = "Provides the frozen Docker image for Speedtest Tracker internet speed testing"
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

	# Pull Speedtest Tracker container image
	rm -rf speedtest-tracker.frozen
	skopeo --override-arch arm64 copy \
		docker://ghcr.io/alexjustesen/speedtest-tracker:latest \
		docker-archive:speedtest-tracker.frozen:ghcr.io/alexjustesen/speedtest-tracker:latest

	# Install to optional containers directory
	install -d ${D}/JSDELIVR_BASE_CONTAINER/optional
	install -m 0644 ${WORKDIR}/speedtest-tracker.frozen \
		${D}/JSDELIVR_BASE_CONTAINER/optional/
}

FILES:${PN} = "/JSDELIVR_BASE_CONTAINER/optional/speedtest-tracker.frozen"
