#!/bin/bash
#
# Add custom Docker containers to the Yocto build
#
# Usage:
#   ./add-container.sh --add-container lapsiufcg/suricata:v0.1
#   ./add-container.sh --add-container lapsiufcg/suricata:v0.1 --add-container nginx:latest
#   ./add-container.sh --add-container ghcr.io/org/image:tag --network bridge --cap NET_ADMIN,NET_RAW
#   ./add-container.sh --list
#   ./add-container.sh --remove suricata
#
# What this script does:
#   1. Generates a BitBake recipe to pull and freeze the container at build time
#   2. Adds the container to the manifest.json for runtime loading
#   3. Enables the container in enabled-containers.conf
#   4. Adds the recipe to IMAGE_INSTALL in local.conf
#
# The container will be:
#   - Pulled via skopeo during the Yocto build (arm64 architecture)
#   - Frozen as a .frozen OCI archive in /JSDELIVR_BASE_CONTAINER/optional/
#   - Loaded and started at boot by jsdelivr-container-loader.sh
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Project paths
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
RECIPES_DIR="$PROJECT_DIR/meta-jsdelivr/recipes-jsdelivr"
MANIFEST_FILE="$RECIPES_DIR/jsdelivr-optional-containers/files/manifest.json"
ENABLED_CONF="$RECIPES_DIR/jsdelivr-optional-containers/files/enabled-containers.conf"
LOCAL_CONF="$PROJECT_DIR/meta-jsdelivr/build_conf/local.conf"

# Container defaults
NETWORK_MODE="host"
RESTART_POLICY="unless-stopped"
CAPABILITIES=""
PORTS=""
MEMORY_MB=100
PRIORITY=50
DESCRIPTION=""

ACTION=""
CONTAINER_COUNT=0
HEADER_PRINTED=0

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Add containers:"
    echo "  $0 --add-container IMAGE:TAG [--add-container IMAGE2:TAG2 ...]"
    echo ""
    echo "List containers:"
    echo "  $0 --list"
    echo ""
    echo "Remove container:"
    echo "  $0 --remove NAME"
    echo ""
    echo "Options (apply to the preceding --add-container):"
    echo "  --network MODE                Docker network mode (default: host)"
    echo "  --cap CAP1,CAP2               Linux capabilities (e.g., NET_ADMIN,NET_RAW)"
    echo "  --ports PORT1,PORT2           Published ports (e.g., 8080:80,443:443)"
    echo "  --memory MB                   Required memory in MB (default: 100)"
    echo "  --priority N                  Startup priority, lower=first (default: 50)"
    echo "  --description TEXT            Container description"
    echo "  --volume SRC:TGT[:ro]         Bind mount; repeatable; SRC auto-created if missing"
    echo "  --env KEY=VALUE               Environment variable; repeatable"
    echo ""
    echo "Examples:"
    echo "  $0 --add-container lapsiufcg/suricata:v0.1"
    echo "  $0 --add-container nginx:latest --ports 8080:80"
    echo "  $0 --add-container myregistry/myapp:1.0 --cap NET_ADMIN --network bridge"
    echo "  $0 --add-container crowdsecurity/crowdsec:slim --cap NET_ADMIN,NET_RAW \\"
    echo "     --volume /docker_persist/crowdsec/data:/var/lib/crowdsec/data \\"
    echo "     --volume /docker_persist/crowdsec/config:/etc/crowdsec"
    echo "  $0 --add-container linuxserver/wireguard:latest --cap NET_ADMIN,SYS_MODULE \\"
    echo "     --volume /docker_persist/wireguard:/config --volume /lib/modules:/lib/modules:ro \\"
    echo "     --env PUID=1000 --env PGID=1000"
    echo "  $0 --list"
    echo "  $0 --remove suricata"
}

# Extract a short name from a Docker image reference
# e.g., "lapsiufcg/suricata:v0.1" -> "suricata"
#        "ghcr.io/org/my-app:latest" -> "my-app"
#        "nginx:latest" -> "nginx"
extract_name() {
    local image="$1"
    # Remove tag
    local no_tag="${image%%:*}"
    # Get last path component
    local name="${no_tag##*/}"
    # Sanitize: lowercase, replace non-alphanumeric with hyphens
    echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g'
}

