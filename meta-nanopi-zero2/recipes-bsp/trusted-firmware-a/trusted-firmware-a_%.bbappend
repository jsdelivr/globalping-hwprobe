COMPATIBLE_MACHINE:nanopi-zero2 = "nanopi-zero2"

# TFA platform for RK3528
# Note: RK3528 may not have full TFA support in mainline
# FriendlyElec typically uses pre-built BL31 from Rockchip
# For now, continue using RK3328 as it's the closest match
TFA_PLATFORM:nanopi-zero2 = "rk3328"
TFA_BUILD_TARGET:nanopi-zero2 = "bl31"

# Deploy with RK3528 name for U-Boot compatibility
do_deploy:append:nanopi-zero2() {
    cd ${DEPLOYDIR}
    if [ -f bl31-rk3328.elf ] && [ ! -f bl31-rk3528.elf ]; then
        ln -sf bl31-rk3328.elf bl31-rk3528.elf
    fi
}