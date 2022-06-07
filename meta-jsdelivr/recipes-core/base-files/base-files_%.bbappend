do_install:append () {
    echo "Global Ping Hardware Probe V1" > ${D}${sysconfdir}/issue
    echo "Global Ping Hardware Probe V1" > ${D}${sysconfdir}/issue.net
}
