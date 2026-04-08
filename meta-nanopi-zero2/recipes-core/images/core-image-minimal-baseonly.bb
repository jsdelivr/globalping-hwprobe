require recipes-core/images/core-image-minimal.bb

DESCRIPTION = "Minimal image with only base globalping-probe container (no optional containers)"

# Remove optional containers and their dependencies
# Must remove both the manager and ALL individual frozen container packages
IMAGE_INSTALL:remove = "jsdelivr-container-manager jsdelivr-optional-containers"
IMAGE_INSTALL:remove += "jsdelivr-container-crowdsec jsdelivr-container-netdata jsdelivr-container-wireguard"

# Keep base jsdelivpackages (includes globalping-probe)
# Note: jsdelivr-service, jsdelivr-scripts, jsdelivr-configure, jsdelivr-basecontainer are still included from local.conf
