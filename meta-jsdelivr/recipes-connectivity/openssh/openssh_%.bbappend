


do_install:append () {
        sed -i 's/PermitRootLogin//' ${D}${sysconfdir}/ssh/sshd_config_readonly
        echo "Match User logs "   >> ${D}${sysconfdir}/ssh/sshd_config_readonly
        echo "\t#PasswordAuthentication yes "   >> ${D}${sysconfdir}/ssh/sshd_config_readonly
        echo "\tAllowTCPForwarding no "   >> ${D}${sysconfdir}/ssh/sshd_config_readonly
        echo "\tForceCommand /bin/bash -c \"/usr/bin/docker logs globalping-probe -f \"  teste190  "   >> ${D}${sysconfdir}/ssh/sshd_config_readonly
}