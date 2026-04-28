#!/bin/bash
# jsdelivr-client.sh - Simple bash client for jsdelivr-docker-controller API
# Uses curl for API calls

API_HOST="${API_HOST:-127.0.0.1}"
API_PORT="${API_PORT:-5000}"
BASE_URL="http://${API_HOST}:${API_PORT}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# curl wrapper with sane timeouts — avoids hung CLI on unreachable controller
api() {
    curl --connect-timeout 5 --max-time 30 -sS "$@"
}

# Parse JSON status field from a response string. Echoes the value (or empty).
json_status() {
    echo "$1" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('status', ''))
except Exception:
    pass
" 2>/dev/null
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS] COMMAND [ARGS]

Options:
  --host HOST     API host (default: 127.0.0.1)
  --port PORT     API port (default: 5000)
  --no-color      Disable colored output

Commands:
  containers                          List all containers
  logs CONTAINER [SINCE]              Get container logs (SINCE: 1h, 30m, etc.)
  start CONTAINER                     Start a container
  stop CONTAINER                      Stop a container
  settings                            Get all settings
  setting NAME                        Get specific setting
  set NAME VALUE                      Set a specific setting
  health                              Health check

Environment Variables:
  API_HOST        API host (default: 127.0.0.1)
  API_PORT        API port (default: 5000)

Examples:
  # List containers
  $0 containers

  # Get logs from last hour
  $0 logs globalping-probe 1h

  # Start container
  $0 start globalping-probe

  # Get settings
  $0 settings

  # Set a setting
  $0 set webApiEnabled true

  # Connect to remote device
  API_HOST=192.168.1.100 $0 containers
EOF
}

# Parse options
while [[ $# -gt 0 ]]; do
    case $1 in
        --host)
            if [[ $# -lt 2 || "$2" == -* ]]; then
                echo -e "${RED}ERROR: --host requires a value${NC}"
                exit 1
            fi
            API_HOST="$2"
            BASE_URL="http://${API_HOST}:${API_PORT}"
            shift 2
            ;;
        --port)
            if [[ $# -lt 2 || ! "$2" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}ERROR: --port requires a numeric value${NC}"
                exit 1
            fi
            API_PORT="$2"
            BASE_URL="http://${API_HOST}:${API_PORT}"
            shift 2
            ;;
        --no-color)
            RED=''
            GREEN=''
            YELLOW=''
            BLUE=''
            CYAN=''
            BOLD=''
            NC=''
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

COMMAND="${1:-}"
[ $# -gt 0 ] && shift

case "$COMMAND" in
    containers)
        echo -e "${BOLD}Docker Containers:${NC}\n"
        if ! response=$(api "${BASE_URL}/containers"); then
            echo -e "${RED}ERROR: Cannot connect to ${BASE_URL}${NC}"
            exit 1
        fi

        echo "$response" | python3 -c "
import sys, json
try:
    containers = json.load(sys.stdin)
    for c in containers:
        name = c.get('Names', 'N/A')
        state = c.get('State', 'N/A')
        status = c.get('Status', 'N/A')
        image = c.get('Image', 'N/A')
        cid = c.get('ID', 'N/A')[:12]

        print(f'Name: {name}')
        print(f'ID: {cid}')
        print(f'Image: {image}')
        print(f'State: {state}')
        print(f'Status: {status}')
        print()
except:
    print('No containers found or invalid response', file=sys.stderr)
"
        ;;

    logs)
        container="$1"
        since="$2"

        if [ -z "$container" ]; then
            echo -e "${RED}ERROR: Container name required${NC}"
            echo "Usage: $0 logs CONTAINER [SINCE]"
            exit 1
        fi

        url="${BASE_URL}/containers/${container}/logs"
        if [ -n "$since" ]; then
            url="${url}?since=${since}"
        fi

        echo -e "${BOLD}Logs for ${container}:${NC}\n"
        api "$url"
        ;;

    start)
        container="$1"

        if [ -z "$container" ]; then
            echo -e "${RED}ERROR: Container name required${NC}"
            echo "Usage: $0 start CONTAINER"
            exit 1
        fi

        if ! response=$(api -X POST "${BASE_URL}/containers/${container}/start"); then
            echo -e "${RED}ERROR: Cannot connect to ${BASE_URL}${NC}"
            exit 1
        fi

        if [ "$(json_status "$response")" = "success" ]; then
            echo -e "${GREEN}✓ Container '${container}' started successfully${NC}"
            echo "$response" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f\"Container ID: {data.get('container_id', 'N/A')}\")
"
        else
            echo -e "${RED}ERROR: Failed to start container${NC}"
            echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
            exit 1
        fi
        ;;

    stop)
        container="$1"

        if [ -z "$container" ]; then
            echo -e "${RED}ERROR: Container name required${NC}"
            echo "Usage: $0 stop CONTAINER"
            exit 1
        fi

        if ! response=$(api -X POST "${BASE_URL}/containers/${container}/stop"); then
            echo -e "${RED}ERROR: Cannot connect to ${BASE_URL}${NC}"
            exit 1
        fi

        if [ "$(json_status "$response")" = "success" ]; then
            echo -e "${YELLOW}✓ Container '${container}' stopped${NC}"
            echo "$response" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f\"Container ID: {data.get('container_id', 'N/A')}\")
