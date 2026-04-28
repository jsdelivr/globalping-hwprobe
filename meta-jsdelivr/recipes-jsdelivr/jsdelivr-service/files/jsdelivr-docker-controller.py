import json
import os
import re
import subprocess
from pathlib import Path
from flask import Flask, jsonify, request, Response

app = Flask(__name__)

# Configuration and settings file paths
# All config files are stored in /persist/jsdelivr-config/ subdirectory for consistency
# with container-loader.sh and other scripts
CONFIG_FILE = '/persist/jsdelivr-config/jsdelivr_controller.settings'
PERSIST_MOUNT = '/persist'
SETTINGS_DIR = '/persist/jsdelivr-config'

# Default Flask app configuration
DEFAULT_CONFIG = {
    'host': '127.0.0.1',
    'port': 5000,
    'debug': False
}

# Default application settings (stored as individual bash-compatible files)
DEFAULT_SETTINGS = {
    'webApiEnabled': True,
    'webApiPassword': ''
}

# Settings file names (bash-compatible format)
SETTINGS_FILES = {
    'webApiEnabled': 'webApiEnabled',
    'webApiPassword': 'webApiPassword'
}

# Settings whose values must never be returned to API clients or written to logs.
SECRET_SETTINGS = ('webApiPassword',)


def redact_settings(settings):
    """Return a copy of settings with secret values masked, for safe logging
    or API responses. Booleans pass through; secret strings become a fixed
    placeholder so callers cannot tell whether a value is set or empty."""
    redacted = dict(settings)
    for key in SECRET_SETTINGS:
        if key in redacted:
            redacted[key] = '***' if redacted[key] else ''
    return redacted


def remount_persist_rw():
    """
    Remount /persist partition as read-write.
    Returns True if successful, False otherwise.
    """
    try:
        subprocess.run(
            ['mount', '-o', 'remount,rw', PERSIST_MOUNT],
            capture_output=True,
            text=True,
            check=True
        )
        print(f"Remounted {PERSIST_MOUNT} as read-write")
        return True
    except subprocess.CalledProcessError as e:
        print(f"Warning: Failed to remount {PERSIST_MOUNT} as RW: {e.stderr}")
        return False
    except Exception as e:
        print(f"Warning: Error remounting {PERSIST_MOUNT}: {e}")
        return False


def remount_persist_ro():
    """
    Remount /persist partition as read-only.
    Returns True if successful, False otherwise.
    """
    try:
        subprocess.run(
            ['mount', '-o', 'remount,ro', PERSIST_MOUNT],
            capture_output=True,
            text=True,
            check=True
        )
        print(f"Remounted {PERSIST_MOUNT} as read-only")
        return True
    except subprocess.CalledProcessError as e:
        print(f"Warning: Failed to remount {PERSIST_MOUNT} as RO: {e.stderr}")
        return False
    except Exception as e:
        print(f"Warning: Error remounting {PERSIST_MOUNT}: {e}")
        return False


def create_default_config():
    """
    Create a new config file with default values (Flask config only).
    Remounts /persist as RW, writes the file, then remounts as RO.
    """
    config_path = Path(CONFIG_FILE)

    # Remount /persist as read-write
    if not remount_persist_rw():
        print("Proceeding with in-memory defaults")
        return False

    try:
        # Ensure the parent directory exists
        config_path.parent.mkdir(parents=True, exist_ok=True)

        # Write default config to file (Flask settings only)
        with open(CONFIG_FILE, 'w') as f:
            json.dump(DEFAULT_CONFIG, f, indent=2)

        print(f"Created new config file at {CONFIG_FILE} with default values")
        success = True
    except (IOError, OSError) as e:
        print(f"Warning: Failed to create config file at {CONFIG_FILE}: {e}")
        print("Proceeding with in-memory defaults")
        success = False
    finally:
        # Always remount as read-only, even if write failed
        remount_persist_ro()

    return success


