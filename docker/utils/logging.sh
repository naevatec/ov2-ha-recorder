#!/bin/bash

# Shared logging library for OpenVidu HA Recorder scripts
# Usage: source /utils/logging.sh

# Default log file (can be overridden by setting LOG_FILE before sourcing)
LOG_FILE=${LOG_FILE:-"/var/log/openvidu-recorder.log"}

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null

# Main logging function
log() {
    local level="${2:-INFO}"
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local script_name=$(basename "${BASH_SOURCE[2]:-unknown}")
    
    echo "[$timestamp] [$level] [$script_name] $message" | tee -a "$LOG_FILE"
}

# Convenience functions for different log levels
log_info() {
    log "$1" "INFO"
}

log_warn() {
    log "$1" "WARN"
}

log_error() {
    log "$1" "ERROR"
}

log_debug() {
    if [[ "${DEBUG_MODE:-false}" == "true" ]]; then
        log "$1" "DEBUG"
    fi
}

log_success() {
    log "✅ $1" "SUCCESS"
}

log_failure() {
    log "❌ $1" "FAILURE"
}

# Function to set a specific log file for a script
set_log_file() {
    LOG_FILE="$1"
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
}

# Function to rotate log file if it gets too large
rotate_log_if_needed() {
    local max_lines=${1:-5000}
    
    if [[ -f "$LOG_FILE" ]] && [[ $(wc -l < "$LOG_FILE") -gt $max_lines ]]; then
        log_info "Rotating log file (exceeded $max_lines lines)"
        tail -$((max_lines / 2)) "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
        log_info "Log file rotated, kept last $((max_lines / 2)) lines"
    fi
}