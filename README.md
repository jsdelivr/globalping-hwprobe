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

## Flashing the sdcard

This could be flashed to the SDCARD using Raspberry PI Imager, balenaEtecher, Rufus or another similar product.

After the sdcard is correctly flashed and verified it can be inserted into the GlobalPing hardware probe and the probe powered up.


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

The code that runs inside the container is automatically updated, with multiple ways of doing it (in probe code and in the script code that starts the container )

## Security

These safe guards were used make the Hardware Probe as secure as possible:

 - The rootfs of the probe OS is read-only so that any unknown exploit 
 - Kernel configuration was tunned to reduce the size and exploitable area
 - The Container is completely run from RAM, to eliminate persisted exploits
 - The OS will automatically reboot every 3 days to clear any possible exploit 
 - The only user that is illegible to use SSH is the "logs" user, and that doesn't have a shell
 - The OS was trimmed to have the minimum attack surface
 