"
        else
            echo -e "${RED}ERROR: Failed to stop container${NC}"
            echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
            exit 1
        fi
        ;;

    settings)
        echo -e "${BOLD}Application Settings:${NC}\n"
        if ! response=$(api "${BASE_URL}/settings"); then
            echo -e "${RED}ERROR: Cannot connect to ${BASE_URL}${NC}"
            exit 1
        fi
        echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    settings = data.get('settings', {})
    settings_dir = data.get('settings_dir', 'N/A')

    print(f'Settings directory: {settings_dir}\n')

    for key, value in settings.items():
        # Hide passwords
        if 'password' in key.lower() and value:
            display_value = '*' * len(str(value))
        else:
            display_value = value
        print(f'{key}: {display_value}')
except:
    print('Failed to parse response', file=sys.stderr)
    sys.exit(1)
"
        ;;

    setting)
        setting_name="$1"

        if [ -z "$setting_name" ]; then
            echo -e "${RED}ERROR: Setting name required${NC}"
            echo "Usage: $0 setting NAME"
            exit 1
        fi

        encoded_setting_name=$(printf '%s' "$setting_name" | python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.stdin.read(), safe=''))")
        if ! response=$(api "${BASE_URL}/settings/${encoded_setting_name}"); then
            echo -e "${RED}ERROR: Cannot connect to ${BASE_URL}${NC}"
            exit 1
        fi
        echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    name = data.get('setting_name', 'N/A')
    value = data.get('value')
    file_path = data.get('file', 'N/A')

    # Hide passwords
    if 'password' in name.lower() and value:
        display_value = '*' * len(str(value))
    else:
        display_value = value

    print(f'Setting: {name}')
    print(f'Value: {display_value}')
    print(f'File: {file_path}')
except:
    print('Setting not found or invalid response', file=sys.stderr)
    sys.exit(1)
"
        ;;

    set)
        setting_name="$1"
        value="$2"

        if [ -z "$setting_name" ] || [ -z "$value" ]; then
            echo -e "${RED}ERROR: Setting name and value required${NC}"
            echo "Usage: $0 set NAME VALUE"
            exit 1
        fi

        # URL encode path segments; safe='' escapes "/" too.
        encoded_setting_name=$(printf '%s' "$setting_name" | python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.stdin.read(), safe=''))")
        encoded_value=$(printf '%s' "$value" | python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.stdin.read(), safe=''))")

        if ! response=$(api -X PUT "${BASE_URL}/settings/${encoded_setting_name}/${encoded_value}"); then
            echo -e "${RED}ERROR: Cannot connect to ${BASE_URL}${NC}"
            exit 1
        fi

        if [ "$(json_status "$response")" = "success" ]; then
            echo -e "${GREEN}✓ Setting '${setting_name}' updated successfully${NC}"
            echo "$response" | python3 -c "
import sys, json
data = json.load(sys.stdin)
value = data.get('value')
name = data.get('setting_name') or ''

# Hide passwords
if 'password' in name.lower() and value:
    display_value = '*' * len(str(value))
else:
    display_value = value

print(f'New value: {display_value}')
"
        else
            echo -e "${RED}ERROR: Failed to update setting${NC}"
            echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
            exit 1
        fi
        ;;

    health)
        if ! response=$(api "${BASE_URL}/health"); then
            echo -e "${RED}ERROR: Cannot connect to ${BASE_URL}${NC}"
            exit 1
        fi

        if [ "$(json_status "$response")" = "healthy" ]; then
            echo -e "${GREEN}✓ API is healthy${NC}"
        else
            echo -e "${RED}✗ API health check failed${NC}"
            echo "$response"
            exit 1
        fi
        ;;

    "")
        print_usage
        exit 1
        ;;

    *)
        echo -e "${RED}ERROR: Unknown command: $COMMAND${NC}"
        print_usage
        exit 1
        ;;
esac