# Convert name to uppercase config variable
# e.g., "suricata" -> "ENABLE_SURICATA"
#        "my-app" -> "ENABLE_MY_APP"
name_to_config_var() {
    local name="$1"
    echo "ENABLE_$(echo "$name" | tr '[:lower:]' '[:upper:]' | tr '-' '_')"
}

# Generate a BitBake recipe for a container
generate_recipe() {
    local docker_image="$1"
    local name="$2"
    local network="$3"
    local caps="$4"
    local ports="$5"
    local memory="$6"
    local priority="$7"
    local desc="$8"

    local recipe_dir="$RECIPES_DIR/jsdelivr-container-${name}"
    local recipe_file="$recipe_dir/jsdelivr-container-${name}_1.0.bb"
    local frozen_name="${name}.frozen"

    if [ -z "$desc" ]; then
        desc="Custom container: ${docker_image}"
    fi

    mkdir -p "$recipe_dir"

    cat > "$recipe_file" <<EOF
SUMMARY = "${name} Container - Frozen Docker Image"
DESCRIPTION = "${desc}"
HOMEPAGE = "https://github.com/jsdelivr/globalping-hwprobe"
SECTION = "containers"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://\${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

S = "\${WORKDIR}"

inherit allarch

DEPENDS = "ca-certificates-native curl-native skopeo-native"

# Requires optional containers infrastructure
RDEPENDS:\${PN} = "jsdelivr-optional-containers"

do_install[network] = "1"

do_install() {
	CURL_CA_BUNDLE=\${STAGING_DIR_NATIVE}/etc/ssl/certs/ca-certificates.crt
	export CURL_CA_BUNDLE

	# Pull container image
	rm -rf ${frozen_name}
	skopeo --override-arch arm64 copy \\
		docker://${docker_image} \\
		docker-archive:${frozen_name}:${docker_image}

	# Install to optional containers directory
	install -d \${D}/JSDELIVR_BASE_CONTAINER/optional
	install -m 0644 \${WORKDIR}/${frozen_name} \\
		\${D}/JSDELIVR_BASE_CONTAINER/optional/
}

FILES:\${PN} = "/JSDELIVR_BASE_CONTAINER/optional/${frozen_name}"
EOF

    echo -e "${GREEN}  Created recipe: ${recipe_file}${NC}"
}

# Add container entry to manifest.json
# Args: docker_image name network caps ports memory priority desc vol_file env_file
add_to_manifest() {
    local docker_image="$1"
    local name="$2"
    local network="$3"
    local caps="$4"
    local ports="$5"
    local memory="$6"
    local priority="$7"
    local desc="$8"
    local vol_file="$9"
    local env_file="${10}"

    local frozen_name="${name}.frozen"

    if [ -z "$desc" ]; then
        desc="Custom container: ${docker_image}"
    fi

    # Check if container already exists in manifest
    if grep -q "\"name\": \"${name}\"" "$MANIFEST_FILE"; then
        echo -e "${YELLOW}  Container '${name}' already in manifest, skipping${NC}"
        return
    fi

    MANIFEST_PATH="$MANIFEST_FILE" \
    C_NAME="$name" \
    C_FROZEN="$frozen_name" \
    C_IMAGE="$docker_image" \
    C_DESC="$desc" \
    C_PRIORITY="$priority" \
    C_MEMORY="$memory" \
    C_NETWORK="$network" \
    C_CAPS="$caps" \
    C_PORTS="$ports" \
    C_VOL_FILE="$vol_file" \
    C_ENV_FILE="$env_file" \
    python3 - <<'PYEOF'
import json, os

manifest_path = os.environ['MANIFEST_PATH']
with open(manifest_path, 'r') as f:
    manifest = json.load(f)

def read_lines(path):
    if not path or not os.path.isfile(path):
        return []
    with open(path) as f:
        return [line.rstrip('\n') for line in f if line.strip()]

volumes = []
for spec in read_lines(os.environ.get('C_VOL_FILE', '')):
    parts = spec.split(':')
    if len(parts) < 2:
        continue
    src, tgt = parts[0], parts[1]
    readonly = (len(parts) > 2 and parts[2] == 'ro')
    volumes.append({
        'type': 'bind',
        'source': src,
        'target': tgt,
        'readonly': readonly,
        'create': True,
    })

env_specs = read_lines(os.environ.get('C_ENV_FILE', ''))

new_container = {
    'name': os.environ['C_NAME'],
    'frozen_image': os.environ['C_FROZEN'],
    'docker_image': os.environ['C_IMAGE'],
    'description': os.environ['C_DESC'],
    'default_enabled': False,
    'startup_priority': int(os.environ['C_PRIORITY']),
    'required_memory_mb': int(os.environ['C_MEMORY']),
    'network_mode': os.environ['C_NETWORK'],
    'restart_policy': 'unless-stopped',
    'ports': [p for p in os.environ.get('C_PORTS', '').split(',') if p],
    'volumes': volumes,
    'capabilities': [c for c in os.environ.get('C_CAPS', '').split(',') if c],
    'env': env_specs,
}

manifest['containers'].append(new_container)

with open(manifest_path, 'w') as f:
    json.dump(manifest, f, indent=2)
    f.write('\n')
PYEOF

    echo -e "${GREEN}  Added to manifest.json${NC}"
}

