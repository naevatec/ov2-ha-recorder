#!/bin/bash

# Robust inotify-based chunk uploader with retry and failure handling
# Prioritizes recording safety - separate process that never affects FFmpeg

# Load shared logging library
LOG_FILE="/var/log/chunk-uploader-${1:-${VIDEO_ID:-video}}.log"
source /usr/local/bin/logging.sh

VIDEO_ID=${1:-${VIDEO_ID:-video}}
CHUNK_DIR="/recordings/$VIDEO_ID${CHUNK_FOLDER:-/chunks}"
FAILED_DIR="/tmp/failed-uploads-${VIDEO_ID}"
STATE_FILE="/tmp/upload-state-${VIDEO_ID}.txt"

# S3 Configuration - works with AWS S3, MinIO, or any S3-compatible service
S3_BUCKET=${HA_AWS_S3_BUCKET:-ov-recordings}
S3_ENDPOINT=${HA_AWS_S3_SERVICE_ENDPOINT}

export AWS_ACCESS_KEY_ID=${HA_AWS_ACCESS_KEY}
export AWS_SECRET_ACCESS_KEY=${HA_AWS_SECRET_KEY}

# Build AWS command with timeout for any S3-compatible service
AWS_CMD="timeout 30 aws s3 cp"
[ -n "$S3_ENDPOINT" ] && AWS_CMD="$AWS_CMD --endpoint-url $S3_ENDPOINT"

# Initialize directories and files
mkdir -p "$CHUNK_DIR" "$FAILED_DIR"
touch "$STATE_FILE"

log_info "🚀 Starting chunk uploader for VIDEO_ID: $VIDEO_ID"
log_info "📁 Monitoring directory: $CHUNK_DIR"
log_info "☁️  S3 Bucket: $S3_BUCKET"
log_info "🔗 S3 Endpoint: ${S3_ENDPOINT:-default AWS}"
log_info "📂 Chunk folder: ${CHUNK_FOLDER:-/chunks}"

# Upload function with retry logic and cleanup
upload_chunk() {
    local chunk_file="$1"
    local filename=$(basename "$chunk_file")
    local s3_path="s3://$S3_BUCKET/$VIDEO_ID/chunks/$filename"
    local failed_marker="$FAILED_DIR/$filename"
    
    # Skip if already uploaded successfully
    if grep -q "^SUCCESS:$filename$" "$STATE_FILE" 2>/dev/null; then
        return 0
    fi
    
    # Check if file exists and is stable (not being written by FFmpeg)
    if [ ! -f "$chunk_file" ]; then
        log_warn "File not found: $filename"
        return 1
    fi
    
    local size1=$(stat -c%s "$chunk_file" 2>/dev/null || echo 0)
    sleep 2  # Wait for FFmpeg to finish writing
    local size2=$(stat -c%s "$chunk_file" 2>/dev/null || echo 0)
    
    # Ensure file is stable and has minimum size
    if [ "$size1" != "$size2" ]; then
        log_info "⏳ $filename still being written (size: $size1 -> $size2), will retry later"
        return 1
    fi
    
    if [ "$size2" -lt 1024 ]; then
        log_warn "$filename too small ($size2 bytes), skipping"
        return 1
    fi
    
    # Retry logic: 3 attempts with exponential backoff
    local attempt=1
    local max_attempts=3
    
    while [ $attempt -le $max_attempts ]; do
        log_info "📤 Uploading $filename (attempt $attempt/$max_attempts, ${size2} bytes)"
        
        # Upload with timeout (works with AWS S3, MinIO, and other S3-compatible services)
        if $AWS_CMD "$chunk_file" "$s3_path" 2>&1 | tee -a "$LOG_FILE"; then
            # Success - mark as uploaded and clean up local chunk
            echo "SUCCESS:$filename" >> "$STATE_FILE"
            rm -f "$failed_marker"
            
            # Clean up local chunk file after successful upload
            if rm -f "$chunk_file"; then
                log_success "Successfully uploaded and cleaned: $filename"
            else
                log_success "Successfully uploaded: $filename (cleanup failed)"
            fi
            return 0
        else
            log_error "Upload failed (attempt $attempt): $filename"
            
            if [ $attempt -eq $max_attempts ]; then
                # Final failure - mark for manual retry later
                echo "FAILED:$filename:$(date +%s)" >> "$STATE_FILE"
                touch "$failed_marker"
                log_failure "FINAL FAILURE: $filename (marked for retry, chunk preserved)"
                return 1
            fi
            
            # Wait before retry (exponential backoff)
            local wait_time=$((attempt * 3))
            log_info "⏸️  Waiting ${wait_time}s before retry..."
            sleep $wait_time
            ((attempt++))
        fi
    done
}

