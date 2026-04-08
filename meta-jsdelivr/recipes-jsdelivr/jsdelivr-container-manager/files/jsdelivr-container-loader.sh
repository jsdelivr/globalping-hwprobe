#!/bin/bash
#
# jsdelivr-container-loader.sh - Enhanced multi-container management system
# Loads and manages optional Docker containers alongside globalping-probe
# Version 2.0 - Supports volumes, capabilities, ports, and advanced parameters
#

OPTIONAL_DIR="/JSDELIVR_BASE_CONTAINER/optional"
CONFIG_DIR="/JSDELIVR_BASE_CONTAINER/config"
PERSIST_CONFIG_DIR="/persist/jsdelivr-config"
MANIFEST_FILE="${OPTIONAL_DIR}/manifest.json"
CONFIG_FILE="${CONFIG_DIR}/enabled-containers.conf"
PERSIST_CONFIG_FILE="${PERSIST_CONFIG_DIR}/enabled-containers.conf"

# Log function
log() {
    echo "[Container Loader] $1" > /dev/tty3
    echo "[Container Loader] $1"
}

# Load configuration from persistent storage if available, otherwise use default
load_config() {
    # Check if persistent config exists
    if [ -f "$PERSIST_CONFIG_FILE" ]; then
        log "Loading configuration from persistent storage"
        source "$PERSIST_CONFIG_FILE"
    elif [ -f "$CONFIG_FILE" ]; then
        log "Loading default configuration"
        source "$CONFIG_FILE"
    else
        log "No configuration file found, all optional containers disabled by default"
    fi
}

# Check if a container is enabled in configuration
is_container_enabled() {
    local container_name="$1"
    local var_name="ENABLE_${container_name^^}"
    local var_name_clean="${var_name//-/_}"  # Replace hyphens with underscores

    # Get the value of the variable
    local enabled="${!var_name_clean:-0}"

    [ "$enabled" = "1" ]
}

# Parse JSON manifest (simple bash implementation)
get_container_info() {
    local container_name="$1"
    local field="$2"

    if [ ! -f "$MANIFEST_FILE" ]; then
        return 1
    fi

    # Simple grep-based JSON parsing (works for simple structures)
    grep -A 10 "\"name\": \"$container_name\"" "$MANIFEST_FILE" | \
        grep "\"$field\"" | \
        cut -d'"' -f4
}

# Get array field from manifest (capabilities, ports, etc.)
get_container_array() {
    local container_name="$1"
    local field="$2"

    if [ ! -f "$MANIFEST_FILE" ]; then
        return 1
    fi

    # Extract array values - handles both single-line ["item1", "item2"] and multi-line formats
    local section=""
    section=$(grep -A 20 "\"name\": \"$container_name\"" "$MANIFEST_FILE" | grep -A 1 "\"$field\":")

    # Check if array is on the same line as field (single-line format)
    # Note: Use 'head -n 1' for BusyBox compatibility (not 'head -1')
    if echo "$section" | head -n 1 | grep -q '\[.*\]'; then
        # Single-line array like: "capabilities": ["SYS_PTRACE", "NET_ADMIN"]
        echo "$section" | head -n 1 | \
            sed 's/.*\[//' | sed 's/\].*//' | \
            tr ',' '\n' | \
            sed 's/^[[:space:]]*"//' | sed 's/"[[:space:]]*$//' | \
            grep -v '^$'
    else
        # Multi-line array format
        grep -A 20 "\"name\": \"$container_name\"" "$MANIFEST_FILE" | \
            grep -A 10 "\"$field\":" | \
            grep -E '^\s*"' | \
            cut -d'"' -f2 | \
            grep -v "^$field$"
    fi
}

