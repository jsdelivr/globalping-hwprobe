FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# Create mount point directories for persistent storage
# Remove /etc/hostname to allow dynamic hostname generation
do_install:append() {
    install -d ${D}/persist
    install -d ${D}/docker_persist

    # Remove /etc/hostname - system will generate hostname dynamically
    rm -f ${D}${sysconfdir}/hostname
}
