#!/usr/bin/env bash

## Origin: https://raw.githubusercontent.com/moby/moby/master/contrib/download-frozen-image-v2.sh

# We extend our path to include local directory to ease jq finding.
export PATH=$PATH:.

# List of external commands we need currently
NEEDCMD=(
    curl jq awk sha256sum uname
)

set -eo pipefail

usage() {
    echo ""
    echo "Usage: $0 <options> image[:tag][@digest] ..."
    echo "  options:"
    echo "      -d|--dir <directory>        Output directory. Defaults to /tmp/docker_pull.XXXX"
    echo "      -o|--output <file>          Write downloaded images as tar to <file>."
    echo "      -O|--stdout                 Write downloaded images as tar to stdout"
    echo "      -l|--load                   Automatically use docker load afterwards. Disables output file."
    echo "      -I|--insecure               Use http instead of https protocol when not using official registry"
    echo "      -p|--progress               Show additional download progress bar of curl."
    echo "      -q|--quiet                  Only output warnings and errors."
    echo "      -a|--auth                   Use authentication for accessing the registry."
    echo "                file:<file>       Credential store file for non-public registry images. Default: ~/.docker/config.json"
    echo "                env:<varname>     Environment variable name holding the base64 encoded user:pass."
    echo "                <b64creds>        The base64 encoded version of 'user:pass'. NOT RECOMMENDED! MAY LEAK!"
    echo "      -A|--no-auth                Do not use any form of authentication. Disables any --auth option."
    echo "      -D|--debug                  Debug output. If used twice, sensitive information might be displayed!"
    echo "      -Z|--check                  dont download, just check hash"
    echo "      -c|--color                  Force color even if not on tty"
    echo "      -C|--no-color               No color output. Will be disabled if no tty is detected on stdout"
    echo "      -r|--architecture <arch>    Architecture to download. Tries to be auto-detect according current arch..."
    echo "      --force                     Overwrite --output <file> if it already exists. Default is to abort with error."
    echo ""
    echo " Note: "
    echo "  - Each option must be specified on it's own, like -D -D"
    echo "  - You cannot mix secure and insecure registries."
    echo "  - The credentials must be a base64-encoded version of username:password like used in HTTP Basic Auth"
    echo "  - Use http_proxy and https_proxy variables to download behind firewall. See your curl's man page"
    echo "  - Required binaries (must be present in PATH or CWD): ${NEEDCMD[@]}"
    echo "  - The --load and --output options require the 'tar' binary present in PATH"
    echo "  - The --load option requires the 'docker' binary present in PATH"
    echo "  - Output directory will be removed unless specified with --dir"
    echo "  - Authentication has precedence if used multiple times: creds -> env -> file. Default file will be used if not defined otherwise."
    echo ""
    [ -z "$1" ] || exit "$1"
}

[[ $# = 0 ]] && usage 255;

# Some default variables
AUTHCRED=""
AUTHENV=""
AUTHFILE=~/.docker/config.json
AUTH=1
PROGRESS="-s"
QUIET=0
LOAD=0
KEEP=0
STDOUT=0
FORCE=0
DEBUG=0
CHECK=0
PROTOCOL='https'
ARGS=()
DESTFILE=""
ARCH="arm"
AUTHENTICATION=""
dir=""
images=()
manifestJsonEntries=()
doNotGenerateManifestJson=
newlineIFS=$'\n'
indent_style=""
debug_style=""
error_style=""
reset_style=""
warn_style=""

error() { awk -v C="${error_style}" -v R="${reset_style}" '{ printf "%s* Error: %s%s\n", C,$0,R > "/dev/stderr"; fflush(); }' <<<"$@";  }
txt()  {
    if [[ $1 = "-w" ]]; then
        shift;
        echo "${warn_style}* Warning: $@${reset_style}" >&2;
    else
        ((QUIET)) || echo "$@" >&2; 
    fi
}
debug() { 
    ((DEBUG)) || return 0;
    if [[ $1 = "-i" ]]; then 
        ((DEBUG > 1 )) || return 0
        I=1; C="${indent_style}"; 
        shift;
    else 
        I=0; C="${debug_style}"; 
    fi; 
    awk -v I=$I -v C="$C" -v R="${reset_style}" '{ printf "%sdebug[%s]: %s%s%s\n", C, (I+1), (I==1) ? " | ":"", $0, R > "/dev/stderr"; fflush(); }' <<<"$@" || :; 
}

needcmd() {
    local cmd cmdbin
    debug "Checking for availability of binaries: $@"
    for cmd in $@; do
        if ! cmdbin=$(command -v $cmd 2> /dev/null ); then 
            error "Binary \"$cmd\" not found in $PATH!"
            usage 255
        else
            debug -i "$(printf "%-10s => %s\n" "$cmd" "$cmdbin")"
        fi
    done
}

[[ -t 1 ]] && COLOR=1 || COLOR=0

while [[ -n $1 ]]; do
    case $1 in
        -o|--output)        DESTFILE="$2"; STDOUT=0; shift ;;
        -O|--stdout)        DESTFILE="";   STDOUT=1; LOAD=0;;
        -l|--load)          DESTFILE="";   STDOUT=0; LOAD=1;;
        -I|--insecure)      PROTOCOL='http' ;;
        -d|--dir)           dir="$2"; KEEP=1; shift ;;
        -p|--progress)      QUIET=0 ; PROGRESS="--progress-bar";;
        -q|--quiet)         QUIET=1 ; PROGRESS="-s";;
        -a|--auth)          case ${2%:*} in
                                env)    AUTHENV="${2#*:}" ;;
                                file)   AUTHFILE="${2#*:}" ;;
                                *)      AUTHCRED="$2";;
                            esac
                            shift
                            ;;
        -A|--no-auth)       AUTH=0;;
        -D|--debug)         DEBUG+=1;;
        -Z|--check)         CHECK=1;;
        -c|--color)         COLOR=1;;
        -C|--no-color)      COLOR=0;;
        -r|--architecture)  ARCH="$2"; shift ;;
        --force)            FORCE=1;;
        -*)
            error "Unknown option: $1"
            usage 255
            ;;
        *) ARGS+=( "$1" );;
    esac
    shift;
