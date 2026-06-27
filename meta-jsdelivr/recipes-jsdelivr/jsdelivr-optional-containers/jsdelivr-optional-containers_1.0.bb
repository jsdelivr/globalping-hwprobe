SUMMARY = "jsdelivr Optional Containers - Configuration and manifest"
DESCRIPTION = "Provides manifest and configuration files for optional Docker containers. Does not include actual container images."
HOMEPAGE = "https://github.com/jsdelivr/globalping-hwprobe"
SECTION = "containers"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit allarch

SRC_URI = " \
    file://manifest.json \
    file://enabled-containers.conf \
"

# Requires container manager
RDEPENDS:${PN} = "jsdelivr-container-manager"

do_install() {
    # Create directory structure
    install -d ${D}/JSDELIVR_BASE_CONTAINER/optional
    install -d ${D}/JSDELIVR_BASE_CONTAINER/config

    # Install manifest
    install -m 0644 ${WORKDIR}/manifest.json \
        ${D}/JSDELIVR_BASE_CONTAINER/optional/

    # Install default configuration
    install -m 0644 ${WORKDIR}/enabled-containers.conf \
        ${D}/JSDELIVR_BASE_CONTAINER/config/
}

FILES:${PN} = "/JSDELIVR_BASE_CONTAINER /JSDELIVR_BASE_CONTAINER/*"

# Note: This recipe only provides the infrastructure
# Actual container images should be added via separate recipes
# Example: jsdelivr-container-netdata, jsdelivr-container-wireguard, etc.
