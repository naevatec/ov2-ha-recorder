#!/bin/bash

# Log uploader script - Collects all log files, creates tgz archive and saves locally
# Usage: ./log-uploader.sh <VIDEO_ID>

# Load shared logging library
LOG_FILE="/var/log/log-uploader-${1:-${VIDEO_ID:-video}}.log"
source /usr/local/bin/logging.sh

VIDEO_ID=${1:-${VIDEO_ID:-video}}
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
ARCHIVE_NAME="logs_${VIDEO_ID}_${TIMESTAMP}.tgz"
TEMP_DIR="/tmp/log-collection-${VIDEO_ID}-${TIMESTAMP}"

# Save archive to recordings directory instead of S3
RECORDINGS_DIR="/recordings/$VIDEO_ID"
ARCHIVE_PATH="$RECORDINGS_DIR/$ARCHIVE_NAME"

log_info "🚀 Starting log uploader for VIDEO_ID: $VIDEO_ID"
log_info "📦 Archive name: $ARCHIVE_NAME"
log_info "💾 Local archive path: $ARCHIVE_PATH"

# Function to collect log files
collect_log_files() {
    log_info "📋 Collecting log files..."

    # Create temporary directory for log collection
    mkdir -p "$TEMP_DIR"

    local collected_count=0
    local total_size=0

    # Collect logs from various locations
    log_info "🔍 Searching for log files..."

    # 1. Video-specific logs in recordings directory
    if [ -d "/recordings/$VIDEO_ID" ]; then
        log_info "🔍 Collecting logs from /recordings/$VIDEO_ID/"
        find "/recordings/$VIDEO_ID" -name "*.log" -type f 2>/dev/null | while read log_file; do
            if [ -f "$log_file" ]; then
                local filename=$(basename "$log_file")
                cp "$log_file" "$TEMP_DIR/recording_${filename}" 2>/dev/null
                local size=$(stat -c%s "$log_file" 2>/dev/null || echo 0)
                log_info "  ✅ $filename (${size} bytes)"
                ((collected_count++))
                ((total_size += size))
            fi
        done

        # Also collect video analysis file if it exists
        if [ -f "/recordings/$VIDEO_ID/$VIDEO_ID.info" ]; then
            cp "/recordings/$VIDEO_ID/$VIDEO_ID.info" "$TEMP_DIR/video_analysis_${VIDEO_ID}.info" 2>/dev/null
            local size=$(stat -c%s "/recordings/$VIDEO_ID/$VIDEO_ID.info" 2>/dev/null || echo 0)
            log_info "  ✅ video analysis info (${size} bytes)"
            ((collected_count++))
            ((total_size += size))
        fi
    fi

    # 2. System logs related to our video ID
    log_info "🔍 Collecting video-specific system logs..."
    find /var/log -name "*${VIDEO_ID}*" -type f 2>/dev/null | while read log_file; do
        if [ -f "$log_file" ]; then
            local filename=$(basename "$log_file")
            cp "$log_file" "$TEMP_DIR/system_${filename}" 2>/dev/null
            local size=$(stat -c%s "$log_file" 2>/dev/null || echo 0)
            log_info "  ✅ $filename (${size} bytes)"
            ((collected_count++))
            ((total_size += size))
        fi
    done

    # 3. Chunk uploader/downloader logs
    log_info "🔍 Collecting chunk processing logs..."
    for log_pattern in "chunk-uploader-${VIDEO_ID}.log" "chunk-downloader-${VIDEO_ID}.log" "composed-${VIDEO_ID}.log" "log-uploader-${VIDEO_ID}.log"; do
        local log_file="/var/log/$log_pattern"
        if [ -f "$log_file" ]; then
            cp "$log_file" "$TEMP_DIR/$log_pattern" 2>/dev/null
            local size=$(stat -c%s "$log_file" 2>/dev/null || echo 0)
            log_info "  ✅ $log_pattern (${size} bytes)"
            ((collected_count++))
            ((total_size += size))
        fi
    done

    # 4. Temporary logs and state files
    log_info "🔍 Collecting temporary logs and state files..."
    for temp_pattern in "upload-state-${VIDEO_ID}.txt" "download-state-${VIDEO_ID}.txt" "container.log"; do
        local temp_file="/tmp/$temp_pattern"
        if [ -f "$temp_file" ]; then
            cp "$temp_file" "$TEMP_DIR/$temp_pattern" 2>/dev/null
            local size=$(stat -c%s "$temp_file" 2>/dev/null || echo 0)
            log_info "  ✅ $temp_pattern (${size} bytes)"
            ((collected_count++))
            ((total_size += size))
        fi
    done

    # 5. Debug logs if they exist
    if [[ "${DEBUG_MODE:-false}" == "true" ]]; then
        log_info "🔍 Collecting debug logs..."
        for debug_file in "/recordings/$VIDEO_ID/$VIDEO_ID-container.log" "/recordings/$VIDEO_ID/chrome_debug.log"; do
            if [ -f "$debug_file" ]; then
                local filename=$(basename "$debug_file")
                cp "$debug_file" "$TEMP_DIR/debug_${filename}" 2>/dev/null
                local size=$(stat -c%s "$debug_file" 2>/dev/null || echo 0)
                log_info "  ✅ debug_$filename (${size} bytes)"
                ((collected_count++))
                ((total_size += size))
            fi
        done
    fi

    # 6. Create a summary file
    log_info "📄 Creating log collection summary..."
    cat > "$TEMP_DIR/LOG_COLLECTION_SUMMARY.txt" << EOF
Log Collection Summary for VIDEO_ID: $VIDEO_ID
Timestamp: $(date)
Archive: $ARCHIVE_NAME

Collection Details:
- Total files collected: $collected_count
- Total size: $total_size bytes
- Collection directory: $TEMP_DIR

Files included:
$(ls -la "$TEMP_DIR" 2>/dev/null || echo "No files collected")

System Information:
- Hostname: $(hostname)
- Uptime: $(uptime)
- Docker container ID: $(cat /proc/self/cgroup 2>/dev/null | head -1 | sed 's/.*\///' || echo "N/A")

Environment Variables (filtered):
$(env | grep -E "(VIDEO_ID|HA_|CHUNK_|S3_|AWS_)" | sort || echo "No relevant env vars")
EOF

    # Count actual collected files
    local actual_count=$(find "$TEMP_DIR" -type f | wc -l)
    local actual_size=$(du -sb "$TEMP_DIR" 2>/dev/null | cut -f1 || echo 0)

    log_info "📊 Log collection completed:"
    log_info "  - Files collected: $actual_count"
    log_info "  - Total size: $actual_size bytes"

    if [ "$actual_count" -eq 0 ]; then
        log_warn "No log files found for collection"
        return 1
    fi

    return 0
}