done

if [[ ${#ARGS[@]} -eq 0 ]]; then
    usage 255
fi

if [[ -z "$dir" ]]; then
    dir="/tmp/docker_pull.$$.$RANDOM"
fi

if ((COLOR)); then
    ## ANSI Escape Sequence @ http://archive.download.redhat.com/pub/redhat/linux/7.1/fr/doc/HOWTOS/other-formats/html/Bash-Prompt-HOWTO-html/Bash-Prompt-HOWTO-6.html
    esc="$( echo -en "\033" )"
    rst="${esc}[0m"
    gray="${esc}[1;30m"
    red="${esc}[0;31m"
    cyan="${esc}[1;35m"
    yellow="${esc}[0;33m"

    debug_style="${yellow}"
    error_style="${red}"
    warn_style="${cyan}"
    reset_style="${rst}"
    indent_style="${gray}"
fi

if [[ -n $AUTHCRED ]]; then
    txt -w "Credentials provided via command line can be insecure";
fi

if [[ $KEEP -eq 0 && $DESTFILE = "" && $STDOUT -eq 0 && $LOAD -eq 0 ]]; then
    txt -w "With the current options this script will not produce any usable output"
fi

if [[ -z $ARCH ]]; then
    A=`uname -m`
    case $A in
        x86_64)     ARCH='amd64';;
        s390*)      ARCH='s390x';;
        ppc64)      ARCH='ppc64';;
        ppc64le)    ARCH='ppc64le';;
        arm|armv7*) ARCH='arm';;
        aarch64*)   ARCH='arm64';;
        armv8*)     ARCH='arm64';;
        *)
            error "Could not map architecture '$A' to a manifest type"
            exit 1;
            ;;
    esac
    debug "Determined architecture to be '$ARCH' via '$A'"
else
    debug "Set architecture to '$ARCH' via CLI"
fi

if [[ $FORCE -eq 0 && $DESTFILE != "" && -e $DESTFILE ]]; then
    error "Output file $DESTFILE already exists and not using --force"
    exit 255
fi

# check if essential commands are in our PATH
needcmd ${NEEDCMD[@]}

if ((LOAD)); then
    needcmd docker
fi

if ((KEEP==0)); then
    trap 'rm -rf "$dir"' EXIT QUIT INT
else
    txt "Output will be kept at: '$dir'"
fi

if ! [[ -d $dir ]]; then
    mkdir -p "$dir"
fi

case "$(uname)" in
    WindowsNT)
        # bash v4 on Windows CI requires CRLF separator
        if [[ ${BASH_VERSION%%.*} -ge 4 ]]; then
            newlineIFS=$'\r\n'
            debug "Setting custom IFS for Bash 4+ on Windows"
        fi
        ;;
esac