# Retry failed uploads periodically
retry_failed_uploads() {
    if [ ! -d "$FAILED_DIR" ] || [ -z "$(ls -A "$FAILED_DIR" 2>/dev/null)" ]; then
        return
    fi
    
    # Retry files that failed more than 2 minutes ago
    find "$FAILED_DIR" -name "*.mp4" -mmin +2 2>/dev/null | while read failed_marker; do
        local filename=$(basename "$failed_marker")
        local chunk_file="$CHUNK_DIR/$filename"
        
        if [ -f "$chunk_file" ]; then
            log "🔄 Retrying failed upload: $filename"
            # Remove from failed state to allow retry
            sed -i "/FAILED:$filename:/d" "$STATE_FILE" 2>/dev/null
            upload_chunk "$chunk_file"
        else
            # Original file no longer exists, clean up markers
            rm -f "$failed_marker"
            sed -i "/FAILED:$filename:/d" "$STATE_FILE" 2>/dev/null
            log "🧹 Cleaned up marker for missing file: $filename"
        fi
    done
}

# Background retry daemon
retry_daemon() {
    while true; do
        sleep 120  # Check for retries every 2 minutes
        retry_failed_uploads
    done
}

# Start retry daemon in background
retry_daemon &
RETRY_PID=$!

# Cleanup function
cleanup() {
    log "🧹 Cleaning up chunk uploader..."
    
    # Stop retry daemon
    if [ -n "$RETRY_PID" ]; then
        kill $RETRY_PID 2>/dev/null
        wait $RETRY_PID 2>/dev/null
    fi
    
    # Final upload attempt for any remaining chunks
    log "📤 Final upload attempt for remaining chunks..."
    if [ -d "$CHUNK_DIR" ]; then
        find "$CHUNK_DIR" -name "*.mp4" 2>/dev/null | while read chunk_file; do
            if [ -f "$chunk_file" ]; then
                upload_chunk "$chunk_file"
            fi
        done
    fi
    
    # Report final status
    local success_count=$(grep -c "^SUCCESS:" "$STATE_FILE" 2>/dev/null || echo 0)
    local failed_count=$(grep -c "^FAILED:" "$STATE_FILE" 2>/dev/null || echo 0)
    log "📊 Final upload status: $success_count uploaded, $failed_count failed"
    
    if [ "${failed_count:-0}" -gt 0 ]; then
        log "🔴 Failed uploads logged in: $STATE_FILE"
        log "🔴 Failed chunk markers in: $FAILED_DIR"
        log "💡 Failed chunks preserved for manual recovery"
    fi
    
    # Clean up successful uploads from state tracking
    if [ "${failed_count:-0}" -eq 0 ]; then
        rm -f "$STATE_FILE" "$FAILED_DIR"/*.mp4 2>/dev/null
        log "✅ All chunks uploaded successfully, cleanup completed"
    fi
    
    log "🏁 Chunk uploader terminated"
}

# Set up cleanup trap
trap cleanup EXIT INT TERM

# Main inotify monitoring loop
log "👀 Starting inotify monitoring on $CHUNK_DIR..."

# Create directory if it doesn't exist for inotify
mkdir -p "$CHUNK_DIR"

# Monitor for new .mp4 files with inotify
inotifywait -m -e close_write -e moved_to --format '%f' "$CHUNK_DIR" 2>/dev/null | while read filename; do
    if [[ "$filename" == *.mp4 ]]; then
        chunk_file="$CHUNK_DIR/$filename"
        log "📄 New chunk detected: $filename"
        
        # Upload in background to avoid blocking inotify
        upload_chunk "$chunk_file" &
    fi
done

# If we reach here, inotify failed
log "❌ inotify monitoring stopped unexpectedly"
exit 1