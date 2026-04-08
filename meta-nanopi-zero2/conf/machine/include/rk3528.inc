# RK3528 SoC configuration
# Rockchip RK3528A Quad-core ARM Cortex-A53 @ 2.0GHz

SOC_FAMILY = "rk3528"

DEFAULTTUNE ?= "cortexa53-crypto"

require conf/machine/include/soc-family.inc
require conf/machine/include/rockchip-defaults.inc
require conf/machine/include/arm/armv8a/tune-cortexa53.inc
require conf/machine/include/rockchip-wic.inc

KBUILD_DEFCONFIG ?= "nanopi5_linux_defconfig"
KERNEL_CLASSES = "kernel-fitimage"
KERNEL_IMAGETYPE ?= "fitImage"

SERIAL_CONSOLES = "1500000;ttyFIQ0"

# TFA Platform
TFA_PLATFORM = "rk3528"
TFA_BUILD_TARGET = "bl31"

UBOOT_SUFFIX ?= "itb"
UBOOT_ENTRYPOINT ?= "0x06000000"

ENABLE_STATELESS_VPU_GST ?= "1"