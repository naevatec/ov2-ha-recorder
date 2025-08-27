#!/bin/bash

# Robust S3 chunk downloader with retry and verification
# Downloads all uploaded chunks from S3 back to local directory

# Load shared logging library
LOG_FILE="/var/log/chunk-downloader-${1:-${VIDEO_ID:-video}}.log"
source /usr/local/bin/logging.sh

VIDEO_ID=${1:-${VIDEO_ID:-video}}
LOCAL_CHUNK_DIR=${2:-"/recordings/$VIDEO_ID${CHUNK_FOLDER:-/chunks}"}
STATE_FILE="/tmp/download-state-${VIDEO_ID}.txt"

# S3 Configuration - works with AWS S3, MinIO, or any S3-compatible service
S3_BUCKET=${HA_AWS_S3_BUCKET:-ov-recordings}
S3_ENDPOINT=${HA_AWS_S3_SERVICE_ENDPOINT}

export AWS_ACCESS_KEY_ID=${HA_AWS_ACCESS_KEY}
export AWS_SECRET_ACCESS_KEY=${HA_AWS_SECRET_KEY}

# Build AWS command with timeout for any S3-compatible service
AWS_CMD="timeout 60 aws s3 cp"
AWS_LIST_CMD="timeout 30 aws s3 ls"
[ -n "$S3_ENDPOINT" ] && AWS_CMD="$AWS_CMD --endpoint-url $S3_ENDPOINT"
[ -n "$S3_ENDPOINT" ] && AWS_LIST_CMD="$AWS_LIST_CMD --endpoint-url $S3_ENDPOINT"

# Initialize directories and files
mkdir -p "$LOCAL_CHUNK_DIR"
touch "$STATE_FILE"

log_info "📥 Starting chunk downloader for VIDEO_ID: $VIDEO_ID"
log_info "📂 Local directory: $LOCAL_CHUNK_DIR"
log_info "☁️  S3 Bucket: $S3_BUCKET"
log_info "🔗 S3 Endpoint: ${S3_ENDPOINT:-default AWS}"

# S3 paths
S3_CHUNKS_PATH="s3://$S3_BUCKET/$VIDEO_ID/chunks/"

# Function to list available chunks in S3
list_s3_chunks() {
    log_info "📋 Listing available chunks in S3..."
    
    # List all .mp4 files in the S3 chunks directory
    local s3_files
    if s3_files=$($AWS_LIST_CMD "$S3_CHUNKS_PATH" 2>/dev/null | grep "\.mp4$" | awk '{print $4}'); then
        if [ -n "$s3_files" ]; then
            local chunk_count=$(echo "$s3_files" | wc -l)
            log_info "📊 Found $chunk_count chunks in S3:"
            echo "$s3_files" | while read filename; do
                log_info "  - $filename"
            done
            echo "$s3_files"
            return 0
        else
            log_warn "No .mp4 chunks found in S3"
            return 1
        fi
    else
        log_error "Failed to list S3 chunks"
        return 1
    fi
}

# Function to download a single chunk with retry logic
download_chunk() {
    local filename="$1"
    local s3_path="$S3_CHUNKS_PATH$filename"
    local local_path="$LOCAL_CHUNK_DIR/$filename"
    
    # Skip if already downloaded successfully
    if grep -q "^SUCCESS:$filename$" "$STATE_FILE" 2>/dev/null; then
        log_info "✅ $filename already downloaded, skipping"
        return 0
    fi
    
    # Check if file already exists locally with reasonable size
    if [ -f "$local_path" ]; then
        local local_size=$(stat -c%s "$local_path" 2>/dev/null || echo 0)
        if [ "$local_size" -gt 1024 ]; then
            log_info "✅ $filename already exists locally (${local_size} bytes), marking as downloaded"
            echo "SUCCESS:$filename" >> "$STATE_FILE"
            return 0
        fi
    fi
    
    # Retry logic: 3 attempts with exponential backoff
    local attempt=1
    local max_attempts=3
    
    while [ $attempt -le $max_attempts ]; do
        log_info "📥 Downloading $filename (attempt $attempt/$max_attempts)"
        
        # Download with timeout
        if $AWS_CMD "$s3_path" "$local_path" 2>&1 | tee -a "$LOG_FILE"; then
            # Verify download success
            if [ -f "$local_path" ]; then
                local downloaded_size=$(stat -c%s "$local_path" 2>/dev/null || echo 0)
                if [ "$downloaded_size" -gt 1024 ]; then
                    # Success - mark as downloaded
                    echo "SUCCESS:$filename" >> "$STATE_FILE"
                    log_success "Successfully downloaded: $filename (${downloaded_size} bytes)"
                    return 0
                else
                    log_error "Downloaded file too small: $filename (${downloaded_size} bytes)"
                    rm -f "$local_path"
                fi
            else
                log_error "Downloaded file not found: $filename"
            fi
        else
            log_error "Download failed (attempt $attempt): $filename"
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            # Final failure
            echo "FAILED:$filename:$(date +%s)" >> "$STATE_FILE"
            log_failure "FINAL FAILURE: $filename (all attempts exhausted)"
            return 1
        fi
        
        # Wait before retry (exponential backoff)
        local wait_time=$((attempt * 5))
        log_info "⏸️  Waiting ${wait_time}s before retry..."
        sleep $wait_time
        ((attempt++))
    done
}

