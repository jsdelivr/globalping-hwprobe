# meta-nanopi-zero2

Yocto BSP layer for the FriendlyElec NanoPi Zero2 board based on Rockchip RK3528A SoC.

## Description

This layer provides support for the NanoPi Zero2, a compact single-board computer featuring:
- Rockchip RK3528A Quad-core ARM Cortex-A53 @ 2.0GHz
- 1GB/2GB LPDDR4X RAM
- Gigabit Ethernet
- USB 2.0 ports
- M.2 Key-E socket for WiFi module
- 45x45mm form factor

## Dependencies

This layer depends on:

* meta-openembedded
  - URI: https://git.openembedded.org/meta-openembedded
  - layers: meta-oe, meta-python, meta-networking

* meta-rockchip
  - URI: https://git.yoctoproject.org/meta-rockchip
  - branch: master/scarthgap

## Quick Start

1. Add this layer to your build configuration:
   ```bash
   bitbake-layers add-layer meta-nanopi-zero2
   ```

2. Set the machine in `conf/local.conf`:
   ```
   MACHINE = "nanopi-zero2"
   ```

3. Build an image:
   ```bash
   bitbake core-image-minimal
   ```

## Current Status

**Note**: This layer is a work-in-progress. The RK3528A SoC has limited mainline kernel support:
- Linux 6.1 vendor kernel (FriendlyElec nanopi6-v6.1.y branch) is recommended
- U-Boot v2017.09 (FriendlyElec nanopi5-v2017.09 branch)
- Mainline support is minimal (basic clock driver in Linux 6.15+)

### Known Limitations

- Requires vendor-specific kernel and U-Boot (not fully mainlined)
- DDR and BL31 binaries from Rockchip needed
- Some peripherals may require additional device tree work

## Contributing

Patches and improvements are welcome! This layer was created based on meta-rockchip structure.

## Maintainer

This layer is community-maintained.

## License

MIT