fetch_blob() {
    local url="$1"
    shift
    local targetFile="$1"
    shift

    debug "Processing BLOB at '$url'"

    ## This magic is to workaround from curl passing the Bearer-Token to a redirected resource
    ## that is pointing to the BLOB because AmazonS3 does not like having an Authorization header
    ## when serving. See for more information: 
    ##    https://github.com/moby/moby/issues/33700
    ##    https://stackoverflow.com/questions/37865875/stopping-curl-from-sending-authorization-header-on-302-redirect

    local redirectUrl targetHeader rc=0
    targetHeader="$(
        curl \
            --show-error --head --silent \
            --output /dev/null \
            --dump-header - \
            ${AUTHENTICATION:+ --header "Authorization: $AUTHENTICATION"} \
                "$url"
    )"
    debug -i "$targetHeader"
    redirectUrl="$(
        awk '
                BEGIN { IGNORECASE = 1; NOT_DIRECT = 0; }

                # Strip silly characters, replaces the "tr -d" command of the original script
                { gsub(/\r/,""); }

                # This usually is output when you are going through a proxy:
                #  HTTP/1.1 200 Connection established
                $1 ~ /^HTTP/ && $2 == "200" && /Connection established/ { next; }

                # File is served directly 
                $1 ~ /^HTTP/ && $2 == "200" { exit 10; }

                # Example for redirect:
                #  HTTP/1.1 307 Temporary Redirect
                $1 ~ /^HTTP/ && $2 != "200" { NOT_DIRECT = 1; }
                $1 == "Location:" {
                    print $2;
                    exit 11;
                }
        ' <<<"$targetHeader" 
    )" || rc=$?;
    case $rc in
        10) 
            debug "File is downloading directly via original URL."
            curl \
                --fail --show-error --location $PROGRESS \
                --output "$targetFile" \
                ${AUTHENTICATION:+ --header "Authorization: $AUTHENTICATION"} \
                    "$url" || \
                { error "Could not download '$url', curl error $?"; exit 1; }

            ;;
        11)
            # We got a redirect so we retrieve the redirect target without any Bearer token auth
            debug "File is downloading from a redirected URL."
            debug -i "redirect_url: $redirectUrl"
            url="$redirectUrl"
            curl \
                --fail --show-error --location $PROGRESS \
                --output "$targetFile" \
                    "$url" || \
                { error "Could not download '$url', curl error $?"; exit 1; }
            ;;
        *)
            error "Failed fetching '$url': unhandled error"
            debug -i "$redirectUrl"
            ;;
    esac

    if ! [[ -s "$targetFile" ]]; then
        error "Failed to fetch URL '$url': File size is zero!"
        exit 1
    fi

    debug "BLOB saved at '$targetFile'"
}

fetch_manifest() {
    local manifestUrl="$1"
    curl \
        --silent --show-error --location --fail \
        ${AUTHENTICATION:+ --header "Authorization: $AUTHENTICATION"} \
        --header 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
        --header 'Accept: application/vnd.docker.distribution.manifest.list.v2+json' \
        --header 'Accept: application/vnd.docker.distribution.manifest.v1+json' \
            "$manifestUrl"
}

fetch_digest() {
    local manifestUrl="$1"
    local manifest_Header="$(
        curl \
            --silent --location --head \
            ${AUTHENTICATION:+ --header "Authorization: $AUTHENTICATION"} \
            --header 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
            --header 'Accept: application/vnd.docker.distribution.manifest.list.v2+json' \
                "$manifestUrl" 2> /dev/null
    )"
    awk '
        BEGIN { IGNORECASE = 1; }
        { gsub(/\r/,""); }
        /^docker-content-digest:/ { print $2; exit; }
    ' <<<"$manifest_Header";
}

fssize() {
    local file="$1" timing="$2"
    stat -c %s "$file" | awk -v TIME="$timing" '
        function format_size(size, x, f) {
            f[1024^3]="GiB";
            f[1024^2]="MiB";
            f[1024^1]="KiB";
            f[1024^0]="bytes";

            for (x=1024^3; x>=1; x/=1024) {
                if (size >= x) {
                    return sprintf("%.1f %s", size/x, f[x]);
                }
            }
        }
        function format_time(sec, x, fullpart, subpart, f) {
            if (sec<0) {
                return;
            }
            f[60^2] = "h";
            f[60^1] = "m";
            f[60^0] = "s";
            if (sec==0) {
                return "0s";
            }
            for (x=60^3; x>=1; x/=60) {
                if (sec >= x) {
                    fullpart = int(sec/x);
                    subpart = sec - ( fullpart * x );
                    if (subpart == 0) {
                        return sprintf("%s%s", fullpart, f[x] );
                    } else {
                        return sprintf("%s%s %s", fullpart, f[x], format_time(subpart) );
                    }
                    break;
                }
            }
        }
        { printf "%s/%s\n", format_size($0), format_time(TIME); }
    '
}

