#!/bin/bash

# Recorder Session Manager Script
# Manages heartbeat for recording sessions with the HA Controller

set -euo pipefail

# Configuration
SCRIPT_NAME="$(basename "$0")"
LOG_PREFIX="[${SCRIPT_NAME}]"
DEFAULT_CONTROLLER_HOST="ov-recorder"
DEFAULT_CONTROLLER_PORT="8080"
DEFAULT_HEARTBEAT_INTERVAL=30
DEFAULT_JSON_FILE="/tmp/recording_info.json"

# Environment variables
CONTROLLER_HOST="${CONTROLLER_HOST:-$DEFAULT_CONTROLLER_HOST}"
CONTROLLER_PORT="${CONTROLLER_PORT:-$DEFAULT_CONTROLLER_PORT}"
CONTROLLER_USER="${APP_SECURITY_USERNAME:-recorder}"
CONTROLLER_PASSWORD="${APP_SECURITY_PASSWORD:-rec0rd3r_2024!}"
HEARTBEAT_INTERVAL="${HEARTBEAT_INTERVAL:-$DEFAULT_HEARTBEAT_INTERVAL}"
JSON_FILE="${1:-$DEFAULT_JSON_FILE}"
CHUNK_RECORDING_DIR="${2:-${CHUNK_RECORDING_DIR:-}}"

# API Base URL
API_BASE="http://${CONTROLLER_HOST}:${CONTROLLER_PORT}/api/sessions"

# Global variables
UNIQUE_SESSION_ID=""
LAST_CHUNK_SENT=""

# Logging function
log() {
    echo "${LOG_PREFIX} $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
}

# Error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Parse recording information from JSON
parse_recording_info() {
    local json_file="$1"
    
    if [[ ! -f "$json_file" ]]; then
        error_exit "JSON file not found: $json_file"
    fi
    
    UNIQUE_SESSION_ID=$(jq -r '.uniqueSessionId // .sessionId // .id // empty' "$json_file" 2>/dev/null || echo "")
    
    if [[ -z "$UNIQUE_SESSION_ID" ]]; then
        error_exit "Could not extract session ID from JSON file"
    fi
    
    log "Managing session: $UNIQUE_SESSION_ID"
}

# Get the last chunk file created
get_last_chunk() {
    if [[ -n "$CHUNK_RECORDING_DIR" && -d "$CHUNK_RECORDING_DIR" ]]; then
        # Find the most recently created .mp4 file
        local last_chunk
        last_chunk=$(find "$CHUNK_RECORDING_DIR" -name "*.mp4" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
        
        if [[ -n "$last_chunk" ]]; then
            # Extract just the filename
            basename "$last_chunk"
        else
            echo ""
        fi
    else
        echo ""
    fi
}

# Send heartbeat with last chunk info
send_heartbeat() {
    local current_chunk
    current_chunk=$(get_last_chunk)
    
    # Prepare heartbeat data
    local heartbeat_data="{}"
    
    # Add chunk information if available and different from last sent
    if [[ -n "$current_chunk" && "$current_chunk" != "$LAST_CHUNK_SENT" ]]; then
        heartbeat_data=$(jq -n \
            --arg lastChunk "$current_chunk" \
            '{lastChunk: $lastChunk}')
        LAST_CHUNK_SENT="$current_chunk"
        log "Sending heartbeat with new chunk: $current_chunk"
    else
        log "Sending heartbeat (no new chunks)"
    fi
    
    local response
    response=$(curl -s -w "%{http_code}" \
        -X PUT \
        -u "${CONTROLLER_USER}:${CONTROLLER_PASSWORD}" \
        -H "Content-Type: application/json" \
        -H "User-Agent: recorder-session-manager/1.0" \
        -d "$heartbeat_data" \
        "${API_BASE}/${UNIQUE_SESSION_ID}/heartbeat" 2>/dev/null || echo "000")
    
    local http_code="${response: -3}"
    
    if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
        if [[ -n "$current_chunk" && "$current_chunk" != "${LAST_CHUNK_SENT:-}" ]]; then
            log "Heartbeat sent successfully with chunk info"
        else
            log "Heartbeat sent successfully"
        fi
        return 0
    else
        log "Heartbeat failed (HTTP $http_code)"
        return 1
    fi
}

# Main heartbeat loop
heartbeat_loop() {
    log "Starting heartbeat loop (interval: ${HEARTBEAT_INTERVAL}s)"
    
    while true; do
        if send_heartbeat; then
            log "Heartbeat sent, sleeping for ${HEARTBEAT_INTERVAL}s"
        else
            log "Heartbeat failed, will retry in ${HEARTBEAT_INTERVAL}s"
        fi
        
        sleep "$HEARTBEAT_INTERVAL"
    done
}

# Cleanup function - fast unregistration
cleanup() {
    log "Script terminating, unregistering session..."
    if [[ -n "${UNIQUE_SESSION_ID}" ]]; then
        # Quick DELETE call instead of status update
        timeout 5 curl -s \
            -u "${CONTROLLER_USER}:${CONTROLLER_PASSWORD}" \
            -X DELETE \
            "${API_BASE}/${UNIQUE_SESSION_ID}" \
            >/dev/null 2>&1 || true
        log "Session unregistered"
    fi
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT

# Main execution
main() {
    log "Starting Recorder Session Manager"
    log "Controller: ${CONTROLLER_HOST}:${CONTROLLER_PORT}"
    log "JSON file: $JSON_FILE"
    log "Chunk directory: ${CHUNK_RECORDING_DIR:-'not specified'}"
    log "Heartbeat interval: ${HEARTBEAT_INTERVAL}s"
    
    # Parse JSON file
    parse_recording_info "$JSON_FILE"
    
    # Start heartbeat loop
    heartbeat_loop
}

# Run main function
main "$@"