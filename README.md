## Globalping Hardware Probe Firmware

This is the firmware of the hardware probe we ship to our supporters. It was tested only on our specific ARM-v6 probes and we don't guarantee it will work correctly on other similar devices.
As a user it is not necessary to update your firmware unless something breaks or you need to replace the SD card.

[How to get a Globalping hardware probe](https://github.com/jsdelivr/globalping-probe#hardware-probes)

## Download the latest firmware

Check the [Releases](https://github.com/jsdelivr/globalping-hwprobe/releases)

The gz file is ready to get flashed to your SD Card, no preparation required.

## Flashing the SD card

The compiled firmware can be flashed to an SD card using Raspberry PI Imager, balenaEtcher, Rufus or other similar software.

After the SD Card is correctly flashed and verified it can be inserted into the Globalping hardware probe and the probe powered up.


## Hardware Probe startup process

 1. After power-up the red LED will be on for the first 17 seconds
 2. After this, the red LED will turn off and the green LED will start blinking
 3. When the probe software has been started the green LED will go solid.

## Errors 

 - #### Solid red LED ( the green LED never turns on)
      If during the startup process the green LED never turn's on, it could be a flash sdcard issue or the sdcard is not correctly installed on the slot.
 - #### Blinking red LED
      Probe Software has failed, and the software restart is being done  (should jump to solid Green when finishes).

## Updates

The actual probe code that runs inside a docker container on the device is automatically updated. [Learn more about the probe code](https://github.com/jsdelivr/globalping-probe#readme)

## Accessing the probe

For security reasons there is no way to get shell access of a running probe. But for debugging purposes you can connect to it via SSH to get the logs of the software probe. To connect:

1. Login into your router's web UI and check the list of connected devices. You should be able to spot the globalping hardware probe in the list.
2. Get the IP address of the probe
3. Login via ssh `ssh logs@IP_ADDRESS` e.g. `ssh logs@192.168.1.145`
4. You can now see the log output of the docker container running the software probe on your device.

## Security

In addition to the [security features of the software probe](https://github.com/jsdelivr/globalping-probe#security) these are the extra safe guards we used to make the hardware device as secure as possible:

 - The rootfs of the probe OS is read-only 
 - The kernel configuration was tunned to reduce the size and exploitable area
 - The probe container runs completely from RAM
 - The OS will automatically reboot every 3 days + random amount of hours between 1 and 48.
 - The only user that is eligible to use SSH is the "logs" user, without shell access
 - The OS was trimmed to have minimum attack surface
 
## Building the firmware

The script was tested on Ubuntu 20.04 LTS.
First install the required software:

```
apt install gawk wget git diffstat unzip texinfo gcc build-essential chrpath socat cpio python3 python3-pip python3-pexpect xz-utils debianutils iputils-ping python3-git python3-jinja2 libegl1-mesa libsdl1.2-dev pylint3 xterm python3-subunit mesa-common-dev zstd liblz4-tool
```

Next create a user for the compilation process and clone this repo locally.
```
useradd -m compiler
su compiler
bash
cd /home/compiler
git clone https://github.com/jsdelivr/globalping-hwprobe
```

You can now run the bash script that will download all the necessary dependencies and build the firmware.
NOTE: This process can take a couple of hours

```
cd globalping-hwprobe
bash build_firmware.sh 
```

After the build is done a firmware file with the extension ".sunxi-sdimg" will appear in the current directory.

## USB update

The probe firmware can upgrade the container itself using a USB flash drive as the initiator for the process but not as a method of offline upgrade. This is done as a security measure to avoid "Evil maid " type of attacks. 

#### USB update key
To create the USB update key is just a matter of using a USB flash drive formatted as fat with a file named "JSDELIVR.UPD" in its root.
The file can be empty as its presence is checked, not the file content.

After the USB drive preparation is done, plug the USB Flash drive in the probe and power cycle it
The probe will detect the USB flash and check for the presence of the update key file.
If it's present, the upgrade process will start, with a rapid flashing of the GREEN led. At the end of the process, the initiator file  "JSDELIVR.UPD" will be erased, and the probe automatically reboots.


#### USB factory reset key
If by any chance there is a need to go back to the container version bundled with the probe firmware, this can be quickly done by doing the same process as the USB Update, but instead with a file named "JSDELIVR.RESET"