# handle 'application/vnd.docker.distribution.manifest.v2+json' manifest
handle_single_manifest_v2() {
    local manifestJson="$1"
    shift

    local configDigest="$( jq --raw-output '.config.digest' <<<"$manifestJson" )"
    local imageId="$( awk -F':' '{print $2}' <<<"$configDigest" )"

    debug "Processing manifest $imageId"
    debug -i "$manifestJson"

    local configFile="${imageId}.json"
    fetch_blob "$urlBase/blobs/$configDigest" "$dir/$configFile"

    local layersFs="$(echo "$manifestJson" | jq --raw-output --compact-output '.layers[]')"
    local IFS="$newlineIFS"
    local layers=($layersFs)
    unset IFS

    local layerCount="${#layers[@]}"
    txt "  - Processing ${layerCount} layers..."
    local layerId=
    local layerFiles=()
    for i in "${!layers[@]}"; do
        local layerMeta="${layers[$i]}"

        local layerMediaType="$(echo "$layerMeta" | jq --raw-output '.mediaType')"
        local layerDigest="$(echo "$layerMeta" | jq --raw-output '.digest')"

        debug "Processing Layer '$layerDigest' having type '$layerMediaType'"
        debug -i "$layerMeta"

        # save the previous layer's ID
        local parentId="$layerId"
        # create a new fake layer ID based on this layer's digest and the previous layer's fake ID
        # this accounts for the possibility that an image contains the same layer twice (and thus has a duplicate digest value)
        layerId="$(echo "$parentId"$'\n'"$layerDigest" | sha256sum | awk '{print $1}' )"

        mkdir -p "$dir/$layerId"
        echo '1.0' > "$dir/$layerId/VERSION"

        if [ ! -s "$dir/$layerId/json" ]; then
            local parentJson="$(printf ', parent: "%s"' "$parentId")"
            local addJson="$(printf '{ id: "%s"%s }' "$layerId" "${parentId:+$parentJson}")"
            # this starter JSON is taken directly from Docker's own "docker save" output for unimportant layers
            jq "$addJson + ." > "$dir/$layerId/json" <<<'
                {
                    "created": "0001-01-01T00:00:00Z",
                    "container_config": {
                        "Hostname": "",
                        "Domainname": "",
                        "User": "",
                        "AttachStdin": false,
                        "AttachStdout": false,
                        "AttachStderr": false,
                        "Tty": false,
                        "OpenStdin": false,
                        "StdinOnce": false,
                        "Env": null,
                        "Cmd": null,
                        "Image": "",
                        "Volumes": null,
                        "WorkingDir": "",
                        "Entrypoint": null,
                        "OnBuild": null,
                        "Labels": null
                    }
                }
            ';
        fi

        case "$layerMediaType" in
            application/vnd.docker.image.rootfs.diff.tar.gzip)
                local layerTar="$layerId/layer.tar"
                layerFiles+=("$layerTar")
                local comment="" download
                local checksum_should="$( awk -F':' '{print $2}' <<<"${layerDigest}" )"
                if [ -f "$dir/$layerTar" ]; then
                    debug "Starting verification of already downloaded file: $dir/$layerTar"
                    debug -i "checksum_should=$checksum_should"
                    T0=$SECONDS
                    local checksum_is="$( sha256sum "$dir/$layerTar" | awk '{print $1}' )"
                    T1=$SECONDS
                    debug -i "checksum_is=$checksum_is"
                    if [[ $checksum_should != $checksum_is ]]; then
                        debug "Digest Verification failed, removing corrupted file"
                        rm -f "$dir/$layerTar"
                        comment="Re-Downloaded"
                        download=1
                    else
                        debug "Digest Verification succeded, keeping file and skipping download."
                        comment="Verified"
                        download=0
                    fi
                else
                    download=1
                    comment="Downloaded"
                fi
                if ((download)); then
                    if ((CHECK==1)); then
                        echo "CHECK FAILURE ->$CHECK"
                        exit 123
                    fi
                    T0=$SECONDS
                    fetch_blob "$urlBase/blobs/$layerDigest" "$dir/$layerTar"
                    T1=$SECONDS
                fi
                comment+=" $( fssize "$dir/$layerTar" $((T1-T0)) )"
                ((QUIET)) || printf "    [%02d/%02d] Layer %s: %s\n" "$((i+1))" "$layerCount" "${layerDigest}" "$comment"
                ;;

            *)
                error "Unknown layer mediaType ($imageIdentifier, $layerDigest): '$layerMediaType'"
                exit 1
                ;;
        esac
    done

    # change "$imageId" to be the ID of the last layer we added (needed for old-style "repositories" file which is created later -- specifically for older Docker daemons)
    imageId="$layerId"

    # munge the top layer image manifest to have the appropriate image configuration for older daemons
    local imageOldConfig="$(jq --raw-output --compact-output '{ id: .id } + if .parent then { parent: .parent } else {} end' "$dir/$imageId/json")"
    jq --raw-output "$imageOldConfig + del(.history, .rootfs)" "$dir/$configFile" > "$dir/$imageId/json"

    local manifestJsonEntry="$(
        echo '{}' | jq --raw-output '. + {
            Config: "'"$configFile"'",
            RepoTags: ["'"${image#library\/}:$tag"'"],
            Layers: '"$(echo '[]' | jq --raw-output ".$(for layerFile in "${layerFiles[@]}"; do echo " + [ \"$layerFile\" ]"; done)")"'
        }'
    )"
    manifestJsonEntries+=("$manifestJsonEntry")
} #handle_single_manifest_v2

