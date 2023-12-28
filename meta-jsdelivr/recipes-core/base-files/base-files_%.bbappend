do_install:append () {
    echo "Global Ping Hardware Probe V2" > ${D}${sysconfdir}/issue
    echo "Global Ping Hardware Probe V2" > ${D}${sysconfdir}/issue.net
}