# Add container to enabled-containers.conf
add_to_enabled_conf() {
    local name="$1"
    local docker_image="$2"
    local config_var
    config_var=$(name_to_config_var "$name")

    if grep -q "^${config_var}=" "$ENABLED_CONF" 2>/dev/null; then
        echo -e "${YELLOW}  ${config_var} already in enabled-containers.conf, skipping${NC}"
        return
    fi

    cat >> "$ENABLED_CONF" <<EOF

# ${docker_image}
${config_var}=1
EOF

    echo -e "${GREEN}  Added ${config_var}=1 to enabled-containers.conf${NC}"
}

# Add container recipe to local.conf IMAGE_INSTALL
add_to_local_conf() {
    local name="$1"
    local recipe_name="jsdelivr-container-${name}"

    if grep -q "${recipe_name}" "$LOCAL_CONF" 2>/dev/null; then
        echo -e "${YELLOW}  ${recipe_name} already in local.conf, skipping${NC}"
        return
    fi

    # Find the line with existing optional container frozen images and append
    if grep -q "# Optional container frozen images" "$LOCAL_CONF"; then
        # Append to the existing optional containers line
        sed -i "/^# Optional container frozen images/a\\
# Custom container: ${name}\\
IMAGE_INSTALL:append = \" ${recipe_name}\"" "$LOCAL_CONF"
    else
        # Add a new section
        echo "" >> "$LOCAL_CONF"
        echo "# Custom container: ${name}" >> "$LOCAL_CONF"
        echo "IMAGE_INSTALL:append = \" ${recipe_name}\"" >> "$LOCAL_CONF"
    fi

    echo -e "${GREEN}  Added ${recipe_name} to local.conf${NC}"
}