auth_url() {
    local url="$1"
    local rc=0

    ## Details for registry auth via bearer token:
    ##   https://docs.docker.com/registry/spec/auth/token/

    debug "Checking authentication for url: '$url'"

    # Only fetch header so we will receive the requirements - if any
    auth_hdr="$( curl -s --location --head "$url" )" || { error "Could not retrieve headers for '$url': curl error $?"; exit 1; }
    debug -i "${auth_hdr}"

    auth_url="$( awk '
        BEGIN { 
            for (i = 0; i <= 255; i++) ord[sprintf("%c", i)] = i; 
            IGNORECASE = 1; 
            HTTP_LINE="";
            HTTP_RESPONSE=0;
            RC=0;
        }

        # URLEncode function from: https://rosettacode.org/wiki/URL_encoding#AWK
        function escape(str,    c, len, res) {
            len = length(str)
            res = ""
            for (i = 1; i <= len; i++) {
                c = substr(str, i, 1);
                if (c ~ /[0-9A-Za-z]/)
                    res = res c
                else
                    res = res "%" sprintf("%02X", ord[c])
            }
            return res
        }

        # Strip silly characters, replaces the "tr -d" command of the original script
        { gsub(/\r/,""); }

        # This usually is output when you are going through a proxy:
        #  HTTP/1.1 200 Connection established
        # We store this and check if we got a second HTTP header, and if yes, ignore this one
        # This could be solved by a CLI option, but this is "quite" recent, so not sure all
        # curl version support it yet: 
        #  ref: https://curl.haxx.se/libcurl/c/CURLOPT_SUPPRESS_CONNECT_HEADERS.html
        $1 ~ /^HTTP\// { HTTP_LINE=$0; HTTP_RESPONSE=$2; next; }

        # We received an authentication request we must fulfill. Right now we can only handle Bearer Token
        # We output the whole line and exit with specific error code, error handling will be done on bash level
        $1 ~ /^www-authenticate:/ {
            if ($2 ~ /Basic/) {
                RC=17;
                exit
            }
            if ($2 !~ /Bearer/) {
                print $0;
                RC=12;
                exit;
            }

            begin = match($0, /realm="([^"]+)",service="([^"]+)",scope="([^"]+)"/ , result);
            if (begin == 0) {
                # We did not manage to parse the results into the "result" array
                print $0;
                RC=13;
                exit;
            }
            printf "%s?service=%s&scope=%s\n", result[1], escape(result[2]), result[3];
            RC=10;
            exit;
        }

        END {
            if (RC>0) { exit RC; }
            # We did not receive an authenticate-header, so we have to check whats going on.
            print HTTP_LINE;
            if (substr(HTTP_RESPONSE,0,1) == "2") {
                # HTTP 2xx: Success
                exit 11;
            }
            if (HTTP_RESPONSE == "404") {
                # Not found: image does not exist
                exit 15;
            }
            if (HTTP_RESPONSE == "401") {
                # Unauthorized
                exit 16;
            }
            # Something else happened...
            exit 14;
        }
        ' <<<"$auth_hdr"
    )" || rc=$?;
    case $rc in
        10|17)
            # Expected outcome
            debug "Authentication is required"
            if ((AUTH == 1)); then
                if [[ -n $AUTHCRED ]]; then
                    auth_cred="$AUTHCRED"
                    txt  "  - Using Credentials via CLI"
                elif [[ -n ${AUTHENV} ]]; then
                    if [[ -n ${!AUTHENV} ]]; then
                        auth_cred="${!AUTHENV}"
                        txt "  - Using Credentials found in env:${AUTHENV}"
                    else
                        txt -w "Credentials via environment variable '${AUTHENV}' are empty!"
                    fi
                elif [[ -s $AUTHFILE ]]; then
                    auth_cred="$( jq --raw-output '.auths["'$registryService'"].auth' $AUTHFILE 2> /dev/null )" 
                    if [[ $auth_cred = "null" ]]; then
                        auth_cred=""
                        debug "Found auth file at $AUTHFILE but it did not contain anything for $registryService"
                    else
                        txt "  - Using Credentials found in file:$AUTHFILE"
                    fi
                fi
            else
                debug "Sending Authorization is disabled via CLI option"
            fi
            if (( rc == 17 )); then
                if [[ -z $auth_cred ]]; then
                    error "Basic authentication required but no credentials are present"
                    exit 1
                fi
                debug "Testing Basic Auth"
                http_code="$( curl --silent --location --output /dev/null --write-out '%{http_code}' --header "Authorization: Basic ${auth_cred}" "$url" )"
                debug -i "http_result: $http_code"
                case $http_code in
                    401)
                        error "Failed to Authenticate to Registry via Basic Auth: 401 Not Authorized"
                        exit 1
                        ;;
                    404)
                        error "Element not found: are you sure this exists?? '$url'"
                        exit 1
                        ;;
                esac
                AUTHENTICATION="Basic $auth_cred"
                return 0
            else
                debug "Requesting Token at '$auth_url'"
                token_content_w_header="$( 
                    curl \
                        --silent --show-error --location --include \
                        ${auth_cred:+ --header "Authorization: Basic ${auth_cred}"} \
                            "$auth_url"
                )" 
                debug -i "$token_content_w_header"
                token_content="$(
                    awk '
                        BEGIN { HTTP_RESPONSE=0; IGNORECASE = 1; }
                        { gsub(/\r/,""); }
                        $1 ~ /^HTTP\// { HTTP_RESPONSE=$2; next; }
                        /^{/ { print }
                        END {
                            if (HTTP_RESPONSE == "200") { exit 10; }
                            if (HTTP_RESPONSE == "401") { exit 11; }
                            if (HTTP_RESPONSE == "400") { exit 12; }
                        }
                    ' <<<"$token_content_w_header"
                )" || rc=$?;
                case $rc in
                    10)
                        local _token;
                        if ! _token="$(jq --raw-output 'if .token != null  then .token elif .access_token != null then .access_token else "-" end ' 2>/dev/null <<< "$token_content")"; then
                            error "Could not parse valid json from Bearer token request via $auth_url. Use --debug for response content."
                            exit 1
                        fi
                        if [[ $_token = "-" ]]; then
                            error "No Bearer token found in response from $auth_url. Use --debug for response content."
                            exit 1
                        fi
                        debug "Testing Bearer Token Auth"
                        http_code="$( curl --silent --location --output /dev/null --head --write-out '%{http_code}' --header "Authorization: Bearer $_token" "$url" 2> /dev/null )"
                        debug -i "http_result: $http_code"
                        case $http_code in
                            401)
                                error "Failed to Authenticate to Registry via Bearer Token Auth: 401 Not Authorized"
                                exit 1
                                ;;
                            404)
                                error "Element not found: are you sure this exists?? '$url'"
                                exit 1
                                ;;
                        esac
                        debug "Bearer Token validated: ${_token:0:20}..."
                        # Setting the global variable
                        AUTHENTICATION="Bearer $_token"
                        return 0;
                        ;;
                    11)
                        if [[ -z $auth_cred ]]; then
                            error "Failed to Authenticate to Token Service: credentials are required";
                            error "$token_content"
                            exit 1;
                        else
                            error "Failed to Authenticate to Token Service: Authentication using credentails failed. User/Pass might be invalid."; 
                            error "$token_content"
                            exit 1; 
                        fi
                        ;;
                    12)
                        error "Failed to Authenticate to Token Service: Probably badly formatted b64credentials?"
                        error "$token_content"
                        exit 1;
                        ;;
                    *)
                        error "Unknown error during authentication"
                        exit 1
                        ;;
                esac
            fi
            ;;
        11)
            debug "No authentication required"
            # Setting the global variable
            AUTHENTICATION=""
            return 0
            ;;
        12)
            error "Authentication type is not Bearer token, cannot handle this auth schema! Use --debug for more details"
            debug "Authentication header: '$auth_url'"
            exit 1;
            ;;
        13)
            error "Could not parse authentication request from registry to request a token! Use --debug for more details"
            debug "Authentication header: '$auth_url'"
            exit 1;
            ;;
        14)
            error "Unhandled HTTP response: '$auth_url'";
            exit 1;
            ;;
        15)
            error "Image does not exists (HTTP 404)"
            debug "Authentication header: '$auth_url'"
            exit 1;
            ;;
        16)
            error "We are not authorized to access that resource (HTTP 401)"
            debug "Authentication header: '$auth_url'"
            exit 1;
            ;;
        *)
            error "Unknown error during authentication: rc=$rc"
            debug -i "$auth_url"
            exit 1;
            ;;
    esac
}

