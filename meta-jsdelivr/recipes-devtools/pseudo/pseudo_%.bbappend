FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# Host tar with the CVE-2025-45582 fix (Ubuntu jammy tar >= 1.34+dfsg-1ubuntu0.1.22.04.4)
# uses the raw openat2() syscall, which pseudo cannot intercept via LD_PRELOAD,
# breaking do_package. Force the openat() fallback path instead.
SRC_URI += "file://0001-ports-linux-return-ENOSYS-for-openat2.patch"
