#!/bin/bash
if [ "$(ps -o comm= $PPID)" == "systemd" ]; then
    IS_SYSTEMD=1
else
    IS_SYSTEMD=0
fi
log() {
	if [[ $IS_SYSTEMD == 1 ]]; then
		echo $1
	else
		echo "$(date --rfc-3339 sec): $1"
	fi
}

validate_upstream() {
    local upstream="$1"

    if [[ -z "$upstream" ]] || [[ "$upstream" =~ ^[[:space:]]*# ]]; then
        return 0
    fi

    if [[ "$upstream" =~ ^\[/[^/]+/\](.+)$ ]]; then
        local actual_upstream="${BASH_REMATCH[1]}"
        if [[ "$actual_upstream" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || \
           [[ "$actual_upstream" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:[0-9]+$ ]] || \
           [[ "$actual_upstream" =~ ^[0-9a-fA-F:]+$ ]] || \
           [[ "$actual_upstream" =~ ^\[[0-9a-fA-F:]+\]$ ]] || \
           [[ "$actual_upstream" =~ ^\[[0-9a-fA-F:]+\]:[0-9]+$ ]] || \
           [[ "$actual_upstream" =~ ^(udp|tcp)://[^/]+$ ]] || \
           [[ "$actual_upstream" =~ ^tls://[^/]+$ ]] || \
           [[ "$actual_upstream" =~ ^https://[^/]+/dns-query$ ]] || \
           [[ "$actual_upstream" =~ ^h3://[^/]+/dns-query$ ]] || \
           [[ "$actual_upstream" =~ ^quic://[^/]+$ ]] || \
           [[ "$actual_upstream" =~ ^sdns:// ]]; then
            return 0
        fi
        return 1
    fi

    if [[ "$upstream" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || \
       [[ "$upstream" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:[0-9]+$ ]] || \
       [[ "$upstream" =~ ^[0-9a-fA-F:]+$ ]] || \
       [[ "$upstream" =~ ^\[[0-9a-fA-F:]+\]$ ]] || \
       [[ "$upstream" =~ ^\[[0-9a-fA-F:]+\]:[0-9]+$ ]] || \
       [[ "$upstream" =~ ^(udp|tcp)://[^/]+$ ]] || \
       [[ "$upstream" =~ ^tls://[^/]+$ ]] || \
       [[ "$upstream" =~ ^https://[^/]+/dns-query$ ]] || \
       [[ "$upstream" =~ ^h3://[^/]+/dns-query$ ]] || \
       [[ "$upstream" =~ ^quic://[^/]+$ ]] || \
       [[ "$upstream" =~ ^sdns:// ]]; then
        return 0
    fi

    return 1
}

validate_dns_server() {
    local dns_server="$1"

    if [[ "$dns_server" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || \
       [[ "$dns_server" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:[0-9]+$ ]] || \
       [[ "$dns_server" =~ ^[0-9a-fA-F:]+$ ]] || \
       [[ "$dns_server" =~ ^\[[0-9a-fA-F:]+\]$ ]] || \
       [[ "$dns_server" =~ ^\[[0-9a-fA-F:]+\]:[0-9]+$ ]] || \
       [[ "$dns_server" =~ ^(udp|tcp)://[^/]+$ ]] || \
       [[ "$dns_server" =~ ^tls://[^/]+$ ]] || \
       [[ "$dns_server" =~ ^https://[^/]+/dns-query$ ]] || \
       [[ "$dns_server" =~ ^h3://[^/]+/dns-query$ ]] || \
       [[ "$dns_server" =~ ^quic://[^/]+$ ]] || \
       [[ "$dns_server" =~ ^sdns:// ]]; then
        return 0
    fi

    return 1
}

replace_dns_in_upstream() {
    local line="$1"
    local replacement_dns="$2"

    if [[ "$line" =~ ^\[/[^/]+/\](.+)$ ]]; then
        local domain_part="${line%]*}"
        echo "${domain_part}]${replacement_dns}"
    else
        echo "$line"
    fi
}

DEFAULT_UPSTREAMS=()
DEFAULT_UPSTREAM_FILE=""
UPSTREAM_FILE_URL="https://gitlab.com/fernvenue/chn-domains-list/-/raw/master/CHN.ALL.agh"
OUTPUT_FILE="/opt/AdGuardHome/AdGuardHome.upstream"
REPLACE_UPSTREAM_DNS=""
RESTART_SERVICE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --default-upstream)
            if [[ -z "$2" ]]; then
                log "Error: --default-upstream requires an argument"
                exit 1
            fi
            if ! validate_upstream "$2"; then
                log "Error: Invalid upstream format: $2"
                exit 1
            fi
            log "Validated upstream: $2"
            DEFAULT_UPSTREAMS+=("$2")
            shift 2
            ;;
        --default-upstream-file)
            if [[ -z "$2" ]]; then
                log "Error: --default-upstream-file requires an argument"
                exit 1
            fi
            if [[ ! -f "$2" ]]; then
                log "Error: File not found: $2"
                exit 1
            fi
            DEFAULT_UPSTREAM_FILE="$2"
            shift 2
            ;;
        --upstream-file)
            if [[ -z "$2" ]]; then
                log "Error: --upstream-file requires an argument"
                exit 1
            fi
            if [[ ! "$2" =~ ^https?:// ]]; then
                log "Error: --upstream-file must be a valid HTTP or HTTPS URL: $2"
                exit 1
            fi
            UPSTREAM_FILE_URL="$2"
            shift 2
            ;;
        --output-file)
            if [[ -z "$2" ]]; then
                log "Error: --output-file requires an argument"
                exit 1
            fi
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --replace-upstream-dns)
            if [[ -z "$2" ]]; then
                log "Error: --replace-upstream-dns requires an argument"
                exit 1
            fi
            if ! validate_dns_server "$2"; then
                log "Error: Invalid DNS server format: $2"
                exit 1
            fi
            log "Validated replacement DNS server: $2"
            REPLACE_UPSTREAM_DNS="$2"
            shift 2
            ;;
        --restart-service)
            if [[ -z "$2" || "$2" == --* ]]; then
                log "Error: --restart-service requires a service name"
                exit 1
            else
                if [[ "$2" != *.service ]]; then
                    RESTART_SERVICE="${2}.service"
                    log "Service name processed: $2 -> $RESTART_SERVICE"
                else
                    RESTART_SERVICE="$2"
                fi
                shift 2
            fi
            ;;
        *)
            log "Error: Unknown parameter: $1"
            exit 1
            ;;
    esac
done

if [[ ${#DEFAULT_UPSTREAMS[@]} -eq 0 && -z "$DEFAULT_UPSTREAM_FILE" ]]; then
    log "Error: At least one --default-upstream or --default-upstream-file must be specified"
    exit 1
fi

set -e


log "Creating default upstream configuration..."

> "/tmp/default.upstream"

for upstream in "${DEFAULT_UPSTREAMS[@]}"; do
    echo "$upstream" >> "/tmp/default.upstream"
done

if [[ -n "$DEFAULT_UPSTREAM_FILE" ]]; then
    log "Validating upstream file: $DEFAULT_UPSTREAM_FILE"
    while IFS= read -r line; do
        if ! validate_upstream "$line"; then
            log "Error: Invalid upstream format in file: $line"
            exit 1
        fi
        if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]]; then
            echo "$line" >> "/tmp/default.upstream"
        fi
    done < "$DEFAULT_UPSTREAM_FILE"
    log "Upstream file validation completed: $DEFAULT_UPSTREAM_FILE"
fi

log "Downloading and validating upstream file: $UPSTREAM_FILE_URL"
if ! curl -s "$UPSTREAM_FILE_URL" > "/tmp/upstream.tmp"; then
    log "Error: Failed to download upstream file from $UPSTREAM_FILE_URL"
    exit 1
fi

> "/tmp/custom.upstream"
while IFS= read -r line; do
    if ! validate_upstream "$line"; then
        log "Error: Invalid upstream format in downloaded file: $line"
        exit 1
    fi
    if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]]; then
        if [[ -n "$REPLACE_UPSTREAM_DNS" ]]; then
            processed_line=$(replace_dns_in_upstream "$line" "$REPLACE_UPSTREAM_DNS")
            echo "$processed_line" >> "/tmp/custom.upstream"
        else
            echo "$line" >> "/tmp/custom.upstream"
        fi
    fi
done < "/tmp/upstream.tmp"
log "Upstream file validation completed"
if [[ -n "$REPLACE_UPSTREAM_DNS" ]]; then
    log "Applied DNS server replacement: $REPLACE_UPSTREAM_DNS"
fi

log "Processing data format..."
cat "/tmp/default.upstream" "/tmp/custom.upstream" > "$OUTPUT_FILE"

log "Cleaning..."
rm /tmp/*.upstream /tmp/upstream.tmp

if [[ -n "$RESTART_SERVICE" ]]; then
    log "Restarting service: $RESTART_SERVICE"
    systemctl restart "$RESTART_SERVICE"
else
    log "No service restart requested"
fi

log "All finished!"

unset IS_SYSTEMD