# Function to download all chunks using recursive copy (faster for many files)
download_all_chunks_bulk() {
    log_info "📦 Attempting bulk download of all chunks..."
    
    # Build AWS download command for recursive copy
    local aws_download_cmd="timeout 300 aws s3 cp --recursive"
    [ -n "$S3_ENDPOINT" ] && aws_download_cmd="$aws_download_cmd --endpoint-url $S3_ENDPOINT"
    
    # Download all chunks from S3 back to local directory
    if $aws_download_cmd "$S3_CHUNKS_PATH" "$LOCAL_CHUNK_DIR/" 2>&1 | tee -a "$LOG_FILE"; then
        # Verify downloaded chunks
        local downloaded_count=$(find "$LOCAL_CHUNK_DIR" -name "*.mp4" -type f | wc -l)
        if [ "$downloaded_count" -gt 0 ]; then
            log_success "Bulk download completed: $downloaded_count chunks"
            
            # Mark all downloaded files as successful
            find "$LOCAL_CHUNK_DIR" -name "*.mp4" -type f | while read chunk_file; do
                local filename=$(basename "$chunk_file")
                if ! grep -q "^SUCCESS:$filename$" "$STATE_FILE" 2>/dev/null; then
                    echo "SUCCESS:$filename" >> "$STATE_FILE"
                fi
            done
            
            return 0
        else
            log_error "Bulk download completed but no chunks found locally"
            return 1
        fi
    else
        log_error "Bulk download failed"
        return 1
    fi
}

