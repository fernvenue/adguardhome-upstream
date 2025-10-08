#!/bin/bash
if [ "$(ps -o comm= $PPID)" == "systemd" ]; then
    IS_SYSTEMD=1
else
    IS_SYSTEMD=0
fi
log() {
	local level="${2:-info}"
	local message="$1"

	case "$level" in
		debug) local_priority=0 ;;
		info) local_priority=1 ;;
		warn) local_priority=2 ;;
		error) local_priority=3 ;;
		*) local_priority=1 ;;
	esac

	case "$LOG_LEVEL" in
		debug) global_priority=0 ;;
		info) global_priority=1 ;;
		warn) global_priority=2 ;;
		error) global_priority=3 ;;
		*) global_priority=1 ;;
	esac

	if [[ $local_priority -ge $global_priority ]]; then
		if [[ $IS_SYSTEMD == 1 ]]; then
			echo "$message"
		else
			echo "$(date --rfc-3339 sec): [${level^^}] $message"
		fi
	fi
}

validate_upstream() {
    local upstream="$1"

    if [[ -z "$upstream" ]] || [[ "$upstream" =~ ^[[:space:]]*# ]]; then
        return 0
    fi

    if [[ "$upstream" =~ ^\[/[^/]+/\](.+)$ ]]; then
        local actual_upstream="${BASH_REMATCH[1]}"
        IFS=' ' read -ra servers <<< "$actual_upstream"
        for server in "${servers[@]}"; do
            if [[ -n "$server" ]]; then
                if ! [[ "$server" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] && \
                   ! [[ "$server" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:[0-9]+$ ]] && \
                   ! [[ "$server" =~ ^[0-9a-fA-F:]+$ ]] && \
                   ! [[ "$server" =~ ^\[[0-9a-fA-F:]+\]$ ]] && \
                   ! [[ "$server" =~ ^\[[0-9a-fA-F:]+\]:[0-9]+$ ]] && \
                   ! [[ "$server" =~ ^(udp|tcp)://[^/]+$ ]] && \
                   ! [[ "$server" =~ ^tls://[^/]+$ ]] && \
                   ! [[ "$server" =~ ^https://[^/]+/dns-query$ ]] && \
                   ! [[ "$server" =~ ^h3://[^/]+/dns-query$ ]] && \
                   ! [[ "$server" =~ ^quic://[^/]+$ ]] && \
                   ! [[ "$server" =~ ^sdns:// ]]; then
                    return 1
                fi
            fi
        done
        return 0
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

send_telegram_notification() {
    local message="$1"

    if [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
        return 0
    fi

    local url="https://${TELEGRAM_CUSTOM_ENDPOINT}/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
    local payload
    payload=$(jq -n --arg chat_id "$TELEGRAM_CHAT_ID" --arg text "$message" '{chat_id: $chat_id, text: $text, parse_mode: "HTML"}')

    if ! curl -s -m 10 --connect-timeout 5 -X POST -H "Content-Type: application/json" -d "$payload" "$url" > /dev/null; then
        log "Failed to send Telegram notification" warn
    else
        log "Telegram notification sent successfully" debug
    fi
}

DEFAULT_UPSTREAMS=()
if [[ -n "${DEFAULT_UPSTREAMS_ENV:-}" ]]; then
    IFS=',' read -ra ADDR <<< "$DEFAULT_UPSTREAMS_ENV"
    for upstream in "${ADDR[@]}"; do
        upstream=$(echo "$upstream" | xargs)
        if [[ -n "$upstream" ]]; then
            if ! validate_upstream "$upstream"; then
                log "Error: Invalid upstream format in environment variable: $upstream" error
                exit 1
            fi
            DEFAULT_UPSTREAMS+=("$upstream")
        fi
    done
fi
DEFAULT_UPSTREAM_FILE="${DEFAULT_UPSTREAM_FILE:-}"
UPSTREAM_FILE_URL="${UPSTREAM_FILE_URL:-https://gitlab.com/fernvenue/chn-domains-list/-/raw/master/CHN.ALL.agh}"
OUTPUT_FILE="${OUTPUT_FILE:-/opt/AdGuardHome/AdGuardHome.upstream}"
REPLACE_UPSTREAM_DNS="${REPLACE_UPSTREAM_DNS:-}"
RESTART_SERVICE="${RESTART_SERVICE:-}"
LOG_LEVEL="${LOG_LEVEL:-info}"
VALIDATE_UPSTREAM_FILE="${VALIDATE_UPSTREAM_FILE:-true}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
TELEGRAM_CUSTOM_ENDPOINT="${TELEGRAM_CUSTOM_ENDPOINT:-api.telegram.org}"

while [[ $# -gt 0 ]]; do
    case $1 in
        --default-upstream)
            if [[ -z "$2" ]]; then
                log "Error: --default-upstream requires an argument" error
                exit 1
            fi
            if ! validate_upstream "$2"; then
                log "Error: Invalid upstream format: $2" error
                exit 1
            fi
            log "Validated upstream: $2" debug
            DEFAULT_UPSTREAMS+=("$2")
            shift 2
            ;;
        --default-upstream-file)
            if [[ -z "$2" ]]; then
                log "Error: --default-upstream-file requires an argument" error
                exit 1
            fi
            if [[ ! -f "$2" ]]; then
                log "Error: File not found: $2" error
                exit 1
            fi
            DEFAULT_UPSTREAM_FILE="$2"
            shift 2
            ;;
        --upstream-file)
            if [[ -z "$2" ]]; then
                log "Error: --upstream-file requires an argument" error
                exit 1
            fi
            if [[ ! "$2" =~ ^https?:// ]]; then
                log "Error: --upstream-file must be a valid HTTP or HTTPS URL: $2" error
                exit 1
            fi
            UPSTREAM_FILE_URL="$2"
            shift 2
            ;;
        --output-file)
            if [[ -z "$2" ]]; then
                log "Error: --output-file requires an argument" error
                exit 1
            fi
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --replace-upstream-dns)
            if [[ -z "$2" ]]; then
                log "Error: --replace-upstream-dns requires an argument" error
                exit 1
            fi
            if ! validate_dns_server "$2"; then
                log "Error: Invalid DNS server format: $2" error
                exit 1
            fi
            log "Validated replacement DNS server: $2" debug
            REPLACE_UPSTREAM_DNS="$2"
            shift 2
            ;;
        --restart-service)
            if [[ -z "$2" || "$2" == --* ]]; then
                log "Error: --restart-service requires a service name" error
                exit 1
            else
                if [[ "$2" != *.service ]]; then
                    RESTART_SERVICE="${2}.service"
                    log "Service name processed: $2 -> $RESTART_SERVICE" debug
                else
                    RESTART_SERVICE="$2"
                fi
                shift 2
            fi
            ;;
        --log-level)
            if [[ -z "$2" ]]; then
                log "Error: --log-level requires an argument" error
                exit 1
            fi
            case "$2" in
                debug|info|warn|error)
                    LOG_LEVEL="$2"
                    ;;
                *)
                    log "Error: Invalid log level '$2'. Valid levels are: debug, info, warn, error" error
                    exit 1
                    ;;
            esac
            shift 2
            ;;
        --validate-upstream-file)
            VALIDATE_UPSTREAM_FILE=true
            shift
            ;;
        --telegram-bot-token)
            if [[ -z "$2" ]]; then
                log "Error: --telegram-bot-token requires an argument" error
                exit 1
            fi
            TELEGRAM_BOT_TOKEN="$2"
            shift 2
            ;;
        --telegram-chat-id)
            if [[ -z "$2" ]]; then
                log "Error: --telegram-chat-id requires an argument" error
                exit 1
            fi
            TELEGRAM_CHAT_ID="$2"
            shift 2
            ;;
        --telegram-custom-endpoint)
            if [[ -z "$2" ]]; then
                log "Error: --telegram-custom-endpoint requires an argument" error
                exit 1
            fi
            if ! [[ "$2" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
                log "Error: Invalid domain format: $2" error
                exit 1
            fi
            TELEGRAM_CUSTOM_ENDPOINT="$2"
            shift 2
            ;;
        --help|-h)
            cat << EOF
DNS Upstream Configuration Script

OPTIONS:
    --default-upstream <DNS_SERVER> (required, can be used multiple times)
        Add default upstream (AdGuardTeam/dnsproxy format).
        Environment variable: DEFAULT_UPSTREAMS_ENV (comma-separated)

    --default-upstream-file <FILE> (optional)
        Local file with default upstreams (one per line).
        Environment variable: DEFAULT_UPSTREAM_FILE

    --upstream-file <URL> (optional)
        URL to download upstream file from (default: https://gitlab.com/fernvenue/chn-domains-list/-/raw/master/CHN.ALL.agh).
        Environment variable: UPSTREAM_FILE_URL

    --output-file <FILE> (optional)
        Output file path (default: /opt/AdGuardHome/AdGuardHome.upstream).
        Environment variable: OUTPUT_FILE

    --replace-upstream-dns <DNS_SERVER> (optional)
        Replace DNS servers in [/domain/]dns entries.
        Environment variable: REPLACE_UPSTREAM_DNS

    --restart-service <SERVICE> (optional)
        Restart systemd service after processing.
        Environment variable: RESTART_SERVICE

    --log-level <LEVEL> (optional)
        Logging level: debug, info, warn, error (default: info).
        Environment variable: LOG_LEVEL

    --validate-upstream-file (optional)
        Enable validation of downloaded upstream file (default: true).
        Environment variable: VALIDATE_UPSTREAM_FILE

    --telegram-bot-token <TOKEN> (optional)
        Telegram bot token for notifications.
        Environment variable: TELEGRAM_BOT_TOKEN

    --telegram-chat-id <ID> (optional)
        Telegram chat ID for notifications.
        Environment variable: TELEGRAM_CHAT_ID

    --telegram-custom-endpoint <DOMAIN> (optional)
        Custom Telegram API endpoint domain (default: api.telegram.org).
        Environment variable: TELEGRAM_CUSTOM_ENDPOINT

    --help, -h
        Show this help.
EOF
            exit 0
            ;;
        *)
            log "Error: Unknown parameter: $1" error
            exit 1
            ;;
    esac
done

if [[ ${#DEFAULT_UPSTREAMS[@]} -eq 0 && -z "$DEFAULT_UPSTREAM_FILE" ]]; then
    log "Error: At least one --default-upstream or --default-upstream-file must be specified" error
    exit 1
fi

set -e

DEFAULT_DNS_COUNT=0
CUSTOM_DNS_COUNT=0

log "Creating default upstream configuration..."

> "./default.upstream.tmp"
log "Created default upstream file" debug

for upstream in "${DEFAULT_UPSTREAMS[@]}"; do
    log "Adding upstream: $upstream" debug
    echo "$upstream" >> "./default.upstream.tmp" || {
        log "Failed to write to default.upstream.tmp" error
        exit 1
    }
    DEFAULT_DNS_COUNT=$((DEFAULT_DNS_COUNT + 1))
    log "DNS count now: $DEFAULT_DNS_COUNT" debug
done

log "Default upstreams processed: $DEFAULT_DNS_COUNT" debug

if [[ -n "$DEFAULT_UPSTREAM_FILE" ]]; then
    log "Validating upstream file: $DEFAULT_UPSTREAM_FILE"
    while IFS= read -r line; do
        if ! validate_upstream "$line"; then
            log "Error: Invalid upstream format in file: $line"
            exit 1
        fi
        if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]]; then
            echo "$line" >> "./default.upstream.tmp"
            DEFAULT_DNS_COUNT=$((DEFAULT_DNS_COUNT + 1))
        fi
    done < "$DEFAULT_UPSTREAM_FILE"
    log "Upstream file validation completed: $DEFAULT_UPSTREAM_FILE"
fi

log "Downloading and validating upstream file: $UPSTREAM_FILE_URL"
if ! curl -s -m 30 --connect-timeout 10 "$UPSTREAM_FILE_URL" > "./upstream.download.tmp"; then
    log "Error: Failed to download upstream file from $UPSTREAM_FILE_URL" error
    exit 1
fi

> "./custom.upstream.tmp"
while IFS= read -r line; do
    if [[ "$VALIDATE_UPSTREAM_FILE" == "true" ]]; then
        if ! validate_upstream "$line"; then
            log "Error: Invalid upstream format in downloaded file: $line" error
            exit 1
        fi
    fi
    if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]]; then
        if [[ -n "$REPLACE_UPSTREAM_DNS" ]]; then
            processed_line=$(replace_dns_in_upstream "$line" "$REPLACE_UPSTREAM_DNS")
            echo "$processed_line" >> "./custom.upstream.tmp"
        else
            echo "$line" >> "./custom.upstream.tmp"
        fi
        CUSTOM_DNS_COUNT=$((CUSTOM_DNS_COUNT + 1))
    fi
done < "./upstream.download.tmp"
log "Upstream file validation completed"
if [[ -n "$REPLACE_UPSTREAM_DNS" ]]; then
    log "Applied DNS server replacement: $REPLACE_UPSTREAM_DNS" debug
fi

log "Processing data format..."
cat "./default.upstream.tmp" "./custom.upstream.tmp" > "$OUTPUT_FILE"

log "Cleaning..."
rm -f ./*.upstream.tmp ./upstream.download.tmp

if [[ -n "$RESTART_SERVICE" ]]; then
    log "Restarting service: $RESTART_SERVICE"
    systemctl restart "$RESTART_SERVICE"
else
    log "No service restart requested"
fi

log "All finished!"

TOTAL_DNS_COUNT=$((DEFAULT_DNS_COUNT + CUSTOM_DNS_COUNT))
NOTIFICATION_MESSAGE="🎯 DNS Upstream Configuration Completed Successfully!

📊 Statistics:
Hostname: <code>$(hostname)</code>
Default upstream DNS count: ${DEFAULT_DNS_COUNT}
Upstream file DNS rules count: ${CUSTOM_DNS_COUNT}
Total DNS rules processed: ${TOTAL_DNS_COUNT}

📁 Output:
File: <code>${OUTPUT_FILE}</code>"

if [[ -n "$REPLACE_UPSTREAM_DNS" ]]; then
    NOTIFICATION_MESSAGE="${NOTIFICATION_MESSAGE}
Replacement DNS: <code>${REPLACE_UPSTREAM_DNS}</code>"
fi

if [[ -n "$RESTART_SERVICE" ]]; then
    NOTIFICATION_MESSAGE="${NOTIFICATION_MESSAGE}

🔄 Service Management:
Service restarted: <code>${RESTART_SERVICE}</code>"
else
    NOTIFICATION_MESSAGE="${NOTIFICATION_MESSAGE}

⚠️ Service Management:
No service restart requested"
fi

send_telegram_notification "$NOTIFICATION_MESSAGE"

unset IS_SYSTEMD
