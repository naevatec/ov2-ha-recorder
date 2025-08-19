#!/bin/bash

# S3 chunk cleanup script - removes uploaded chunks after successful recording
# Called after chunks have been downloaded and joined into final video

# Load shared logging library
LOG_FILE="/var/log/chunk-cleaner-${1:-${VIDEO_ID:-video}}.log"
source /usr/local/bin/logging.sh

VIDEO_ID=${1:-${VIDEO_ID:-video}}
FORCE_CLEANUP=${2:-false}  # Set to true to cleanup even if local verification fails

# S3 Configuration - works with AWS S3, MinIO, or any S3-compatible service
S3_BUCKET=${HA_AWS_S3_BUCKET:-ov-recordings}
S3_ENDPOINT=${HA_AWS_S3_SERVICE_ENDPOINT}

export AWS_ACCESS_KEY_ID=${HA_AWS_ACCESS_KEY}
export AWS_SECRET_ACCESS_KEY=${HA_AWS_SECRET_KEY}

# Build AWS command with timeout for any S3-compatible service
AWS_CMD="timeout 60 aws s3 rm"
AWS_LIST_CMD="timeout 30 aws s3 ls"
AWS_SYNC_CMD="timeout 120 aws s3 rm --recursive"
[ -n "$S3_ENDPOINT" ] && AWS_CMD="$AWS_CMD --endpoint-url $S3_ENDPOINT"
[ -n "$S3_ENDPOINT" ] && AWS_LIST_CMD="$AWS_LIST_CMD --endpoint-url $S3_ENDPOINT"
[ -n "$S3_ENDPOINT" ] && AWS_SYNC_CMD="$AWS_SYNC_CMD --endpoint-url $S3_ENDPOINT"

log_info "🧹 Starting S3 chunk cleanup for VIDEO_ID: $VIDEO_ID"
log_info "☁️  S3 Bucket: $S3_BUCKET"
log_info "🔗 S3 Endpoint: ${S3_ENDPOINT:-default AWS}"
log_info "⚠️  Force cleanup: $FORCE_CLEANUP"

# S3 paths
S3_CHUNKS_PATH="s3://$S3_BUCKET/$VIDEO_ID/chunks/"
S3_VIDEO_PATH="s3://$S3_BUCKET/$VIDEO_ID/"

# Function to verify final video exists locally
verify_final_video() {
    local final_video="/recordings/$VIDEO_ID/${VIDEO_NAME:-video}.${VIDEO_FORMAT:-mp4}"
    
    log_info "🔍 Verifying final video exists: $final_video"
    
    if [ -f "$final_video" ]; then
        local video_size=$(stat -c%s "$final_video" 2>/dev/null || echo 0)
        if [ "$video_size" -gt 1048576 ]; then  # > 1MB
            log_success "Final video verified: ${video_size} bytes"
            return 0
        else
            log_error "Final video too small: ${video_size} bytes"
            return 1
        fi
    else
        log_error "Final video file not found: $final_video"
        return 1
    fi
}

# Function to list chunks in S3 before cleanup
list_s3_chunks() {
    log_info "📋 Listing chunks to be cleaned from S3..."
    
    local s3_files
    if s3_files=$($AWS_LIST_CMD "$S3_CHUNKS_PATH" 2>/dev/null | grep "\.mp4$" | awk '{print $4}'); then
        if [ -n "$s3_files" ]; then
            local chunk_count=$(echo "$s3_files" | wc -l)
            log_info "📊 Found $chunk_count chunks in S3 to cleanup:"
            echo "$s3_files" | while read filename; do
                log_info "  - $filename"
            done
            echo "$s3_files"
            return 0
        else
            log_info "No .mp4 chunks found in S3 (already cleaned or none uploaded)"
            return 1
        fi
    else
        log_warn "Failed to list S3 chunks or directory doesn't exist"
        return 1
    fi
}

