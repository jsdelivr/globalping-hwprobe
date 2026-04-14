SUMMARY = "FriendlyElec Linux kernel for NanoPi Zero2"
DESCRIPTION = "Linux kernel from FriendlyElec's kernel-rockchip repository"
HOMEPAGE = "https://github.com/friendlyarm/kernel-rockchip"
SECTION = "kernel"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=6bc538ed5bd9a7fc9398086aedcd7e46"

inherit kernel
require recipes-kernel/linux/linux-yocto.inc

LINUX_VERSION ?= "6.1.118"
LINUX_VERSION_EXTENSION = "-friendlyarm"

# Skip version sanity check since we're using pinned commit
KERNEL_VERSION_SANITY_SKIP = "1"

# Kernel version pinned on 2025-10-11 (tested and working)
# Commit: arm64: dts: rockchip: rk3588: Add clk PCLK_PHP_ROOT to pcie30phy
# Date: Thu Aug 7 14:29:04 2025
SRCREV = "4944602540b62f5aad139fe602a76cf7c3176128"
SRC_URI = "git://github.com/friendlyarm/kernel-rockchip.git;protocol=https;branch=nanopi6-v6.1.y"

SRC_URI:append = " \
    file://nanopi-zero2-docker.cfg \
    file://zstd-compression.cfg \
    file://enable-watchdog.cfg \
    file://rauc-streaming.cfg \
    file://disable-unused-drivers.cfg \
    file://0001-fix-bootargs-root-device-for-yocto.patch \
    file://0002-enable-hardware-watchdog.patch \
    file://0003-swap-led-triggers-green-heartbeat-red-panic.patch \
    file://0004-fix-phy-rockchip-samsung-dcphy-kconfig-dependency.patch \
"

