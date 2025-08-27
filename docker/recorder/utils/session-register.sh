#!/bin/bash

# Enhanced Session Registration Script
# Registers a recording session with the HA Controller using environment variables

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

# Create JSON with all environment variables
create_environment_json() {
    jq -n \
        --arg DEBUG_MODE "${DEBUG_MODE:-false}" \
        --arg CONTAINER_WORKING_MODE "${CONTAINER_WORKING_MODE:-recording}" \
        --arg URL "${URL:-}" \
        --arg ONLY_VIDEO "${ONLY_VIDEO:-false}" \
        --arg RESOLUTION "${RESOLUTION:-1280x720}" \
        --arg FRAMERATE "${FRAMERATE:-25}" \
        --arg VIDEO_ID "${VIDEO_ID:-}" \
        --arg VIDEO_NAME "${VIDEO_NAME:-}" \
        --arg VIDEO_FORMAT "${VIDEO_FORMAT:-mp4}" \
        --arg RECORDING_JSON "${RECORDING_JSON:-}" \
        --arg CHUNK_RECORDING_TYPE "${CHUNK_RECORDING_TYPE:-local}" \
        --arg CHUNK_FOLDER "${CHUNK_FOLDER:-chunks}" \
        --arg CHUNK_START "${CHUNK_START:-0000}" \
        --arg CHUNK_TIME_SIZE "${CHUNK_TIME_SIZE:-10}" \
        --arg IS_RECOVERY_CONTAINER "${IS_RECOVERY_CONTAINER:-false}" \
        --arg HOSTNAME "$(hostname 2>/dev/null || echo "unknown")" \
        --arg CONTAINER_IP "$(hostname -i 2>/dev/null || echo "unknown")" \
        '{
            debugMode: $DEBUG_MODE,
            containerWorkingMode: $CONTAINER_WORKING_MODE,
            url: $URL,
            onlyVideo: $ONLY_VIDEO,
            resolution: $RESOLUTION,
            framerate: $FRAMERATE,
            videoId: $VIDEO_ID,
            videoName: $VIDEO_NAME,
            videoFormat: $VIDEO_FORMAT,
            recordingJson: $RECORDING_JSON,
            chunkRecordingType: $CHUNK_RECORDING_TYPE,
            chunkFolder: $CHUNK_FOLDER,
            chunkStart: $CHUNK_START,
            chunkTimeSize: $CHUNK_TIME_SIZE,
            isRecoveryContainer: $IS_RECOVERY_CONTAINER,
            hostname: $HOSTNAME,
            containerIp: $CONTAINER_IP,
            timestamp: (now | tostring)
        }'
}

# Enhanced session registration
register_session() {
    log "Registering session from: $JSON_FILE"

    # Check if file exists
    if [[ ! -f "$JSON_FILE" ]]; then
        error_exit "JSON file not found: $JSON_FILE"
    fi

    # Parse basic info from JSON file
    local session_id unique_session_id status recording_json_from_file
    session_id=$(jq -r '.sessionId // .id // empty' "$JSON_FILE" 2>/dev/null || echo "")
    unique_session_id=$(jq -r '.uniqueSessionId // .sessionId // .id // empty' "$JSON_FILE" 2>/dev/null || echo "")
    status=$(jq -r '.status // "started"' "$JSON_FILE" 2>/dev/null || echo "started")
    recording_json_from_file=$(jq -c . "$JSON_FILE" 2>/dev/null || echo "{}")

    # Use VIDEO_ID as primary sessionId, fallback to unique_session_id
    local primary_session_id
    if [[ -n "${VIDEO_ID:-}" ]]; then
        primary_session_id="$VIDEO_ID"
        log "Using VIDEO_ID as sessionId: $primary_session_id"
    elif [[ -n "$unique_session_id" ]]; then
        primary_session_id="$unique_session_id"
        log "Using unique_session_id as sessionId: $primary_session_id"
    elif [[ -n "$session_id" ]]; then
        primary_session_id="$session_id"
        log "Using session_id as sessionId: $primary_session_id"
    else
        error_exit "Could not determine sessionId - VIDEO_ID, uniqueSessionId, or sessionId required"
    fi

    # Get client info
    local client_host client_id
    client_host=$(hostname -i 2>/dev/null || echo "recorder-container")
    client_id="recorder-$(hostname 2>/dev/null || echo "unknown")"

    # Create environment variables JSON
    local environment_json
    environment_json=$(create_environment_json)

    log "Session: $primary_session_id"
    log "Client: $client_id @ $client_host"
    log "Status: $status"
    log "Environment variables captured"

    # Prepare session data with enhanced structure
    local session_data
    session_data=$(jq -n \
        --arg sessionId "$primary_session_id" \
        --arg clientId "$client_id" \
        --arg clientHost "$client_host" \
        --arg uniqueSessionId "$unique_session_id" \
        --arg originalSessionId "$session_id" \
        --arg status "$status" \
        --argjson recordingJson "$recording_json_from_file" \
        --argjson environment "$environment_json" \
        '{
            sessionId: $sessionId,
            clientId: $clientId,
            clientHost: $clientHost,
            uniqueSessionId: $uniqueSessionId,
            originalSessionId: $originalSessionId,
            status: $status,
            recordingJson: $recordingJson,
            environment: $environment,
            metadata: {
                recording: $recordingJson,
                environment: $environment,
                registrationTimestamp: (now | tostring)
            }
        }')

    # Register session
    if api_call "POST" "" "$session_data"; then
        log "Session registered successfully"
        log "Session ID: $primary_session_id"
        log "Environment variables stored in Redis"
        return 0
    else
        error_exit "Failed to register session"
    fi
}

# Main execution
main() {
    log "Starting enhanced session registration"
    log "Controller: ${HA_CONTROLLER_HOST}:${HA_CONTROLLER_PORT}"
    log "JSON file: $JSON_FILE"
    log "VIDEO_ID: ${VIDEO_ID:-'not set'}"

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