def read_bash_setting_file(filename, setting_name, default_value):
    """
    Read a single bash-style setting file.
    Expected format: SETTING_NAME='value' or SETTING_NAME=value
    Returns the value or default if file doesn't exist or is invalid.
    """
    file_path = Path(SETTINGS_DIR) / filename

    if not file_path.exists():
        return default_value

    try:
        with open(file_path, 'r') as f:
            content = f.read().strip()

        # Parse bash variable format: SETTING_NAME=value
        if '=' in content:
            _, value = content.split('=', 1)
            value = value.strip()

            # Handle boolean conversion for webApiEnabled
            if setting_name == 'webApiEnabled':
                # Remove quotes if present for boolean check
                clean_value = value.strip('"').strip("'")
                return clean_value.lower() in ('true', '1', 'yes')

            # Handle quoted strings (single or double quotes)
            # Remove outer quotes if present
            if len(value) >= 2:
                if (value[0] == "'" and value[-1] == "'") or (value[0] == '"' and value[-1] == '"'):
                    # Unescape the value: '\'' back to '
                    value = value[1:-1].replace("'\\''", "'")
                    return value

            # Return unquoted value as-is (backward compatibility)
            return value
        else:
            return default_value
    except (IOError, OSError) as e:
        print(f"Warning: Failed to read setting file {file_path}: {e}")
        return default_value