# Override configs via sed (more reliable than defconfig patches)
do_configure:append() {
    # Disable HID and input devices
    sed -i 's/^CONFIG_HID=.*/# CONFIG_HID is not set/' ${B}/.config || true
    sed -i 's/^CONFIG_USB_HID=.*/# CONFIG_USB_HID is not set/' ${B}/.config || true
    sed -i 's/^CONFIG_INPUT_MOUSEDEV=.*/# CONFIG_INPUT_MOUSEDEV is not set/' ${B}/.config || true
    sed -i 's/^CONFIG_INPUT_JOYSTICK=.*/# CONFIG_INPUT_JOYSTICK is not set/' ${B}/.config || true
    sed -i 's/^CONFIG_INPUT_TOUCHSCREEN=.*/# CONFIG_INPUT_TOUCHSCREEN is not set/' ${B}/.config || true
    sed -i 's/^CONFIG_INPUT_TABLET=.*/# CONFIG_INPUT_TABLET is not set/' ${B}/.config || true

    # Disable DRM and all display drivers
    sed -i 's/^CONFIG_DRM=.*/# CONFIG_DRM is not set/' ${B}/.config || true
    sed -i 's/^CONFIG_DRM_ROCKCHIP=.*/# CONFIG_DRM_ROCKCHIP is not set/' ${B}/.config || true

    # Disable Mali GPU drivers
    sed -i 's/^CONFIG_MALI400=.*/# CONFIG_MALI400 is not set/' ${B}/.config || true
    sed -i 's/^CONFIG_MALI450=.*/# CONFIG_MALI450 is not set/' ${B}/.config || true
    sed -i 's/^CONFIG_MALI_MIDGARD=.*/# CONFIG_MALI_MIDGARD is not set/' ${B}/.config || true
    sed -i 's/^CONFIG_MALI_BIFROST=.*/# CONFIG_MALI_BIFROST is not set/' ${B}/.config || true
    sed -i 's/^CONFIG_MALI_SHARED_INTERRUPTS=.*/# CONFIG_MALI_SHARED_INTERRUPTS is not set/' ${B}/.config || true
    sed -i 's/^CONFIG_MALI_DT=.*/# CONFIG_MALI_DT is not set/' ${B}/.config || true
    sed -i 's/^CONFIG_MALI_DEVFREQ=.*/# CONFIG_MALI_DEVFREQ is not set/' ${B}/.config || true

    # Disable USB Serial, ACM, Printer
    sed -i 's/^CONFIG_USB_SERIAL=.*/# CONFIG_USB_SERIAL is not set/' ${B}/.config || true
    sed -i 's/^CONFIG_USB_ACM=.*/# CONFIG_USB_ACM is not set/' ${B}/.config || true
    sed -i 's/^CONFIG_USB_PRINTER=.*/# CONFIG_USB_PRINTER is not set/' ${B}/.config || true

    # Disable USB Network adapters
    sed -i 's/^CONFIG_USB_USBNET=.*/# CONFIG_USB_USBNET is not set/' ${B}/.config || true

    # Disable Bluetooth
    sed -i 's/^CONFIG_BT=.*/# CONFIG_BT is not set/' ${B}/.config || true

    # Disable WiFi/Wireless
    sed -i 's/^CONFIG_CFG80211=.*/# CONFIG_CFG80211 is not set/' ${B}/.config || true
    sed -i 's/^CONFIG_MAC80211=.*/# CONFIG_MAC80211 is not set/' ${B}/.config || true
    sed -i 's/^CONFIG_WLAN=.*/# CONFIG_WLAN is not set/' ${B}/.config || true

    # Disable Sound/Audio
    sed -i 's/^CONFIG_SOUND=.*/# CONFIG_SOUND is not set/' ${B}/.config || true
    sed -i 's/^CONFIG_SND=.*/# CONFIG_SND is not set/' ${B}/.config || true

    # Disable Media/DVB/V4L2
    sed -i 's/^CONFIG_MEDIA_SUPPORT=.*/# CONFIG_MEDIA_SUPPORT is not set/' ${B}/.config || true
    sed -i 's/^CONFIG_VIDEO_DEV=.*/# CONFIG_VIDEO_DEV is not set/' ${B}/.config || true

    # Disable IR Remote
    sed -i 's/^CONFIG_RC_CORE=.*/# CONFIG_RC_CORE is not set/' ${B}/.config || true

    # Disable NFC
    sed -i 's/^CONFIG_NFC=.*/# CONFIG_NFC is not set/' ${B}/.config || true

    # Disable IIO (Industrial I/O)
    sed -i 's/^CONFIG_IIO=.*/# CONFIG_IIO is not set/' ${B}/.config || true

    # Disable Rockchip Headset driver (depends on IIO but doesn't declare it - Kconfig bug)
    sed -i 's/^CONFIG_RK_HEADSET=.*/# CONFIG_RK_HEADSET is not set/' ${B}/.config || true

    # Disable CAN bus
    sed -i 's/^CONFIG_CAN=.*/# CONFIG_CAN is not set/' ${B}/.config || true

    # Disable USB Gadget
    sed -i 's/^CONFIG_USB_GADGET=.*/# CONFIG_USB_GADGET is not set/' ${B}/.config || true

    # Rerun oldconfig to resolve dependencies
    oe_runmake -C ${S} O=${B} oldconfig

    # Enable NBD (Network Block Device) as built-in for RAUC streaming updates
    # MUST be after oldconfig or it gets reset to =m
    sed -i 's/^CONFIG_BLK_DEV_NBD=.*/CONFIG_BLK_DEV_NBD=y/' ${B}/.config || true
    sed -i 's/^# CONFIG_BLK_DEV_NBD is not set/CONFIG_BLK_DEV_NBD=y/' ${B}/.config || true
}

S = "${WORKDIR}/git"

KBUILD_DEFCONFIG = "nanopi5_linux_defconfig"

COMPATIBLE_MACHINE = "nanopi-zero2"

# Use FriendlyElec's device tree for RK3528
KERNEL_DEVICETREE = "rockchip/rk3528-nanopi-rev01.dtb"

# Additional kernel configuration
do_configure:prepend() {
    # Use the defconfig from FriendlyElec
    if [ -f ${S}/arch/${ARCH}/configs/${KBUILD_DEFCONFIG} ]; then
        cp ${S}/arch/${ARCH}/configs/${KBUILD_DEFCONFIG} ${B}/.config
    else
        bbwarn "Defconfig ${KBUILD_DEFCONFIG} not found, using default"
    fi
}
