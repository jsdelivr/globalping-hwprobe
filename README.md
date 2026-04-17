## Globalping Hardware Probe V2 Firmware

This is the firmware of [the hardware probe we ship to our supporters](https://github.com/jsdelivr/globalping-probe#hardware-probes). It runs on the NanoPi Zero2 (Rockchip RK3528A SoC) with eMMC storage and is built using Yocto Scarthgap 5.0.

The firmware needs to be updated from time to time. The probe will periodically log a warning when an update is needed. If you registered the probe on our [dashboard](https://dash.globalping.io/), you'll also be notified there.

[How to get a Globalping hardware probe](https://www.jsdelivr.com/globalping)

## Download the latest firmware

Check the [Releases](https://github.com/jsdelivr/globalping-hwprobe/releases), where a prepared image file is available for each release.

The eMMC Programmer image can be flashed to an SD card using [Raspberry PI Imager](https://www.raspberrypi.com/software/), [balenaEtcher](https://etcher.balena.io/), [Rufus](https://rufus.ie/), or other similar software.

After the SD card is correctly flashed and verified, insert it into the NanoPi Zero2 and power up. The programmer will automatically write the production image to eMMC, verify it, and signal success with both LEDs solid. Remove the SD card and reboot to start from eMMC.

## Hardware Probe startup process

 1. After power-up, the green LED will blink slowly (1s on/1s off)
 2. When the container starts, the green LED will blink fast (100ms on/100ms off)
 3. When the probe software is running and stable, the green LED will go solid

## LED Status

 - #### Solid green LED (red LED off)
      Normal operation. The probe software is running and stable.
 - #### Fast blinking green LED (red LED off)
      Container is starting up. Should transition to solid green when stable.
 - #### Slow blinking green LED (red LED off)
      System is booting up.
 - #### Fast blinking red LED (green LED off)
      Probe software has failed. The system will attempt automatic recovery.
 - #### Solid red LED (green LED off)
      Boot failure. Check SD card, eMMC, or system logs.

## Updates

The probe code that runs inside a Docker container on the device is automatically updated. [Learn more about the probe code](https://github.com/jsdelivr/globalping-probe#readme)

The firmware itself can be updated over-the-air using RAUC A/B updates, which safely install to the inactive rootfs slot and roll back automatically if the new version fails to boot.

## Accessing the probe

For debugging purposes you can connect to the probe via SSH. To connect:

1. Login into your router's web UI and check the list of connected devices. You should be able to spot the globalping hardware probe in the list.
2. Get the IP address of the probe
3. Login via ssh `ssh logs@IP_ADDRESS` e.g. `ssh logs@192.168.1.145`
4. You can now see the log output of the Docker container running the software probe on your device.

To access firmware logs (only really useful to firmware devs/firmware debug), repeat the above steps but with "devlogs" instead of "logs" as the user.

## Security

In addition to the [security features of the software probe](https://github.com/jsdelivr/globalping-probe#security) these are the extra safeguards we used to make the hardware device as secure as possible:

 - The rootfs of the probe OS is read-only
 - The kernel configuration was tuned to reduce the size and exploitable area
 - The probe container runs completely from RAM
 - The OS will automatically reboot every 3 days + random amount of hours between 1 and 48
 - The OS was trimmed to have minimum attack surface
 - A/B rootfs slots with automatic rollback protect against bad firmware updates
 - A hardware watchdog reboots the device if the system becomes unresponsive

## Building the firmware

The build was tested on Ubuntu 22.04 LTS.
First, install the required software:

```
apt update -y && apt install gawk wget git diffstat unzip texinfo gcc build-essential chrpath socat cpio python3 python3-pip python3-pexpect xz-utils debianutils iputils-ping python3-git python3-jinja2 libegl1-mesa libsdl1.2-dev xterm python3-subunit mesa-common-dev zstd liblz4-tool file
```

Next, create a user for the compilation process and clone this repo locally.
```
useradd -m compiler
su compiler
bash
cd /home/compiler
git clone https://github.com/jsdelivr/globalping-hwprobe
```

NOTE for maintainers:
Before building a new version update the version inside the firmware itself.
1. Update https://github.com/jsdelivr/globalping-hwprobe/blob/master/meta-jsdelivr/recipes-jsdelivr/jsdelivr-scripts/files/jsdelivr-startWorld.sh#L6
2. Clone and build
3. Tag with the same version
4. Upload

You can now run the build script that will download all the necessary dependencies and build the firmware.
NOTE: This process can take a couple of hours

```
cd globalping-hwprobe
./setup-yocto-from-scratch.sh -y
```

After the build is done, the following images will be available in `build/tmp/deploy/images/nanopi-zero2/`:

 - `core-image-minimal-nanopi-zero2.rootfs.wic` - Production image (for direct eMMC flash or OTA)
 - `emmc-programmer-image-nanopi-zero2.rootfs.wic` - Programmer image (flash to SD card)
 - `rauc-update-bundle-nanopi-zero2-*.raucb` - RAUC bundle (for OTA updates)

## Bundling optional containers

By default `./build-complete-image.sh` produces an image with only the mandatory `globalping-probe` container. Extra containers can be bundled into the firmware with the repeatable `--add-container` flag. Each `--add-container` is followed by its own options (`--cap`, `--priority`, `--memory`, `--volume`, `--env`, ...) until the next `--add-container`.

Bind-mount sources under `/docker_persist/...` are created automatically at first boot, so the data survives RAUC A/B rootfs updates.

### CrowdSec (IPS)

```
./build-complete-image.sh \
    --add-container crowdsecurity/crowdsec:slim \
        --cap NET_ADMIN,NET_RAW --priority 1 --memory 150 \
        --volume /docker_persist/crowdsec/data:/var/lib/crowdsec/data \
        --volume /docker_persist/crowdsec/config:/etc/crowdsec
```

### Netdata (monitoring)

```
./build-complete-image.sh \
    --add-container netdata/netdata:latest \
        --cap SYS_PTRACE --priority 10 --memory 100 \
        --volume /docker_persist/netdata/lib:/var/lib/netdata \
        --volume /docker_persist/netdata/cache:/var/cache/netdata \
        --volume /docker_persist/netdata/config:/etc/netdata
```

### WireGuard (VPN)

```
./build-complete-image.sh \
    --add-container linuxserver/wireguard:latest \
        --cap NET_ADMIN,SYS_MODULE --priority 5 --memory 20 \
        --volume /docker_persist/wireguard:/config \
        --volume /lib/modules:/lib/modules:ro \
        --env PUID=0 --env PGID=0 --env TZ=Etc/UTC
```

### All three at once

```
./build-complete-image.sh \
    --add-container crowdsecurity/crowdsec:slim \
        --cap NET_ADMIN,NET_RAW --priority 1 --memory 150 \
        --volume /docker_persist/crowdsec/data:/var/lib/crowdsec/data \
        --volume /docker_persist/crowdsec/config:/etc/crowdsec \
    --add-container netdata/netdata:latest \
        --cap SYS_PTRACE --priority 10 --memory 100 \
        --volume /docker_persist/netdata/lib:/var/lib/netdata \
        --volume /docker_persist/netdata/cache:/var/cache/netdata \
        --volume /docker_persist/netdata/config:/etc/netdata \
    --add-container linuxserver/wireguard:latest \
        --cap NET_ADMIN,SYS_MODULE --priority 5 --memory 20 \
        --volume /docker_persist/wireguard:/config \
        --volume /lib/modules:/lib/modules:ro \
        --env PUID=0 --env PGID=0 --env TZ=Etc/UTC
```

Bundled containers are enabled by default (`ENABLE_<NAME>=1` is written into `enabled-containers.conf` at build time). To disable one on a running probe, copy `/etc/jsdelivr-optional-containers/enabled-containers.conf` to `/persist/jsdelivr-config/enabled-containers.conf`, flip the flag to `0`, and reboot.

## Flashing

#### eMMC Programmer (recommended)
Flash the programmer image to an SD card:
```
gunzip -c emmc-programmer-image-nanopi-zero2.wic.gz | sudo dd of=/dev/sdX bs=4M status=progress && sync
```
Insert the SD card, power up, and wait for both LEDs to go solid. Remove SD card, reboot from eMMC.


## eMMC Programmer LED Status

 - #### Solid red LED
      Initial state before programming begins, or early failure.
 - #### Fast blinking green LED
      Programming or verification in progress.
 - #### Slow blinking red LED
      Programming or verification failed.
 - #### Both red and green LEDs solid
      Programming complete and verified. Remove the SD card and reboot.

## USB update

The probe firmware can upgrade the container itself using a USB flash drive as the initiator for the process but not as a method of offline upgrade. This is done as a security measure to avoid "Evil maid" type of attacks.

#### USB update key
To create the USB update key is just a matter of using a USB flash drive formatted as FAT with a file named "JSDELIVR.UPD" in its root.
The file can be empty as its presence is checked, not the file content.

After the USB drive preparation is done, plug the USB flash drive into the probe and power cycle it.
The probe will detect the USB flash and check for the presence of the update key file.
If it's present, the upgrade process will start with a rapid flashing of the GREEN LED. At the end of the process, the initiator file "JSDELIVR.UPD" will be erased, and the probe automatically reboots.

#### USB factory reset key
If by any chance there is a need to go back to the container version bundled with the probe firmware, this can be quickly done by doing the same process as the USB Update, but instead with a file named "JSDELIVR.RESET"