def write_bash_setting_file(filename, setting_name, value):
    """
    Write a single bash-style setting file.
    Format: SETTING_NAME='value' (with proper escaping)
    Returns True on success, False on failure.
    """
    file_path = Path(SETTINGS_DIR) / filename

    try:
        # Lock down the parent directory and the file mode explicitly. With
        # the process umask (often 0022) the file would land 0644 and the
        # password fields would be world-readable. Force 0700/0600.
        file_path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        try:
            os.chmod(file_path.parent, 0o700)
        except OSError:
            pass  # best-effort; mkdir may have already set it

        # Format value for bash with proper quoting
        if isinstance(value, bool):
            # Boolean values don't need quoting
            bash_value = 'true' if value else 'false'
        else:
            # Escape single quotes by replacing ' with '\''
            # This safely escapes the value for bash sourcing
            escaped_value = str(value).replace("'", "'\\''")
            # Wrap in single quotes to prevent command injection
            bash_value = f"'{escaped_value}'"

        # Write in bash variable format. Open with explicit 0o600 so the file
        # is never world-readable even if it already existed with looser perms.
        content = f"{setting_name}={bash_value}\n"
        fd = os.open(file_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        try:
            with os.fdopen(fd, 'w') as f:
                f.write(content)
        except Exception:
            try:
                os.close(fd)
            except OSError:
                pass
            raise
        try:
            os.chmod(file_path, 0o600)
        except OSError:
            pass

        return True
    except (IOError, OSError) as e:
        print(f"Warning: Failed to write setting file {file_path}: {e}")
        return False


def load_config():
    """
    Load Flask configuration from the config file.
    Creates a new file with defaults if it doesn't exist.
    Environment variables can override file settings.
    """
    config = DEFAULT_CONFIG.copy()
    config_path = Path(CONFIG_FILE)

    if config_path.exists():
        try:
            with open(CONFIG_FILE, 'r') as f:
                file_data = json.load(f)
                # Update config with file data
                for key in ['host', 'port', 'debug']:
                    if key in file_data:
                        config[key] = file_data[key]
        except (json.JSONDecodeError, IOError) as e:
            print(f"Warning: Failed to load config from {CONFIG_FILE}: {e}")
            print("Using default configuration")
    else:
        # Config file doesn't exist, create it with defaults
        create_default_config()

    # Environment variables override file config
    if 'FLASK_DEBUG' in os.environ:
        config['debug'] = os.environ.get('FLASK_DEBUG', 'false').lower() == 'true'
    if 'FLASK_HOST' in os.environ:
        config['host'] = os.environ.get('FLASK_HOST')
    if 'FLASK_PORT' in os.environ:
        try:
            config['port'] = int(os.environ.get('FLASK_PORT'))
        except ValueError:
            print(f"Warning: Invalid FLASK_PORT value, using {config['port']}")

    return config


def create_default_settings():
    """
    Create default settings files if they don't exist.
    Remounts /persist as RW, creates missing files, then remounts as RO.
    Returns True if successful or not needed, False on failure.
    """
    # Check which files need to be created
    files_to_create = []
    for setting_name, filename in SETTINGS_FILES.items():
        file_path = Path(SETTINGS_DIR) / filename
        if not file_path.exists():
            files_to_create.append((setting_name, filename))

    # If all files exist, nothing to do
    if not files_to_create:
        return True

    # Remount /persist as read-write
    if not remount_persist_rw():
        print("Warning: Could not create default settings files")
        return False

    try:
        success = True
        for setting_name, filename in files_to_create:
            default_value = DEFAULT_SETTINGS[setting_name]
            if write_bash_setting_file(filename, setting_name, default_value):
                print(f"Created default settings file: {SETTINGS_DIR}/{filename}")
            else:
                print(f"Warning: Failed to create {filename}")
                success = False
    except Exception as e:
        print(f"Error creating default settings files: {e}")
        success = False
    finally:
        # Always remount as read-only
        remount_persist_ro()

    return success


def load_settings():
    """
    Load application settings from individual bash-style files in /persist.
    Returns the settings dictionary.
    """
    settings = {}

    for setting_name, filename in SETTINGS_FILES.items():
        default_value = DEFAULT_SETTINGS[setting_name]
        settings[setting_name] = read_bash_setting_file(filename, setting_name, default_value)

    return settings


def save_settings(new_settings):
    """
    Save application settings to individual bash-style files in /persist.
    Remounts /persist as RW, writes the files, then remounts as RO.

    Validates every entry before any write. Writes one file at a time and
    stops on the first failure. Earlier entries in the batch may already be
    committed when a later entry fails — callers should treat a 5xx response
    as "state unknown" and re-read /settings to reconcile.
    Returns (success: bool, error_message: str or None).
    """
    # Validate that only known settings are being updated
    valid_keys = set(SETTINGS_FILES.keys())
    provided_keys = set(new_settings.keys())

    if not provided_keys.issubset(valid_keys):
        invalid_keys = provided_keys - valid_keys
        return False, f"Invalid setting keys: {invalid_keys}. Valid keys are: {valid_keys}"

    # PHASE 1: validate every entry before touching disk. A type error in
    # one field used to commit earlier fields and surface a 4xx — the device
    # ended up partially updated.
    type_errors = []
    for setting_name, value in new_settings.items():
        if setting_name == 'webApiEnabled' and not isinstance(value, bool):
            type_errors.append(f"{setting_name} must be a boolean")
        elif setting_name in SECRET_SETTINGS and not isinstance(value, str):
            type_errors.append(f"{setting_name} must be a string")
    if type_errors:
        return False, "; ".join(type_errors)

    # Remount /persist as read-write. If the remount itself failed, attempt
    # a best-effort remount-RO so we never leave /persist accidentally writable.
    if not remount_persist_rw():
        remount_persist_ro()
        return False, "Failed to remount /persist as read-write"

    try:
        # PHASE 2: write all entries. write_bash_setting_file is itself
        # atomic-ish (os.open with O_TRUNC + 0o600). On the first failure,
        # stop and report — earlier entries are committed.
        for setting_name, value in new_settings.items():
            filename = SETTINGS_FILES[setting_name]
            if not write_bash_setting_file(filename, setting_name, value):
                error_msg = f"Failed to write {setting_name}"
                success = False
                break
        else:
            print(f"Settings saved to {SETTINGS_DIR}")
            success = True
            error_msg = None

    except Exception as e:
        error_msg = f"Unexpected error saving settings: {str(e)}"
        success = False
    finally:
        # Always remount as read-only, even if write failed
        remount_persist_ro()

    return success, error_msg


@app.before_request
def _enforce_webapi_enabled():
    # Always allow the webApiEnabled setting to be inspected and re-enabled
    # so an operator who disabled the API can recover without SSH.
    # GET /settings/webApiEnabled and PUT /settings/webApiEnabled/<value>.
    if request.path == '/settings/webApiEnabled' or \
       request.path.startswith('/settings/webApiEnabled/'):
        return None

    enabled = read_bash_setting_file(
        SETTINGS_FILES['webApiEnabled'],
        'webApiEnabled',
        DEFAULT_SETTINGS['webApiEnabled'],
    )
    if not enabled:
        return jsonify({
            'error': 'API disabled',
            'details': 'webApiEnabled is false. PUT /settings/webApiEnabled/true to re-enable.'
        }), 403
    return None


@app.route('/containers', methods=['GET'])
def get_containers():
    """
    Returns the raw output of docker ps --all --no-trunc --format json
    """
    try:
        # Execute docker ps command
        result = subprocess.run(
            ['docker', 'ps', '--all', '--no-trunc', '--format', 'json'],
            capture_output=True,
            text=True,
            check=True
        )

        # Parse each line as a separate JSON object
        containers = []
        for line in result.stdout.strip().split('\n'):
            if line:
                containers.append(json.loads(line))

        return jsonify(containers), 200

    except subprocess.CalledProcessError as e:
        return jsonify({
            'error': 'Failed to execute docker ps command',
            'details': e.stderr
        }), 500
    except json.JSONDecodeError as e:
        return jsonify({
            'error': 'Failed to parse docker output',
            'details': str(e)
        }), 500
    except FileNotFoundError:
        return jsonify({
            'error': 'Docker command not found',
            'details': 'Docker is not installed or not in PATH'
        }), 500
    except Exception as e:
        return jsonify({
            'error': 'Unexpected error',
            'details': str(e)
        }), 500


@app.route('/containers/<name>/logs', methods=['GET'])
def get_container_logs(name):
    """
    Returns the raw output of docker logs for a specific container.

    The command executed is:
    docker logs $(docker ps --all --latest --filter 'name=<name>' --quiet) --since <since>

    Query parameters:
    - since: Optional timestamp or relative time (e.g., '2023-01-01T00:00:00', '1h', '30m')
    """
    try:
        # First, get the container ID using docker ps with filter
        ps_result = subprocess.run(
            ['docker', 'ps', '--all', '--latest', '--filter', f'name=^{re.escape(name)}$', '--quiet'],
            capture_output=True,
            text=True,
            check=True
        )

        container_id = ps_result.stdout.strip()

        if not container_id:
            return jsonify({
                'error': 'Container not found',
                'details': f'No container found with name: {name}'
            }), 404

        # Build docker logs command
        logs_cmd = ['docker', 'logs', container_id]

        # Add optional since parameter
        since = request.args.get('since', None)
        if since:
            logs_cmd.extend(['--since', since])

        # Execute docker logs command
        logs_result = subprocess.run(
            logs_cmd,
            capture_output=True,
            text=True,
            check=True
        )

        # Return raw output as plain text
        return Response(logs_result.stdout, mimetype='text/plain'), 200

    except subprocess.CalledProcessError as e:
        return jsonify({
            'error': 'Failed to execute docker command',
            'details': e.stderr
        }), 500
    except FileNotFoundError:
        return jsonify({
            'error': 'Docker command not found',
            'details': 'Docker is not installed or not in PATH'
        }), 500
    except Exception as e:
        return jsonify({
            'error': 'Unexpected error',
            'details': str(e)
        }), 500


@app.route('/containers/<name>/stop', methods=['POST'])
def stop_container(name):
    """
    Stops a specific container.

    The command executed is:
    docker stop $(docker ps --all --latest --filter 'name=<name>' --quiet)
    """
    try:
        # First, get the container ID using docker ps with filter
        ps_result = subprocess.run(
            ['docker', 'ps', '--all', '--latest', '--filter', f'name=^{re.escape(name)}$', '--quiet'],
            capture_output=True,
            text=True,
            check=True
        )

        container_id = ps_result.stdout.strip()

        if not container_id:
            return jsonify({
                'error': 'Container not found',
                'details': f'No container found with name: {name}'
            }), 404

        # Execute docker stop command (raises CalledProcessError on failure)
        subprocess.run(
            ['docker', 'stop', container_id],
            capture_output=True,
            text=True,
            check=True
        )

        return jsonify({
            'status': 'success',
            'container': name,
            'container_id': container_id,
            'message': 'Container stopped successfully'
        }), 200

    except subprocess.CalledProcessError as e:
        return jsonify({
            'error': 'Failed to execute docker command',
            'details': e.stderr
        }), 500
    except FileNotFoundError:
        return jsonify({
            'error': 'Docker command not found',
            'details': 'Docker is not installed or not in PATH'
        }), 500
    except Exception as e:
        return jsonify({
            'error': 'Unexpected error',
            'details': str(e)
        }), 500


@app.route('/containers/<name>/start', methods=['POST'])
def start_container(name):
    """
    Starts a specific container.

    The command executed is:
    docker start $(docker ps --all --latest --filter 'name=<name>' --quiet)
    """
    try:
        # First, get the container ID using docker ps with filter
        ps_result = subprocess.run(
            ['docker', 'ps', '--all', '--latest', '--filter', f'name=^{re.escape(name)}$', '--quiet'],
            capture_output=True,
            text=True,
            check=True
        )

        container_id = ps_result.stdout.strip()

        if not container_id:
            return jsonify({
                'error': 'Container not found',
                'details': f'No container found with name: {name}'
            }), 404

        # Execute docker start command (raises CalledProcessError on failure)
        subprocess.run(
            ['docker', 'start', container_id],
            capture_output=True,
            text=True,
            check=True
        )

        return jsonify({
            'status': 'success',
            'container': name,
            'container_id': container_id,
            'message': 'Container started successfully'
        }), 200

    except subprocess.CalledProcessError as e:
        return jsonify({
            'error': 'Failed to execute docker command',
            'details': e.stderr
        }), 500
    except FileNotFoundError:
        return jsonify({
            'error': 'Docker command not found',
            'details': 'Docker is not installed or not in PATH'
        }), 500
    except Exception as e:
        return jsonify({
            'error': 'Unexpected error',
            'details': str(e)
        }), 500


@app.route('/settings', methods=['GET'])
def get_settings():
    """
    Returns the current application settings.
    Settings are read from individual bash-compatible files in /persist:
    - webApiEnabled
    - webApiPassword
    """
    try:
        # Redact secret fields before sending to a client; otherwise GET
        # /settings would echo back webApiPassword in plaintext to whoever
        # can reach the API.
        settings = redact_settings(load_settings())

        return jsonify({
            'status': 'success',
            'settings': settings,
            'settings_dir': SETTINGS_DIR
        }), 200
    except Exception as e:
        return jsonify({
            'error': 'Unexpected error',
            'details': str(e)
        }), 500


@app.route('/settings/<setting_name>', methods=['GET'])
def get_setting(setting_name):
    """
    Returns a specific application setting.

    Valid setting names:
    - webApiEnabled
    - webApiPassword
    """
    try:
        # Validate setting name
        if setting_name not in SETTINGS_FILES:
            return jsonify({
                'error': 'Invalid setting name',
                'details': f'Valid settings are: {list(SETTINGS_FILES.keys())}'
            }), 404

        # Read the specific setting
        filename = SETTINGS_FILES[setting_name]
        default_value = DEFAULT_SETTINGS[setting_name]
        value = read_bash_setting_file(filename, setting_name, default_value)

        # Redact secret fields. Callers that need to know whether a secret
        # is set vs empty can use a separate "is set" probe; we never echo
        # the actual value back.
        if setting_name in SECRET_SETTINGS:
            value = '***' if value else ''

        return jsonify({
            'status': 'success',
            'setting_name': setting_name,
            'value': value,
            'file': f"{SETTINGS_DIR}/{filename}"
        }), 200
    except Exception as e:
        return jsonify({
            'error': 'Unexpected error',
            'details': str(e)
        }), 500


@app.route('/settings/<setting_name>/<path:value>', methods=['PUT'])
def update_setting(setting_name, value):
    """
    Updates a specific application setting via URL path.

    Valid setting names:
    - webApiEnabled (boolean): Enable/disable web API (use 'true' or 'false')
    - webApiPassword (string): Password for web API

    Examples:
    PUT /settings/webApiEnabled/true
    PUT /settings/webApiPassword/apipass123
    """
    try:
        # Validate setting name
        if setting_name not in SETTINGS_FILES:
            return jsonify({
                'error': 'Invalid setting name',
                'details': f'Valid settings are: {list(SETTINGS_FILES.keys())}'
            }), 404

        # Convert value based on setting type
        if setting_name == 'webApiEnabled':
            # Convert string to boolean
            if value.lower() in ('true', '1', 'yes'):
                typed_value = True
            elif value.lower() in ('false', '0', 'no'):
                typed_value = False
            else:
                return jsonify({
                    'error': 'Invalid boolean value',
                    'details': 'For webApiEnabled, use: true, false, 1, 0, yes, or no'
                }), 400
        else:
            # For string settings, use the value as-is
            typed_value = value

        # Save the single setting
        success, error_msg = save_settings({setting_name: typed_value})

        if success:
            # Read back the saved value to confirm. Redact secret fields:
            # echoing the just-set password back to the caller would also
            # land in any access-log proxy on the way out.
            filename = SETTINGS_FILES[setting_name]
            saved_value = read_bash_setting_file(filename, setting_name, DEFAULT_SETTINGS[setting_name])
            response_value = '***' if (setting_name in SECRET_SETTINGS and saved_value) else saved_value

            return jsonify({
                'status': 'success',
                'message': f'Setting {setting_name} updated successfully',
                'setting_name': setting_name,
                'value': response_value,
                'file': f"{SETTINGS_DIR}/{filename}"
            }), 200
        else:
            return jsonify({
                'error': 'Failed to save setting',
                'details': error_msg
            }), 500

    except Exception as e:
        return jsonify({
            'error': 'Unexpected error',
            'details': str(e)
        }), 500


@app.route('/settings', methods=['PUT'])
def update_settings():
    """
    Updates multiple application settings at once.

    Request body should be JSON with the settings to update.
    Each setting is written to a separate bash-compatible file in /persist.
    Supports partial updates - only send the fields you want to change.

    Valid settings:
    - webApiEnabled (boolean): Enable/disable web API
    - webApiPassword (string): Password for web API

    Example:
    {
      "webApiEnabled": true,
      "webApiPassword": "apipassword"
    }

    Files are written in bash-compatible format:
    webApiEnabled=true
    webApiPassword=apipassword
    """
    try:
        if not request.is_json:
            return jsonify({
                'error': 'Request must be JSON',
                'details': 'Content-Type must be application/json'
            }), 400

        new_settings = request.get_json()

        if not new_settings:
            return jsonify({
                'error': 'Empty settings',
                'details': 'Request body must contain at least one setting'
            }), 400

        # Save the settings
        success, error_msg = save_settings(new_settings)

        if success:
            # Read back the saved settings to confirm. Redact secret fields
            # before sending to the client.
            saved_settings = redact_settings(load_settings())

            return jsonify({
                'status': 'success',
                'message': 'Settings updated successfully',
                'settings': saved_settings,
                'settings_dir': SETTINGS_DIR
            }), 200
        else:
            return jsonify({
                'error': 'Failed to save settings',
                'details': error_msg
            }), 500

    except json.JSONDecodeError as e:
        return jsonify({
            'error': 'Invalid JSON',
            'details': str(e)
        }), 400
    except Exception as e:
        return jsonify({
            'error': 'Unexpected error',
            'details': str(e)
        }), 500


@app.route('/health', methods=['GET'])
def health_check():
    """
    Health check endpoint
    """
    return jsonify({
        'status': 'healthy'
    }), 200


if __name__ == '__main__':
    # Load configuration from file and environment
    config = load_config()

    # Initialize default settings files if they don't exist
    create_default_settings()

    # The API has no auth gate. Force bind to loopback so it is only reachable
    # via localhost on the device (or via SSH port-forward). Ignore any host
    # override from the config file or FLASK_HOST env var.
    bind_host = '127.0.0.1'
    if config.get('host') != bind_host:
        print(f"Ignoring config host '{config.get('host')}' — forcing bind to {bind_host}")

    print("Starting Flask app with configuration:")
    print(f"  Host: {bind_host}")
    print(f"  Port: {config['port']}")
    print(f"  Debug: {config['debug']}")
    print(f"  Config file: {CONFIG_FILE}")
    print(f"  Settings dir: {SETTINGS_DIR}")

    app.run(host=bind_host, port=config['port'], debug=config['debug'])