debug "Starting main processing of images..."
rm -f "$dir"/tags-*.tmp
DOWNLOAD_START=$SECONDS

ARGC="${#ARGS[@]}"
txt "Processing ${ARGC} images..."

for ind in "${!ARGS[@]}"; do
    ## Bash regex matching with capture groups
    ##
    ## Capture groups 1 + 3 should be non-capturing, but bash does not support PCRE
    ## using (?:..), so we have to count them but dismiss the content as they are
    ## basically identical to 2+4 including a suffixed "/".
    ## Same goes for groups 6+8: they make sure we find the :tag and @checksum parts properly
    ## but their content can be discarded
    ##
    ## The numbering is differ if registry is set:
    ##   BASH_REMATCH:     2             4          5     7   9
    ##   image_descriptor='registry.fqdn/repository/image:tag@sha256:checksum'
    ##
    ## If the registry is not defined, the repository is catched already by 2nd instead of 4th:
    ##   BASH_REMATCH:     2          5     7   9
    ##   image_descriptor='repository/image:tag@sha256:checksum'
    ##
    ## According to the docker engine code, the registry part is qualified by either having a dot or a colon:
    ##  ref: https://github.com/docker/docker-ce/blob/9afcfdceb553fd39baf0db64033dd544a0847cca/components/engine/registry/service.go#L151
    ##

    image_descriptor="${ARGS[$ind]}"
    txt " [$((ind+1))/$ARGC] Image '${image_descriptor}'..."

    ## Capture groups:              1 2        3 4        5        6 7        8 9
    if ! [[ "$image_descriptor" =~ ^(([^/]+)/)?(([^/]+)/)?([^:@/]+)(:([^@]+))?(@(.+))?$ ]]; then
        txt "  - Skipping malformatted image name"
        continue
    fi
    debug "Capture groups matched (check out source around line $LINENO)"
    for ((i=0; i < ${#BASH_REMATCH[@]}; ++i)); do
        debug -i " BASH_REMATCH[$i]  = ${BASH_REMATCH[$i]}"
    done

    # Default docker registry base and Auth Service used to lookup auth credentials
    # This is the "full index address of the official index" and hostname:port for private ones
    #  ref: https://github.com/docker/docker-ce/blob/e0e6de2e0ddf383ed5bf9099512e32afcf121eda/components/engine/registry/config.go#L397
    #  ref: https://github.com/docker/docker-ce/blob/e0e6de2e0ddf383ed5bf9099512e32afcf121eda/components/engine/registry/config.go#L39

    registryBase='https://registry-1.docker.io'
    registryService="https://index.docker.io/v1/"

    # This is the 'repo' part of the 'repo/image' format, which will default to library if undefined
    repository=""

    # The effective image name which always matches on capture group 5, because the other groups also include a / at the end
    imagename="${BASH_REMATCH[5]}"

    # The :tag suffix without :, if set, but always at 7
    tag="${BASH_REMATCH[7]}"

    # The tailing @sha:checksum suffix without @, if set, but always at 9
    digest="${BASH_REMATCH[9]}"

    # We need to have a tag or a digest otherwise download will fail, so we fall back to latest if no tag is set
    if [[ -z $tag ]]; then
        tag='latest'
    fi

    # If no digest is set, we will have to used the tag during the API calls
    if [[ -z $digest ]]; then
        reference="$tag"
    else
        reference="$digest"
    fi

    # We need to save them because we want to make another regex match, that would overwrite them.
    G2="${BASH_REMATCH[2]}"
    G4="${BASH_REMATCH[4]}"

    if [[ -n "$G2" ]]; then
        if [[ ${G2} =~ [.:]+ ]] || [[ -n ${G4} ]]; then
            # Matches:
            #   <G2:registry.fqdn:port>/<G5:image>
            #   <G2:registry>/<G4:repository>/<G5:image>

            # We have a remote registry, so repository might even be empty, will handle it later
            registryService="${G2}"
            registryBase="${PROTOCOL}://${registryService}"

            # Only prepend repository if it is set
            repository="${G4}"
            imageFile="${repository:+${repository}_}${imagename}"
            image="${repository:+${repository}/}${imagename}"
        else
            # Matches:
            #   <G2:repo>/<G5:image>

            # We have an official image with a repository
            repository="${G2}"
            imageFile="${repository}_${imagename}"
            image="${repository}/${imagename}"
        fi
    else
        # Matches:
        #   <G5:image>

        # We have an image from the library
        repository="library"
        imageFile="${repository}_${imagename}"
        image="${repository}/${imagename}"
    fi

    imageIdentifier="$image${tag:+:$tag}${digest:+@$digest}"
    urlBase="$registryBase/v2/$image"
    manifestUrl="$urlBase/manifests/$reference"

    debug "Parsing image name completed, use additional --debug for details."
    debug -i "registryService => '$registryService'"
    debug -i "registryBase    => '$registryBase'"
    debug -i "image           => '$image'"
    debug -i "tag             => '$tag'"
    debug -i "digest          => '$digest'"
    debug -i "reference       => '$reference'"
    debug -i "urlBase         => '$urlBase'"
    debug -i "manifestUrl     => '$manifestUrl'"

    auth_url "$manifestUrl" || continue
    
    debug "Retrieving digest for image"
    manifestDigest="$( fetch_digest "$manifestUrl" )"
    debug -i "manifestDigest=$manifestDigest"
    if [[ -n $manifestDigest ]]; then
        txt "  - Digest: $manifestDigest"
    fi
    debug "Downloading manifest"
    debug -i "url: '$urlBase/manifests/$reference'"
    manifestJson="$( fetch_manifest "$manifestUrl" )" || { error "Could not download manifest '$manifestUrl', curl error $?"; exit 1; }
    debug -i "$manifestJson"

    if [ "${manifestJson:0:1}" != '{' ]; then
        error "Manifest URL '$manifestUrl' returned something that appears to be not JSON. Use --debug for further details."
        exit 1
    fi

    schemaVersion="$(echo "$manifestJson" | jq --raw-output '.schemaVersion')"
    debug "Schema version: $schemaVersion"
    case "$schemaVersion" in
        2)
            mediaType="$(echo "$manifestJson" | jq --raw-output '.mediaType')"

            case "$mediaType" in
                application/vnd.docker.distribution.manifest.v2+json)
                    handle_single_manifest_v2 "$manifestJson"
                    ;;
                application/vnd.docker.distribution.manifest.list.v2+json)
                    layersFs="$(echo "$manifestJson" | jq --raw-output --compact-output '.manifests[]')"
                    IFS="$newlineIFS"
                    layers=($layersFs)
                    unset IFS

                    found=""
                    # parse first level multi-arch manifest
                    for i in "${!layers[@]}"; do
                        layerMeta="${layers[$i]}"
                        maniArch="$(echo "$layerMeta" | jq --raw-output '.platform.architecture')"
                        if [[ "$maniArch" = "$ARCH" ]]; then
                            digest="$(echo "$layerMeta" | jq --raw-output '.digest')"
                            submanifestUrl="$urlBase/manifests/$digest"
                            # get second level single manifest
                            debug "Downloading second level single manifest for '$ARCH' architecture."
                            debug -i "url: '$submanifestUrl'"
                            submanifestJson="$( fetch_manifest "$submanifestUrl" )" || { error "Could not download sub-manifest '$submanifestUrl', curl error $?"; exit 1; }
                            debug -i "$submanifestJson"
                            handle_single_manifest_v2 "$submanifestJson" 
                            found="found"
                            break
                        else
                            debug "Skipped Manifest with architecture $maniArch which is not $ARCH"
                        fi
                    done
                    if [ -z "$found" ]; then
                        error "Manifest for $maniArch is not found"
                        exit 1
                    fi
                    ;;
                *)
                    error "Unknown manifest mediaType ($imageIdentifier): '$mediaType'"
                    exit 1
                    ;;
            esac
            ;;

        1)
            if [ -z "$doNotGenerateManifestJson" ]; then
                txt -w "Image '$imageIdentifier' uses schemaVersion '$schemaVersion'"
                txt -w " this script cannot (currently) recreate the 'image config' to put in a 'manifest.json',"
                txt -w " thus any schemaVersion 2+ images will be imported in the old way, and their 'docker history' will suffer!"
                doNotGenerateManifestJson=1
            fi

            layersFs="$(echo "$manifestJson" | jq --raw-output '.fsLayers | .[] | .blobSum')"
            IFS="$newlineIFS"
            layersBlobSum=($layersFs)
            unset IFS

            historyJson="$(echo "$manifestJson" | jq '.history | [.[] | .v1Compatibility]')"
            imageId="$(echo "$history" | jq --raw-output '.[0]' | jq --raw-output '.id')"

            local layerCount="${#layersBlobSum[@]}"
            txt "  - Processing ${layerCount} layers..."
            for i in "${!layersBlobSum[@]}"; do
                imageJson="$(echo "$historyJson" | jq --raw-output ".[${i}]")"
                layerId="$(echo "$imageJson" | jq --raw-output '.id')"
                layerDigest="${layersBlobSum[$i]}"
                layerTar="$layerId/layer.tar"

                mkdir -p "$dir/$layerId"
                echo '1.0' > "$dir/$layerId/VERSION"
                echo "$imageJson" > "$dir/$layerId/json"

                local checksum_should="$( awk -F':' '{print $2}' <<<"${layerDigest}" )"
                if [ -f "$dir/$layerTar" ]; then
                    debug "Starting verification of already downloaded file: $dir/$layerTar"
                    debug -i "checksum_should=$checksum_should"
                    T0=$SECONDS
                    local checksum_is="$( sha256sum "$dir/$layerTar" | awk '{print $1}' )"
                    T1=$SECONDS
                    debug -i "checksum_is=$checksum_is"
                    if [[ $checksum_should != $checksum_is ]]; then
                        debug "Digest Verification failed, removing corrupted file"
                        rm -f "$dir/$layerTar"
                        comment="Re-Downloaded"
                        download=1
                    else
                        debug "Digest Verification succeded, keeping file and skipping download."
                        comment="Verified"
                        download=0
                    fi
                else
                    download=1
                    comment="Downloaded"
                fi
                if ((download)); then
		    if ((CHECK==1)); then
			error  "CHECK FAILURE 2 ->$CHECK"
			exit 123
		    fi
                    T0=$SECONDS
                    fetch_blob "$urlBase/blobs/$layerDigest" "$dir/$layerTar"
                    T1=$SECONDS
                fi
                comment+=" $( fssize "$dir/$layerTar" $((T1-T0)) )"
                ((QUIET)) || printf "    [%02d/%02d] Layer %s: %s\n" "$((i+1))" "$layerCount" "${layerDigest}" "$comment"
            done
            ;;

        *)
            error "Unknown manifest schemaVersion ($imageIdentifier): '$schemaVersion'"
            exit 1
            ;;
    esac

    if [ -s "$dir/tags-$imageFile.tmp" ]; then
        echo -n ', ' >> "$dir/tags-$imageFile.tmp"
    else
        images+=("$image")
    fi

    echo -n '"'"$tag"'": "'"$imageId"'"' >> "$dir/tags-$imageFile.tmp"
