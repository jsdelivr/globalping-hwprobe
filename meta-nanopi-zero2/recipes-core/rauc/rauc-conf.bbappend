# RAUC configuration for NanoPi Zero2
# Uses GPT legacy_boot flag for A/B boot selection

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# Use our custom system.conf, CA certificate, and handlers
SRC_URI = " \
    file://system.conf \
    file://ca.cert.pem \
    file://custom-bootloader.sh \
    file://pre-install.sh \
    file://post-install.sh \
"

# CA certificate filename
RAUC_KEYRING_FILE = "ca.cert.pem"

# Install the custom bootloader backend and install handlers
do_install:append() {
    install -d ${D}${libdir}/rauc
    install -m 0755 ${WORKDIR}/custom-bootloader.sh ${D}${libdir}/rauc/custom-bootloader.sh
    install -m 0755 ${WORKDIR}/pre-install.sh ${D}${libdir}/rauc/pre-install.sh
    install -m 0755 ${WORKDIR}/post-install.sh ${D}${libdir}/rauc/post-install.sh
}

# Add handlers to package
FILES:${PN} += "${libdir}/rauc/custom-bootloader.sh"
FILES:${PN} += "${libdir}/rauc/pre-install.sh"
FILES:${PN} += "${libdir}/rauc/post-install.sh"

# RAUC needs parted for GPT flag manipulation
RDEPENDS:${PN} += "parted"