# Function to download chunks individually (fallback method)
download_chunks_individually() {
    local s3_chunks="$1"
    local total_chunks=$(echo "$s3_chunks" | wc -l)
    local downloaded=0
    local failed=0
    
    log_info "📥 Downloading $total_chunks chunks individually..."
    
    echo "$s3_chunks" | while read filename; do
        if [ -n "$filename" ]; then
            if download_chunk "$filename"; then
                ((downloaded++))
            else
                ((failed++))
            fi
        fi
    done
    
    # Wait for all background downloads to complete
    wait
    
    # Count actual results from state file
    local success_count=$(grep -c "^SUCCESS:" "$STATE_FILE" 2>/dev/null | head -1 | tr -d '\n' || echo 0)
    local failed_count=$(grep -c "^FAILED:" "$STATE_FILE" 2>/dev/null | head -1 | tr -d '\n' || echo 0)
    
    log_info "📊 Individual download results: $success_count successful, $failed_count failed"
    
    if [ "$failed_count" -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Function to verify all downloads are complete
verify_downloads() {
    log_info "🔍 Verifying downloaded chunks..."
    
    local local_chunks=$(find "$LOCAL_CHUNK_DIR" -name "*.mp4" -type f | wc -l | tr -d '\n')
    local success_count=$(grep -c "^SUCCESS:" "$STATE_FILE" 2>/dev/null | head -1 | tr -d '\n' || echo 0)
    local failed_count=$(grep -c "^FAILED:" "$STATE_FILE" 2>/dev/null | head -1 | tr -d '\n' || echo 0)
    
    log_info "📊 Verification results:"
    log_info "  - Local chunks found: $local_chunks"
    log_info "  - Successful downloads: $success_count" 
    log_info "  - Failed downloads: $failed_count"
    
    if [ "$local_chunks" -eq "$success_count" ] && [ "$failed_count" -eq 0 ]; then
        log_success "All chunks verified successfully"
        return 0
    else
        if [ "$failed_count" -gt 0 ]; then
            log_warn "Some chunks failed to download"
        fi
        if [ "$local_chunks" -ne "$success_count" ]; then
            log_warn "Mismatch between local chunks and recorded successes"
        fi
        return 1
    fi
}

# Main download function
download_all_chunks() {
    log_info "🚀 Starting chunk download process..."
    
    # First, try to list available chunks in S3
    local s3_chunks
    if ! s3_chunks=$(list_s3_chunks); then
        log_error "Cannot proceed without S3 chunk list"
        return 1
    fi
    
    # Check if we have any chunks to download
    if [ -z "$s3_chunks" ]; then
        log_warn "No chunks found in S3 to download"
        return 1
    fi
    
    # Method 1: Try bulk download first (faster for many files)
    log_info "📦 Attempting bulk download method..."
    if download_all_chunks_bulk; then
        log_success "Bulk download method succeeded"
    else
        log_warn "Bulk download failed, falling back to individual downloads"
        
        # Method 2: Download chunks individually
        if download_chunks_individually "$s3_chunks"; then
            log_success "Individual download method succeeded"
        else
            log_error "Individual download method failed"
        fi
    fi
    
    # Verify final results
    verify_downloads
    local verify_result=$?
    
    # Report upload status from uploader if available
    if [[ -f "/tmp/upload-state-${VIDEO_ID}.txt" ]]; then
        local upload_success=$(grep -c "^SUCCESS:" "/tmp/upload-state-${VIDEO_ID}.txt" 2>/dev/null | head -1 | tr -d '\n' || echo 0)
        local upload_failed=$(grep -c "^FAILED:" "/tmp/upload-state-${VIDEO_ID}.txt" 2>/dev/null | head -1 | tr -d '\n' || echo 0)
        log_info "📊 Original upload summary: $upload_success uploaded, $upload_failed failed"
        
        if [[ $upload_failed -gt 0 ]]; then
            log_warn "Some chunks had failed uploads during recording"
        fi
    fi
    
    return $verify_result
}

# Cleanup function
cleanup() {
    log_info "🧹 Cleaning up chunk downloader..."
    
    # Final status report
    local local_chunks=$(find "$LOCAL_CHUNK_DIR" -name "*.mp4" -type f | wc -l 2>/dev/null | tr -d '\n' || echo 0)
    local success_count=$(grep -c "^SUCCESS:" "$STATE_FILE" 2>/dev/null | head -1 | tr -d '\n' || echo 0)
    local failed_count=$(grep -c "^FAILED:" "$STATE_FILE" 2>/dev/null | head -1 | tr -d '\n' || echo 0)
    
    log_info "📊 Final download status: $local_chunks local chunks, $success_count successful, $failed_count failed"
    
    if [ $failed_count -gt 0 ]; then
        log_warn "Failed downloads logged in: $STATE_FILE"
        log_info "💡 Failed chunks may need manual recovery from S3"
    else
        # Clean up state file if all successful
        rm -f "$STATE_FILE" 2>/dev/null
        log_success "All downloads successful, cleanup completed"
    fi
    
    log_info "🏁 Chunk downloader finished"
}

# Set up cleanup trap
trap cleanup EXIT INT TERM

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    if [ -z "$1" ]; then
        log_error "Usage: $0 <VIDEO_ID> [LOCAL_CHUNK_DIR]"
        log_error "Example: $0 my-video-123 /recordings/my-video-123/chunks"
        exit 1
    fi
    
    # Validate S3 credentials
    if [ -z "$HA_AWS_ACCESS_KEY" ] || [ -z "$HA_AWS_SECRET_KEY" ]; then
        log_error "S3 credentials not configured (HA_AWS_ACCESS_KEY, HA_AWS_SECRET_KEY)"
        exit 1
    fi
    
    # Run the download process
    if download_all_chunks; then
        log_success "✅ Chunk download completed successfully"
        exit 0
    else
        log_error "❌ Chunk download completed with errors"
        exit 1
    fi
fi