# Function to create and save tgz archive locally
create_and_save_archive() {
    log_info "📦 Creating tgz archive: $ARCHIVE_NAME"

    # Ensure recordings directory exists
    mkdir -p "$RECORDINGS_DIR"

    # Create the archive from the temporary directory
    if tar -czf "$ARCHIVE_PATH" -C "$TEMP_DIR" . 2>&1 | tee -a "$LOG_FILE"; then
        local archive_size=$(stat -c%s "$ARCHIVE_PATH" 2>/dev/null || echo 0)
        log_success "Archive created and saved locally: $ARCHIVE_PATH (${archive_size} bytes)"
        return 0
    else
        log_error "Failed to create archive: $ARCHIVE_PATH"
        return 1
    fi
}

# Function to verify local archive
verify_local_archive() {
    log_info "🔍 Verifying local archive..."

    if [ -f "$ARCHIVE_PATH" ]; then
        local archive_size=$(stat -c%s "$ARCHIVE_PATH" 2>/dev/null || echo 0)
        if [ "$archive_size" -gt 0 ]; then
            # Test if archive can be listed (validates it's not corrupted)
            if tar -tzf "$ARCHIVE_PATH" >/dev/null 2>&1; then
                log_success "Archive verified successfully: ${archive_size} bytes"

                # Show contents summary
                local file_count=$(tar -tzf "$ARCHIVE_PATH" 2>/dev/null | wc -l)
                log_info "Archive contains $file_count files"
                return 0
            else
                log_error "Archive verification failed: file is corrupted"
                return 1
            fi
        else
            log_error "Archive verification failed: file is empty"
            return 1
        fi
    else
        log_error "Archive verification failed: file not found"
        return 1
    fi
}

# Cleanup function
cleanup() {
    log_info "🧹 Cleaning up temporary files..."

    # Remove temporary directory
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        log_info "Temporary directory removed: $TEMP_DIR"
    fi

    log_info "🏁 Log uploader cleanup completed"
}

# Set up cleanup trap
trap cleanup EXIT INT TERM

# Main execution function
main() {
    log_info "🚀 Starting log collection and local archive process..."

    # Step 1: Collect log files
    if ! collect_log_files; then
        log_error "Log collection failed"
        exit 1
    fi

    # Step 2: Create and save archive locally
    if ! create_and_save_archive; then
        log_error "Archive creation failed"
        exit 1
    fi

    # Step 3: Verify local archive
    if verify_local_archive; then
        log_success "Archive verification completed"
    else
        log_warn "Archive verification failed, but file may still be usable"
    fi

    # Final summary
    log_success "✅ Log archive process completed successfully"
    log_info "📦 Archive saved to: $ARCHIVE_PATH"
    log_info "📋 Archive contains logs for VIDEO_ID: $VIDEO_ID"
    log_info "🕒 Timestamp: $TIMESTAMP"
    log_info "💡 Archive can be manually retrieved from the recordings directory"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    if [ -z "$1" ]; then
        log_error "Usage: $0 <VIDEO_ID>"
        log_error "Example: $0 my-video-123"
        exit 1
    fi

    # Run the main process
    main
fi