# Parse volumes from manifest JSON
# Returns volume definitions in format: type|source|target|options
parse_volumes() {
    local container_name="$1"

    if [ ! -f "$MANIFEST_FILE" ]; then
        return 1
    fi

    # Extract volumes section for this container
    local in_container=0
    local in_volumes=0
    local type="" source="" target="" readonly="false" create="false"

    while IFS= read -r line; do
        # Check if we're in the right container
        if echo "$line" | grep -q "\"name\": \"$container_name\""; then
            in_container=1
        fi

        # If we're in the container, look for volumes section
        if [ $in_container -eq 1 ] && echo "$line" | grep -q '"volumes":'; then
            in_volumes=1
            continue
        fi

        # If we're in volumes, extract data until we hit the closing bracket
        if [ $in_volumes -eq 1 ]; then
            # Check for end of volumes array (line starting with ])
            if echo "$line" | grep -q '^\s*\]'; then
                in_volumes=0
                break
            fi

            # Extract volume data
            if echo "$line" | grep -q '"type"'; then
                type=$(echo "$line" | cut -d'"' -f4)
            fi
            if echo "$line" | grep -q '"source"'; then
                source=$(echo "$line" | cut -d'"' -f4)
            fi
            if echo "$line" | grep -q '"target"'; then
                target=$(echo "$line" | cut -d'"' -f4)
            fi
            if echo "$line" | grep -q '"readonly"'; then
                readonly=$(echo "$line" | cut -d':' -f2 | tr -d ' ,')
            fi
            if echo "$line" | grep -q '"create"'; then
                create=$(echo "$line" | cut -d':' -f2 | tr -d ' ,')
            fi

            # When we hit closing brace of a volume object, output and reset
            # Match }, or } at end of volume object (but not }] which ends the array)
            if echo "$line" | grep -q '^\s*}' && ! echo "$line" | grep -q '^\s*\]'; then
                if [ -n "$source" ] && [ -n "$target" ]; then
                    echo "${type:-bind}|${source}|${target}|${readonly:-false}|${create:-false}"
                fi
                type=""; source=""; target=""; readonly="false"; create="false"
            fi
        fi

        # Check if we've left the container section (only when not in volumes)
        if [ $in_container -eq 1 ] && [ $in_volumes -eq 0 ] && echo "$line" | grep -q '^\s*},$'; then
            break
        fi
    done < "$MANIFEST_FILE"
}

# Create Docker volumes if needed
create_volumes() {
    local container_name="$1"

    log "Checking volumes for $container_name..."

    # Parse volumes and create if needed
    # Using pipe instead of process substitution for BusyBox/ash compatibility
    parse_volumes "$container_name" | while IFS='|' read -r type source target readonly create; do
        if [ "$type" = "volume" ] && [ "$create" = "true" ]; then
            # Check if volume exists
            if ! docker volume inspect "$source" > /dev/null 2>&1; then
                log "Creating Docker volume: $source"
                docker volume create "$source" > /dev/tty3 2>&1
                if [ $? -eq 0 ]; then
                    log "Successfully created volume $source"
                else
                    log "ERROR: Failed to create volume $source"
                fi
            else
                log "Volume $source already exists"
            fi
        fi
    done
}

# Build volume arguments for docker run
build_volume_args() {
    local container_name="$1"

    # Using pipe instead of process substitution for BusyBox/ash compatibility
    # Each volume arg is echoed directly; printf -v joins them without leading space
    parse_volumes "$container_name" | while IFS='|' read -r type source target readonly create; do
        [ -z "$source" ] && continue

        if [ "$readonly" = "true" ]; then
            printf " -v %s:%s:ro" "$source" "$target"
        else
            printf " -v %s:%s" "$source" "$target"
        fi
    done
}

# Build capability arguments for docker run
build_capability_args() {
    local container_name="$1"

    # Using pipe instead of process substitution for BusyBox/ash compatibility
    get_container_array "$container_name" "capabilities" | while IFS= read -r cap; do
        [ -z "$cap" ] && continue
        printf " --cap-add=%s" "$cap"
    done
}

# Build port arguments for docker run
build_port_args() {
    local container_name="$1"

    # Using pipe instead of process substitution for BusyBox/ash compatibility
    get_container_array "$container_name" "ports" | while IFS= read -r port; do
        [ -z "$port" ] && continue
        printf " -p %s" "$port"
    done
}