# Function to calculate total S3 storage being cleaned
calculate_cleanup_size() {
    log_info "📏 Calculating total size of chunks to cleanup..."
    
    local total_size=0
    local chunk_count=0
    
    # Get detailed listing with sizes
    $AWS_LIST_CMD "$S3_CHUNKS_PATH" 2>/dev/null | grep "\.mp4$" | while read date time size filename; do
        if [ -n "$size" ] && [ "$size" -gt 0 ]; then
            total_size=$((total_size + size))
            chunk_count=$((chunk_count + 1))
        fi
    done
    
    # Convert bytes to human readable
    if [ "$total_size" -gt 1073741824 ]; then
        local size_gb=$(echo "scale=2; $total_size / 1073741824" | bc 2>/dev/null || echo "unknown")
        log_info "📊 Cleanup will free: ${size_gb}GB ($chunk_count chunks)"
    elif [ "$total_size" -gt 1048576 ]; then
        local size_mb=$(echo "scale=2; $total_size / 1048576" | bc 2>/dev/null || echo "unknown")
        log_info "📊 Cleanup will free: ${size_mb}MB ($chunk_count chunks)"
    else
        log_info "📊 Cleanup will free: ${total_size} bytes ($chunk_count chunks)"
    fi
}

# Function to delete individual chunks (safer, with verification)
cleanup_chunks_individually() {
    local s3_chunks="$1"
    local deleted_count=0
    local failed_count=0
    
    log_info "🗑️  Starting individual chunk cleanup..."
    
    echo "$s3_chunks" | while read filename; do
        if [ -n "$filename" ]; then
            local s3_path="$S3_CHUNKS_PATH$filename"
            
            log_info "🗑️  Deleting: $filename"
            
            if $AWS_CMD "$s3_path" 2>&1 | tee -a "$LOG_FILE"; then
                log_success "Deleted: $filename"
                ((deleted_count++))
            else
                log_error "Failed to delete: $filename"
                ((failed_count++))
            fi
        fi
    done
    
    log_info "📊 Individual cleanup results: $deleted_count deleted, $failed_count failed"
    
    if [ "$failed_count" -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Function to delete all chunks recursively (faster for many files)
cleanup_chunks_bulk() {
    log_info "🗑️  Starting bulk chunk cleanup..."
    
    # Delete entire chunks directory recursively
    if $AWS_SYNC_CMD "$S3_CHUNKS_PATH" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Bulk cleanup completed successfully"
        return 0
    else
        log_error "Bulk cleanup failed"
        return 1
    fi
}

# Function to verify cleanup was successful
verify_cleanup() {
    log_info "🔍 Verifying S3 cleanup was successful..."
    
    # Try to list the chunks directory
    if $AWS_LIST_CMD "$S3_CHUNKS_PATH" 2>/dev/null | grep -q "\.mp4$"; then
        log_warn "Some chunks may still exist in S3"
        
        # List remaining chunks
        log_info "📋 Remaining chunks:"
        $AWS_LIST_CMD "$S3_CHUNKS_PATH" 2>/dev/null | grep "\.mp4$" | while read line; do
            log_info "  - $line"
        done
        return 1
    else
        log_success "All chunks successfully removed from S3"
        return 0
    fi
}

# Function to cleanup the entire video directory (optional)
cleanup_entire_video_directory() {
    log_info "🗑️  Cleaning up entire video directory from S3..."
    
    # This removes everything including logs, metadata, etc.
    if $AWS_SYNC_CMD "$S3_VIDEO_PATH" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Entire video directory cleaned from S3"
        return 0
    else
        log_error "Failed to cleanup entire video directory"
        return 1
    fi
}

# Function to check upload/download state files for safety
check_state_files() {
    local upload_state="/tmp/upload-state-${VIDEO_ID}.txt"
    local download_state="/tmp/download-state-${VIDEO_ID}.txt"
    
    log_info "🔍 Checking upload/download state files..."
    
    # Check upload state
    if [ -f "$upload_state" ]; then
        local upload_success=$(grep -c "^SUCCESS:" "$upload_state" 2>/dev/null || echo 0)
        local upload_failed=$(grep -c "^FAILED:" "$upload_state" 2>/dev/null || echo 0)
        log_info "📊 Upload state: $upload_success successful, $upload_failed failed"
        
        if [ "$upload_failed" -gt 0 ] && [ "$FORCE_CLEANUP" != "true" ]; then
            log_warn "Some chunks failed to upload - consider manual verification before cleanup"
            return 1
        fi
    else
        log_warn "Upload state file not found: $upload_state"
    fi
    
    # Check download state
    if [ -f "$download_state" ]; then
        local download_success=$(grep -c "^SUCCESS:" "$download_state" 2>/dev/null || echo 0)
        local download_failed=$(grep -c "^FAILED:" "$download_state" 2>/dev/null || echo 0)
        log_info "📊 Download state: $download_success successful, $download_failed failed"
        
        if [ "$download_failed" -gt 0 ] && [ "$FORCE_CLEANUP" != "true" ]; then
            log_warn "Some chunks failed to download - consider manual verification before cleanup"
            return 1
        fi
    else
        log_warn "Download state file not found: $download_state"
    fi
    
    return 0
}

# Main cleanup function
cleanup_s3_chunks() {
    log_info "🚀 Starting S3 chunk cleanup process..."
    
    # Safety check 1: Verify final video exists locally (unless force cleanup)
    if [ "$FORCE_CLEANUP" != "true" ]; then
        if ! verify_final_video; then
            log_error "Final video verification failed - aborting cleanup for safety"
            log_info "💡 Use FORCE_CLEANUP=true to override this safety check"
            return 1
        fi
    else
        log_warn "⚠️  FORCE_CLEANUP enabled - skipping safety checks"
    fi
    
    # Safety check 2: Check state files
    if [ "$FORCE_CLEANUP" != "true" ]; then
        if ! check_state_files; then
            log_warn "State file check indicates potential issues"
            log_info "💡 Use FORCE_CLEANUP=true to override this safety check"
            return 1
        fi
    fi
    
    # List chunks that will be cleaned
    local s3_chunks
    if ! s3_chunks=$(list_s3_chunks); then
        log_info "No chunks found to cleanup - either already cleaned or none were uploaded"
        return 0
    fi
    
    # Calculate cleanup size
    calculate_cleanup_size
    
    # Perform cleanup
    log_info "🗑️  Starting chunk deletion from S3..."
    
    # Method 1: Try bulk cleanup first (faster)
    if cleanup_chunks_bulk; then
        log_success "Bulk cleanup method succeeded"
    else
        log_warn "Bulk cleanup failed, trying individual cleanup..."
        
        # Method 2: Individual chunk cleanup (safer)
        if cleanup_chunks_individually "$s3_chunks"; then
            log_success "Individual cleanup method succeeded"
        else
            log_error "Individual cleanup method failed"
            return 1
        fi
    fi
    
    # Verify cleanup was successful
    if verify_cleanup; then
        log_success "S3 chunk cleanup verified successfully"
    else
        log_warn "Cleanup verification found remaining chunks"
        return 1
    fi
    
    return 0
}

# Cleanup function for script termination
cleanup_script() {
    log_info "🧹 Cleaning up chunk cleaner script..."
    
    # Clean up state files if cleanup was successful
    if [ "$?" -eq 0 ]; then
        log_info "🗑️  Cleaning up state files..."
        rm -f "/tmp/upload-state-${VIDEO_ID}.txt" 2>/dev/null
        rm -f "/tmp/download-state-${VIDEO_ID}.txt" 2>/dev/null
        log_success "State files cleaned up"
    else
        log_info "💾 Preserving state files due to cleanup errors"
    fi
    
    log_info "🏁 Chunk cleaner finished"
}

# Set up cleanup trap
trap cleanup_script EXIT INT TERM

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    if [ -z "$1" ]; then
        log_error "Usage: $0 <VIDEO_ID> [FORCE_CLEANUP]"
        log_error "Example: $0 my-video-123"
        log_error "Example: $0 my-video-123 true  # Force cleanup"
        exit 1
    fi
    
    # Validate S3 credentials
    if [ -z "$HA_AWS_ACCESS_KEY" ] || [ -z "$HA_AWS_SECRET_KEY" ]; then
        log_error "S3 credentials not configured (HA_AWS_ACCESS_KEY, HA_AWS_SECRET_KEY)"
        exit 1
    fi
    
    # Run the cleanup process
    if cleanup_s3_chunks; then
        log_success "✅ S3 chunk cleanup completed successfully"
        exit 0
    else
        log_error "❌ S3 chunk cleanup completed with errors"
        exit 1
    fi
fi