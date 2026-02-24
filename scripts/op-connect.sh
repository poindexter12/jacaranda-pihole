#!/bin/bash
# op-connect.sh - 1Password Connect Server client with op:// URI support
#
# Usage: op-connect.sh read "op://Vault/Item/Field"
#
# Environment variables:
#   OP_CONNECT_TOKEN    - Bearer token for Connect Server (required)
#   OP_CONNECT_SERVERS  - Server URL (default: http://secrets-server:8080)
#   OP_CONNECT_TIMEOUT  - Request timeout in seconds (default: 5)
#   OP_CONNECT_CACHE    - Cache directory (default: /tmp/op-connect-cache)
#   OP_CONNECT_DEBUG    - Set to 1 for debug output
#
# Caches vault name→ID mappings to reduce API calls.

set -euo pipefail

# Configuration
: "${OP_CONNECT_SERVERS:=http://secrets-server:8080}"
: "${OP_CONNECT_TIMEOUT:=5}"
: "${OP_CONNECT_CACHE:=/tmp/op-connect-cache}"
: "${OP_CONNECT_DEBUG:=0}"

# Ensure cache directory exists
mkdir -p "$OP_CONNECT_CACHE"

debug() {
    if [[ "$OP_CONNECT_DEBUG" == "1" ]]; then
        echo "[DEBUG] $*" >&2
    fi
}

error() {
    echo "[ERROR] $*" >&2
    exit 1
}

# Check for required token
check_token() {
    if [[ -z "${OP_CONNECT_TOKEN:-}" ]]; then
        error "OP_CONNECT_TOKEN environment variable is required"
    fi
}

# Make API request with automatic failover
api_request() {
    local method="$1"
    local path="$2"
    local result=""
    local servers
    IFS=',' read -ra servers <<< "$OP_CONNECT_SERVERS"

    for server in "${servers[@]}"; do
        debug "Trying $server$path"
        if result=$(curl -sf \
            --max-time "$OP_CONNECT_TIMEOUT" \
            -H "Authorization: Bearer $OP_CONNECT_TOKEN" \
            -X "$method" \
            "${server}${path}" 2>/dev/null); then
            debug "Success from $server"
            echo "$result"
            return 0
        fi
        debug "Failed to connect to $server"
    done

    error "All Connect Server instances unreachable"
}

# Get vault ID from name (cached)
get_vault_id() {
    local vault_name="$1"
    local cache_file="$OP_CONNECT_CACHE/vault_${vault_name}.id"

    # Check cache (valid for 1 hour)
    if [[ -f "$cache_file" ]]; then
        local age=$(($(date +%s) - $(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null)))
        if [[ $age -lt 3600 ]]; then
            cat "$cache_file"
            return 0
        fi
    fi

    # Fetch from API
    local vaults
    vaults=$(api_request GET "/v1/vaults")

    local vault_id
    vault_id=$(echo "$vaults" | jq -r ".[] | select(.name == \"$vault_name\") | .id")

    if [[ -z "$vault_id" || "$vault_id" == "null" ]]; then
        error "Vault '$vault_name' not found"
    fi

    # Cache the result
    echo "$vault_id" > "$cache_file"
    echo "$vault_id"
}

# Get item ID from title (not cached - items change more frequently)
get_item_id() {
    local vault_id="$1"
    local item_title="$2"

    # URL encode the title
    local encoded_title
    encoded_title=$(printf '%s' "$item_title" | jq -sRr @uri)

    local items
    items=$(api_request GET "/v1/vaults/${vault_id}/items?filter=title+eq+%22${encoded_title}%22")

    local item_id
    item_id=$(echo "$items" | jq -r '.[0].id')

    if [[ -z "$item_id" || "$item_id" == "null" ]]; then
        error "Item '$item_title' not found in vault"
    fi

    echo "$item_id"
}

# Get field value from item
get_field_value() {
    local vault_id="$1"
    local item_id="$2"
    local field_name="$3"

    local item
    item=$(api_request GET "/v1/vaults/${vault_id}/items/${item_id}")

    # Try to match by label first, then by id
    local value
    value=$(echo "$item" | jq -r ".fields[] | select(.label == \"$field_name\" or .id == \"$field_name\") | .value" | head -1)

    if [[ -z "$value" || "$value" == "null" ]]; then
        error "Field '$field_name' not found in item"
    fi

    echo "$value"
}

# Parse op:// URI
# Format: op://Vault/Item/Field or op://Vault/Item/Section/Field
parse_op_uri() {
    local uri="$1"

    if [[ ! "$uri" =~ ^op:// ]]; then
        error "Invalid URI format. Expected op://Vault/Item/Field"
    fi

    # Remove op:// prefix
    local path="${uri#op://}"

    # Split by /
    IFS='/' read -ra parts <<< "$path"

    if [[ ${#parts[@]} -lt 3 ]]; then
        error "Invalid URI format. Expected op://Vault/Item/Field (got $uri)"
    fi

    local vault="${parts[0]}"
    local item="${parts[1]}"
    local field="${parts[2]}"

    # If there are 4 parts, the 3rd is section and 4th is field
    if [[ ${#parts[@]} -eq 4 ]]; then
        field="${parts[3]}"
    fi

    echo "$vault"
    echo "$item"
    echo "$field"
}

# Main read function
cmd_read() {
    local uri="$1"

    check_token

    # Parse URI (portable - no mapfile)
    local parsed
    parsed=$(parse_op_uri "$uri")

    local vault item field
    vault=$(echo "$parsed" | sed -n '1p')
    item=$(echo "$parsed" | sed -n '2p')
    field=$(echo "$parsed" | sed -n '3p')

    debug "Vault: $vault, Item: $item, Field: $field"

    # Resolve vault ID
    local vault_id
    vault_id=$(get_vault_id "$vault")
    debug "Vault ID: $vault_id"

    # Resolve item ID
    local item_id
    item_id=$(get_item_id "$vault_id" "$item")
    debug "Item ID: $item_id"

    # Get field value
    get_field_value "$vault_id" "$item_id" "$field"
}

# Show usage
usage() {
    cat <<EOF
op-connect.sh - 1Password Connect Server client

Usage:
    op-connect.sh read "op://Vault/Item/Field"

Commands:
    read URI    Read a secret value from the given op:// URI

Environment Variables:
    OP_CONNECT_TOKEN    Bearer token for Connect Server (required)
    OP_CONNECT_SERVERS  Server URL (default: http://secrets-server:8080)
    OP_CONNECT_TIMEOUT  Request timeout in seconds (default: 5)
    OP_CONNECT_CACHE    Cache directory (default: /tmp/op-connect-cache)
    OP_CONNECT_DEBUG    Set to 1 for debug output

Examples:
    # Read a password
    export OP_CONNECT_TOKEN="eyJhbG..."
    op-connect.sh read "op://Homelab/opentofu/password"

    # Read with debug output
    OP_CONNECT_DEBUG=1 op-connect.sh read "op://Homelab/pihole-prod/webpassword"
EOF
}

# Main entrypoint
main() {
    if [[ $# -lt 1 ]]; then
        usage
        exit 1
    fi

    local cmd="$1"
    shift

    case "$cmd" in
        read)
            if [[ $# -lt 1 ]]; then
                error "Usage: op-connect.sh read \"op://Vault/Item/Field\""
            fi
            cmd_read "$1"
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            error "Unknown command: $cmd"
            ;;
    esac
}

main "$@"