# Load optional Docker images from frozen tarballs
load_optional_containers() {
    log "Loading optional container images..."

    # Check if optional directory exists
    if [ ! -d "$OPTIONAL_DIR" ]; then
        log "Optional containers directory not found, skipping"
        return 0
    fi

    # Load configuration
    load_config

    # Iterate through frozen images
    local loaded_count=0
    for frozen in "${OPTIONAL_DIR}"/*.frozen; do
        [ -f "$frozen" ] || continue

        local container_name=$(basename "$frozen" .frozen)
        log "Found optional container: $container_name"

        # Check if enabled
        if is_container_enabled "$container_name"; then
            log "Loading $container_name image..."
            if cat "$frozen" | /usr/bin/docker load > /dev/tty3; then
                log "Successfully loaded $container_name"
                ((loaded_count++))
            else
                log "ERROR: Failed to load $container_name"
            fi
        else
            log "Container $container_name is disabled, skipping"
        fi
    done

    log "Loaded $loaded_count optional container image(s)"
    return 0
}

# Start optional containers based on manifest configuration
start_optional_containers() {
    log "Starting optional containers..."

    # Check if optional directory exists
    if [ ! -d "$OPTIONAL_DIR" ]; then
        log "Optional containers directory not found, skipping"
        return 0
    fi

    # Load configuration
    load_config

    # Start each enabled container
    local started_count=0
    for frozen in "${OPTIONAL_DIR}"/*.frozen; do
        [ -f "$frozen" ] || continue

        local container_name=$(basename "$frozen" .frozen)

        # Check if enabled
        if ! is_container_enabled "$container_name"; then
            continue
        fi

        # Get container configuration from manifest
        local docker_image=$(get_container_info "$container_name" "docker_image")
        local network_mode=$(get_container_info "$container_name" "network_mode")
        local restart_policy=$(get_container_info "$container_name" "restart_policy")

        # Default values if manifest not found
        docker_image="${docker_image:-$container_name}"
        network_mode="${network_mode:-host}"
        restart_policy="${restart_policy:-always}"

        log "Starting container: $container_name (image: $docker_image)"

        # Check if container already exists
        if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
            log "Container $container_name already exists, checking if running..."
            if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
                log "Container $container_name is already running"
                continue
            else
                log "Starting existing container $container_name"
                docker start "$container_name" > /dev/tty3 2>&1
                ((started_count++))
                continue
            fi
        fi

        # Create volumes if needed
        create_volumes "$container_name"

        # Build advanced arguments
        local volume_args=$(build_volume_args "$container_name")
        local cap_args=$(build_capability_args "$container_name")
        local port_args=$(build_port_args "$container_name")

        # Load environment file if exists
        local env_file="${CONFIG_DIR}/${container_name}.env"
        local env_args=""
        if [ -f "$env_file" ]; then
            env_args="--env-file $env_file"
        fi

        # Check for persistent override environment file
        local persist_env_file="/persist/container-overrides/${container_name}.env"
        if [ -f "$persist_env_file" ]; then
            env_args="--env-file $persist_env_file"
            log "Using persistent environment override for $container_name"
        fi

        # Start container with full configuration
        log "Creating and starting new container $container_name"
        docker run -d \
            --name "$container_name" \
            --restart="$restart_policy" \
            --network "$network_mode" \
            $volume_args \
            $cap_args \
            $port_args \
            $env_args \
            "$docker_image" > /dev/tty3 2>&1

        if [ $? -eq 0 ]; then
            log "Successfully started $container_name"
            ((started_count++))
        else
            log "ERROR: Failed to start $container_name"
        fi
    done

    log "Started $started_count optional container(s)"
    return 0
}

# Monitor optional containers and restart if stopped
monitor_optional_containers() {
    # Load configuration
    load_config

    # Check each enabled container
    for frozen in "${OPTIONAL_DIR}"/*.frozen; do
        [ -f "$frozen" ] || continue

        local container_name=$(basename "$frozen" .frozen)

        # Check if enabled
        if ! is_container_enabled "$container_name"; then
            continue
        fi

        # Check if container is running
        if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
            # Container is running
            continue
        else
            # Container is not running, try to start it
            log "Container $container_name is not running, attempting to restart..."
            docker start "$container_name" > /dev/tty3 2>&1

            if [ $? -ne 0 ]; then
                log "Failed to restart $container_name, will retry on next check"
            fi
        fi
    done
}

# List all available optional containers
list_optional_containers() {
    echo "Available optional containers:"

    if [ ! -d "$OPTIONAL_DIR" ]; then
        echo "  No optional containers directory found"
        return 0
    fi

    load_config

    for frozen in "${OPTIONAL_DIR}"/*.frozen; do
        [ -f "$frozen" ] || continue

        local container_name=$(basename "$frozen" .frozen)
        local status="disabled"

        if is_container_enabled "$container_name"; then
            status="enabled"
        fi

        local description=$(get_container_info "$container_name" "description")

        echo "  - $container_name [$status]"
        if [ -n "$description" ]; then
            echo "    $description"
        fi
    done
}

# Export functions for use in other scripts
export -f log
export -f load_config
export -f is_container_enabled
export -f load_optional_containers
export -f start_optional_containers
export -f monitor_optional_containers
export -f list_optional_containers
