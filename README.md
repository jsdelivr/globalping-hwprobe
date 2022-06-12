## Globalping Hardware Probe Firmware

This is the firmware of the hardware probe we ship to our supporters. It was tested only on our specific ARM-v6 probes and we don't guarantee it will work correctly on other similar devices.
As a user there it is not necessary to update your firmware unless something breaks or you need to replace the SD card.

## Download the latest firmware

TODO | Download links

## Flashing the SD card

The compiled firmware could be flashed to the SDCARD using Raspberry PI Imager, balenaEtecher, Rufus or other similar software.

After the SD Card is correctly flashed and verified it can be inserted into the Globalping hardware probe and the probe powered up.


## Hardware Probe startup process

 1. After power-up the red LED will be on for the first 17 seconds
 2. After this, the red LED will turn off and the green LED will start blinking
 3. When the probe software has been started the green LED will go solid.

## Errors 

 - ### Solid red LED ( the green LED never turns on)
      If during the startup process the green LED never turn's on, it could be a flash sdcard issue or the sdcard is not correctly installed on the slot.
 - ### Blinking red LED
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

In addition to the [security features of the software probe](https://github.com/jsdelivr/globalping-probe#security) these are the extra safe guards were used to make the hardaware device as secure as possible:

 - The rootfs of the probe OS is read-only 
 - The kernel configuration was tunned to reduce the size and exploitable area
 - The probe container is completely run from RAM
 - The OS will automatically reboot every 3 days
 - The only user that is eligible to use SSH is the "logs" user, without shell access
 - The OS was trimmed to have minimum attack surface
 
## Building the firmware

To install bitbake and all its dependencies:

```
sudo apt-get install bitbake
```

Then run the next command to download and build the firmware for the globalping hardware probes.
NOTE: this process will take a couple of hours

```
git clone https://github.com/jsdelivr/globalping-hwprobe
bash build_firmware.sh 
```

When the build process finishes a firmware file with the extension ".sunxi-sdimg" will be in the current directory 


