# jsdelivr Optional Containers System

This directory contains the infrastructure for multi-container support in jsdelivr firmware.

## Overview

The optional containers system allows you to bundle additional Docker containers alongside the main globalping-probe container. Containers can be enabled/disabled at runtime without rebuilding the firmware.

## Directory Structure

```
/JSDELIVR_BASE_CONTAINER/
├── globalping-probe.frozen          # Main container (mandatory)
├── optional/
│   ├── netdata.frozen               # Optional container images
│   ├── wireguard.frozen
│   ├── speedtest-tracker.frozen
│   └── manifest.json                # Container metadata
└── config/
    ├── enabled-containers.conf      # Default configuration
    └── *.env                        # Per-container environment files
```

## Creating Frozen Container Images

To bundle a Docker container in firmware:

1. **Pull the container on a development machine:**
   ```bash
   docker pull netdata/netdata:latest
   ```

2. **Save as frozen image (gzipped tar):**
   ```bash
   docker save netdata/netdata:latest | gzip > netdata.frozen
   ```

3. **Create a Yocto recipe:**
   ```bash
   # Copy the example from jsdelivr-container-netdata
   cp -r meta-jsdelivr/recipes-jsdelivr/jsdelivr-container-netdata \
         meta-jsdelivr/recipes-jsdelivr/jsdelivr-container-mycontainer

   # Place your frozen image in files/
   cp mycontainer.frozen \
      meta-jsdelivr/recipes-jsdelivr/jsdelivr-container-mycontainer/files/

   # Edit the .bb recipe file
   ```

4. **Add to your image:**
   ```python
   IMAGE_INSTALL_append = " jsdelivr-container-mycontainer"
   ```

## Enabling/Disabling Containers

### Build-time (Default Configuration)

Edit `enabled-containers.conf`:
```bash
# Enable Netdata
ENABLE_NETDATA=1

# Disable Wireguard
ENABLE_WIREGUARD=0
```

### Runtime (Persistent Configuration)

1. **Mount /persist as read-write:**
   ```bash
   mount -o remount,rw /persist
   ```

2. **Create persistent configuration:**
   ```bash
   mkdir -p /persist/jsdelivr-config
   cp /JSDELIVR_BASE_CONTAINER/config/enabled-containers.conf \
      /persist/jsdelivr-config/
   ```

3. **Edit the configuration:**
   ```bash
   vi /persist/jsdelivr-config/enabled-containers.conf
   # Change ENABLE_NETDATA=0 to ENABLE_NETDATA=1
   ```

4. **Remount /persist as read-only:**
   ```bash
   mount -o remount,ro /persist
   ```

5. **Reboot to apply changes:**
   ```bash
   reboot
   ```

## Container Naming Convention

Container names in configuration files must use underscores instead of hyphens:

| Container File | Docker Image | Config Variable |
|----------------|--------------|----------------|
| netdata.frozen | netdata/netdata | ENABLE_NETDATA |
| wireguard.frozen | linuxserver/wireguard | ENABLE_WIREGUARD |
| speedtest-tracker.frozen | speedtest-tracker | ENABLE_SPEEDTEST_TRACKER |

## Adding New Containers

### 1. Update manifest.json

Add your container to the manifest:

```json
{
  "name": "mycontainer",
  "frozen_image": "mycontainer.frozen",
  "docker_image": "vendor/mycontainer:latest",
  "description": "My custom container",
  "default_enabled": false,
  "startup_priority": 15,
  "required_memory_mb": 100,
  "network_mode": "host"
}
```

### 2. Create the Frozen Image

```bash
docker pull vendor/mycontainer:latest
docker save vendor/mycontainer:latest | gzip > mycontainer.frozen
```

### 3. Create a Yocto Recipe

See `jsdelivr-container-netdata` for an example.

### 4. Update Configuration

Add to `enabled-containers.conf`:
```bash
# My Container - Custom application
ENABLE_MYCONTAINER=0
```

## Monitoring and Management

### Check Container Status

```bash
docker ps -a
```

### View Logs

```bash
# Container loader logs
cat /dev/tty3

# Docker logs
docker logs globalping-probe
docker logs netdata
```

### Restart a Container

```bash
docker restart netdata
```

### Stop a Container

```bash
docker stop netdata
```

Note: Stopped containers will be automatically restarted by the watchdog loop.

## Persistent Storage Layout

The system uses two separate persistent partitions:

### /persist (Partition 4, 50MB, Read-Only by Default)
Configuration files that rarely change. Mounted read-only, remount RW to update.

```bash
/persist/
├── jsdelivr-config/              # Container configuration
│   └── enabled-containers.conf   # Which containers to enable
├── container-overrides/          # Per-container env files
│   └── netdata.env               # Environment overrides
└── jsdelivr_controller.settings  # Controller settings
```

### /docker_persist (Partition 6, ~50% of remaining space, Read-Write)
Container volumes that are written to at runtime.

```bash
/docker_persist/
├── wireguard/          # Wireguard VPN configuration
└── speedtest/          # Speedtest Tracker data/database
```

## Resource Considerations

### Memory Usage
- globalping-probe: ~100MB
- netdata: ~50-100MB
- wireguard: ~20MB
- speedtest-tracker: ~150MB

**Total for all containers:** ~320-370MB

### Disk Space
Each frozen image adds to firmware size:
- netdata.frozen: ~200MB
- wireguard.frozen: ~40MB
- speedtest-tracker.frozen: ~150MB

**Plan disk usage accordingly!**

## Troubleshooting

### Container Not Starting

1. Check if enabled:
   ```bash
   grep ENABLE_ /persist/jsdelivr-config/enabled-containers.conf
   ```

2. Check Docker logs:
   ```bash
   docker logs <container-name>
   ```

3. Check if image loaded:
   ```bash
   docker images
   ```

### Container Keeps Restarting

Check resource constraints:
```bash
docker stats
free -m
```

### Persistent Config Not Applied

Verify the file exists and has correct permissions:
```bash
ls -la /persist/jsdelivr-config/enabled-containers.conf
```

## Example: Enabling Netdata

1. **Check if netdata.frozen is included in firmware:**
   ```bash
   ls -lh /JSDELIVR_BASE_CONTAINER/optional/netdata.frozen
   ```

2. **Enable in persistent config:**
   ```bash
   mount -o remount,rw /persist
   mkdir -p /persist/jsdelivr-config
   echo "ENABLE_NETDATA=1" > /persist/jsdelivr-config/enabled-containers.conf
   mount -o remount,ro /persist
   ```

3. **Reboot:**
   ```bash
   reboot
   ```

4. **Access Netdata UI:**
   Open browser to: `http://<device-ip>:19999`

## Advanced: Custom Container Configurations

Create custom environment files for containers:

```bash
# /persist/container-overrides/netdata.env
TZ=America/New_York
NETDATA_CLAIM_TOKEN=your-token-here
```

The loader will automatically use override files if present.
