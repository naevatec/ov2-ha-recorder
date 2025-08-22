#!/bin/bash

# Simple Session Registration Script
# Registers a recording session with the HA Controller and exits

set -euo pipefail

# Configuration
SCRIPT_NAME="$(basename "$0")"
LOG_PREFIX="[${SCRIPT_NAME}]"
DEFAULT_CONTROLLER_HOST="ov-recorder"
DEFAULT_CONTROLLER_PORT="8080"
DEFAULT_JSON_FILE="/tmp/recording_info.json"

# Environment variables
HA_CONTROLLER_HOST="${HA_CONTROLLER_HOST:-$DEFAULT_CONTROLLER_HOST}"
HA_CONTROLLER_PORT="${HA_CONTROLLER_PORT:-$DEFAULT_CONTROLLER_PORT}"
CONTROLLER_USER="${HA_CONTROLLER_USERNAME:-recorder}"
CONTROLLER_PASSWORD="${HA_CONTROLLER_PASSWORD:-rec0rd3r_2024!}"
JSON_FILE="${1:-$DEFAULT_JSON_FILE}"

# API Base URL
API_BASE="http://${HA_CONTROLLER_HOST}:${HA_CONTROLLER_PORT}/api/sessions"

# Logging function
log() {
    echo "${LOG_PREFIX} $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
}

# Error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Make authenticated API call
api_call() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    
    local url="${API_BASE}${endpoint}"
    
    local response
    response=$(curl -s -w "%{http_code}" \
        -X "$method" \
        -u "${CONTROLLER_USER}:${CONTROLLER_PASSWORD}" \
        -H "Content-Type: application/json" \
        -H "User-Agent: session-register/1.0" \
        ${data:+-d "$data"} \
        "$url" 2>/dev/null || echo "000")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
        log "API call successful: $method $endpoint (HTTP $http_code)"
        echo "$body"
        return 0
    else
        log "API call failed: $method $endpoint (HTTP $http_code)"
        if [[ -n "$body" ]]; then
            log "Response: $body"
        fi
        return 1
    fi
}

# Quick session registration
register_session() {
    log "Registering session from: $JSON_FILE"
    
    # Check if file exists
    if [[ ! -f "$JSON_FILE" ]]; then
        error_exit "JSON file not found: $JSON_FILE"
    fi
    
    # Parse basic info
    local session_id unique_session_id status
    session_id=$(jq -r '.sessionId // .id // empty' "$JSON_FILE" 2>/dev/null || echo "")
    unique_session_id=$(jq -r '.uniqueSessionId // .sessionId // .id // empty' "$JSON_FILE" 2>/dev/null || echo "")
    status=$(jq -r '.status // "started"' "$JSON_FILE" 2>/dev/null || echo "started")
    
    if [[ -z "$session_id" ]]; then
        error_exit "Could not extract sessionId from JSON file"
    fi
    
    if [[ -z "$unique_session_id" ]]; then
        unique_session_id="$session_id"
    fi
    
    # Get client info
    local client_host client_id
    client_host=$(hostname -i 2>/dev/null || echo "recorder-container")
    client_id="recorder-$(hostname 2>/dev/null || echo "unknown")"
    
    log "Session: $unique_session_id"
    log "Client: $client_id @ $client_host"
    log "Status: $status"
    
    # Prepare session data
    local session_data
    session_data=$(jq -n \
        --arg sessionId "$unique_session_id" \
        --arg clientId "$client_id" \
        --arg clientHost "$client_host" \
        --arg metadata "$(jq -c . "$JSON_FILE")" \
        '{
            sessionId: $sessionId,
            clientId: $clientId,
            clientHost: $clientHost,
            metadata: $metadata
        }')
    
    # Register session
    if api_call "POST" "" "$session_data"; then
        log "Session registered successfully"
        log "Session registration completed successfully"
        return 0
    else
        error_exit "Failed to register session"
    fi
}

# Main execution
main() {
    log "Starting session registration"
    log "Controller: ${HA_CONTROLLER_HOST}:${HA_CONTROLLER_PORT}"
    log "JSON file: $JSON_FILE"
    
    # Check dependencies
    if ! command -v jq >/dev/null 2>&1; then
        error_exit "jq is required but not installed"
    fi
    
    if ! command -v curl >/dev/null 2>&1; then
        error_exit "curl is required but not installed"
    fi
    
    # Register session
    register_session
    
    log "Session registration script completed"
}

# Run main function
main "$@"