done

echo -n '{' > "$dir/repositories"
firstImage=1
for image in "${images[@]}"; do
    imageFile="$( tr '/' '_' <<<"${image}")" # "/" can't be in filenames :)
    image="${image#library\/}"

    [ "$firstImage" ] || echo -n ',' >> "$dir/repositories"
    firstImage=
    echo -n $'\n\t' >> "$dir/repositories"
    echo -n '"'"$image"'": { '"$(cat "$dir/tags-$imageFile.tmp")"' }' >> "$dir/repositories"
done
echo -n $'\n}\n' >> "$dir/repositories"
rm -f "$dir"/tags-*.tmp
if [ -z "$doNotGenerateManifestJson" ] && [ "${#manifestJsonEntries[@]}" -gt 0 ]; then
    echo '[]' | jq --raw-output ".$(for entry in "${manifestJsonEntries[@]}"; do echo " + [ $entry ]"; done)" > "$dir/manifest.json"
else
    rm -f "$dir/manifest.json"
fi

DOWNLOAD_END=$SECONDS

txt "Done processing images. It took $((DOWNLOAD_END-DOWNLOAD_START)) seconds."

if ((LOAD == 1)); then
    txt "Loading image into docker..."
    tar -cC "$dir" . | docker load $( ((QUIET)) && echo '--quiet' )
    exit $?
fi

if ((STDOUT == 1)); then
    txt "Streaming tar to stdout..."
    tar -cC "$dir" .
    exit $?
fi

if [[ $DESTFILE != "" ]]; then
    txt "Creating destination file '$DESTFILE'"
    tar -cC "$dir" . -f $DESTFILE
    exit $?
fi