# List all containers (built-in + custom)
list_containers() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Configured Containers${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    if [ ! -f "$MANIFEST_FILE" ]; then
        echo -e "${RED}manifest.json not found${NC}"
        return 1
    fi

    python3 -c "
import json

with open('${MANIFEST_FILE}', 'r') as f:
    manifest = json.load(f)

for c in manifest['containers']:
    enabled = 'enabled' if c.get('default_enabled', False) else 'disabled'
    caps = ', '.join(c.get('capabilities', [])) or 'none'
    print(f\"  {c['name']:20s} {c['docker_image']:45s} priority={c['startup_priority']} mem={c['required_memory_mb']}MB caps={caps}\")
" 2>/dev/null

    echo ""

    # Also show recipe directories
    echo -e "${BLUE}Recipe directories:${NC}"
    for dir in "$RECIPES_DIR"/jsdelivr-container-*/; do
        if [ -d "$dir" ]; then
            local name
            name=$(basename "$dir")
            echo "  $name/"
        fi
    done

    echo ""
    echo -e "${BLUE}local.conf container entries:${NC}"
    grep "jsdelivr-container-" "$LOCAL_CONF" | grep -v "^#" | sed 's/^/  /'
}

# Remove a container
remove_container() {
    local name="$1"
    local recipe_dir="$RECIPES_DIR/jsdelivr-container-${name}"
    local recipe_name="jsdelivr-container-${name}"
    local config_var
    config_var=$(name_to_config_var "$name")

    echo -e "${BLUE}Removing container: ${name}${NC}"

    # Remove recipe directory
    if [ -d "$recipe_dir" ]; then
        rm -rf "$recipe_dir"
        echo -e "${GREEN}  Removed recipe directory${NC}"
    else
        echo -e "${YELLOW}  Recipe directory not found${NC}"
    fi

    # Remove from manifest.json
    if grep -q "\"name\": \"${name}\"" "$MANIFEST_FILE" 2>/dev/null; then
        python3 -c "
import json

with open('${MANIFEST_FILE}', 'r') as f:
    manifest = json.load(f)

manifest['containers'] = [c for c in manifest['containers'] if c['name'] != '${name}']

with open('${MANIFEST_FILE}', 'w') as f:
    json.dump(manifest, f, indent=2)
    f.write('\n')
" 2>/dev/null
        echo -e "${GREEN}  Removed from manifest.json${NC}"
    fi

    # Remove from enabled-containers.conf
    if grep -q "^${config_var}=" "$ENABLED_CONF" 2>/dev/null; then
        # Remove the config line and its comment line above
        sed -i "/^# .*${name}/d; /^${config_var}=/d" "$ENABLED_CONF"
        # Clean up any resulting double blank lines
        sed -i '/^$/N;/^\n$/d' "$ENABLED_CONF"
        echo -e "${GREEN}  Removed from enabled-containers.conf${NC}"
    fi

    # Remove from local.conf
    if grep -q "${recipe_name}" "$LOCAL_CONF" 2>/dev/null; then
        sed -i "/# Custom container: ${name}/d" "$LOCAL_CONF"
        sed -i "/${recipe_name}/d" "$LOCAL_CONF"
        echo -e "${GREEN}  Removed from local.conf${NC}"
    fi

    echo -e "${GREEN}Done.${NC}"
}

# =============================================================================
# Parse arguments
# =============================================================================

# Temporary per-container options
CUR_IMAGE=""
CUR_NETWORK="$NETWORK_MODE"
CUR_CAPS=""
CUR_PORTS=""
CUR_MEMORY="$MEMORY_MB"
CUR_PRIORITY="$PRIORITY"
CUR_DESC=""
declare -a CUR_VOLUMES=()
declare -a CUR_ENVS=()
REMOVE_TARGET=""

reset_current() {
    CUR_IMAGE=""
    CUR_NETWORK="$NETWORK_MODE"
    CUR_CAPS=""
    CUR_PORTS=""
    CUR_MEMORY="$MEMORY_MB"
    CUR_PRIORITY="$PRIORITY"
    CUR_DESC=""
    CUR_VOLUMES=()
    CUR_ENVS=()
}

# Process the currently-buffered container: generate recipe, update manifest,
# enabled-containers.conf, and local.conf. Called whenever we hit a new
# --add-container or end-of-args.
flush_container() {
    [ -n "$CUR_IMAGE" ] || return 0

    if [ $HEADER_PRINTED -eq 0 ]; then
        # Verify project structure lazily once, before the first real write
        if [ ! -d "$RECIPES_DIR" ]; then
            echo -e "${RED}Error: recipes directory not found: $RECIPES_DIR${NC}"
            exit 1
        fi
        if [ ! -f "$MANIFEST_FILE" ]; then
            echo -e "${RED}Error: manifest.json not found: $MANIFEST_FILE${NC}"
            exit 1
        fi
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}Adding Containers to Yocto Build${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo ""
        HEADER_PRINTED=1
    fi

    local name
    name=$(extract_name "$CUR_IMAGE")

    echo -e "${GREEN}Container: ${CUR_IMAGE}${NC}"
    echo "  Name:     ${name}"
    echo "  Network:  ${CUR_NETWORK}"
    echo "  Caps:     ${CUR_CAPS:-none}"
    echo "  Ports:    ${CUR_PORTS:-none}"
    echo "  Memory:   ${CUR_MEMORY} MB"
    echo "  Priority: ${CUR_PRIORITY}"
    if [ ${#CUR_VOLUMES[@]} -gt 0 ]; then
        echo "  Volumes:"
        local v
        for v in "${CUR_VOLUMES[@]}"; do echo "    - $v"; done
    fi
    if [ ${#CUR_ENVS[@]} -gt 0 ]; then
        echo "  Env:"
        local e
        for e in "${CUR_ENVS[@]}"; do echo "    - $e"; done
    fi
    echo ""

    if [ -d "$RECIPES_DIR/jsdelivr-container-${name}" ]; then
        echo -e "${YELLOW}  Recipe already exists for '${name}', skipping recipe generation${NC}"
    else
        generate_recipe "$CUR_IMAGE" "$name" "$CUR_NETWORK" "$CUR_CAPS" "$CUR_PORTS" "$CUR_MEMORY" "$CUR_PRIORITY" "$CUR_DESC"
    fi

    local vol_tmp env_tmp
    vol_tmp=$(mktemp)
    env_tmp=$(mktemp)
    if [ ${#CUR_VOLUMES[@]} -gt 0 ]; then
        printf '%s\n' "${CUR_VOLUMES[@]}" > "$vol_tmp"
    fi
    if [ ${#CUR_ENVS[@]} -gt 0 ]; then
        printf '%s\n' "${CUR_ENVS[@]}" > "$env_tmp"
    fi

    add_to_manifest "$CUR_IMAGE" "$name" "$CUR_NETWORK" "$CUR_CAPS" \
        "$CUR_PORTS" "$CUR_MEMORY" "$CUR_PRIORITY" "$CUR_DESC" \
        "$vol_tmp" "$env_tmp"
    rm -f "$vol_tmp" "$env_tmp"

    add_to_enabled_conf "$name" "$CUR_IMAGE"
    add_to_local_conf "$name"

    echo ""

    CONTAINER_COUNT=$((CONTAINER_COUNT + 1))
    reset_current
}

if [ $# -eq 0 ]; then
    usage
    exit 1
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --add-container)
            flush_container
            CUR_IMAGE="$2"
            ACTION="add"
            shift 2
            ;;
        --network)
            CUR_NETWORK="$2"
            shift 2
            ;;
        --cap)
            CUR_CAPS="$2"
            shift 2
            ;;
        --ports)
            CUR_PORTS="$2"
            shift 2
            ;;
        --memory)
            CUR_MEMORY="$2"
            shift 2
            ;;
        --priority)
            CUR_PRIORITY="$2"
            shift 2
            ;;
        --description)
            CUR_DESC="$2"
            shift 2
            ;;
        --volume)
            CUR_VOLUMES+=("$2")
            shift 2
            ;;
        --env)
            CUR_ENVS+=("$2")
            shift 2
            ;;
        --list)
            ACTION="list"
            shift
            ;;
        --remove)
            ACTION="remove"
            REMOVE_TARGET="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            exit 1
            ;;
    esac
done

# =============================================================================
# Execute action
# =============================================================================

if [ "$ACTION" = "list" ]; then
    list_containers
    exit 0
fi

if [ "$ACTION" = "remove" ]; then
    remove_container "$REMOVE_TARGET"
    exit 0
fi

# Flush last buffered container (add action)
flush_container

if [ "$ACTION" != "add" ] || [ $CONTAINER_COUNT -eq 0 ]; then
    echo -e "${RED}No containers specified. Use --add-container IMAGE:TAG${NC}"
    usage
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Done! ${CONTAINER_COUNT} container(s) configured.${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Next steps:"
echo "  1. Review generated recipes in meta-jsdelivr/recipes-jsdelivr/"
echo "  2. Build the image:  ./build-complete-image.sh"
echo "  3. Or build just the container recipe:"
echo "     source sources/poky/oe-init-build-env build"
echo "     bitbake jsdelivr-container-<name>"
echo ""
echo "To remove a container later:"
echo "  $0 --remove <name>"
echo ""
echo "To list all configured containers:"
echo "  $0 --list"
