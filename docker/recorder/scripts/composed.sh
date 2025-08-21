#!/bin/bash

# Load shared logging library
LOG_FILE="/var/log/composed-${VIDEO_ID:-video}.log"
source /usr/local/bin/logging.sh

# DEBUG MODE
DEBUG_MODE=${DEBUG_MODE:-false}
if [[ ${DEBUG_MODE} == true ]]; then
  DEBUG_CHROME_FLAGS="--enable-logging --v=1"
fi

{
  ### Variables ###

  URL=${URL:-https://www.youtube.com/watch?v=JMuzlEQz3uo}
  ONLY_VIDEO=${ONLY_VIDEO:-false}
  RESOLUTION=${RESOLUTION:-1280x720}
  FRAMERATE=${FRAMERATE:-25}
  WIDTH="$(cut -d'x' -f1 <<<$RESOLUTION)"
  HEIGHT="$(cut -d'x' -f2 <<<$RESOLUTION)"
  VIDEO_ID=${VIDEO_ID:-video}
  VIDEO_NAME=${VIDEO_NAME:-video}
  VIDEO_FORMAT=${VIDEO_FORMAT:-mp4}
  RECORDING_JSON="${RECORDING_JSON}"

  # HA-RECORDER Variables
  # Load variables from /recordings/.env
  if [[ -f /recordings/.env ]]; then
    set -a
    source /recordings/.env
    set +a
    log_info "Loaded environment variables from /recordings/.env"
  fi

  CHUNK_RECORDING_TYPE=${HA_RECORDING_STORAGE:-local} # May be "local" or "s3"
  CHUNK_FOLDER=${CHUNK_FOLDER:-/chunks}
  CHUNK_START=${START_CHUNK:-0000}
  CHUNK_TIME_SIZE=${CHUNK_TIME_SIZE:-10}              # In seconds
  CHUNK_RECORDING_DIR="/recordings/$VIDEO_ID/$(echo "$CHUNK_FOLDER" | sed 's|^/||')"

  export URL
  export ONLY_VIDEO
  export RESOLUTION
  export FRAMERATE
  export WIDTH
  export HEIGHT
  export VIDEO_ID
  export VIDEO_NAME
  export VIDEO_FORMAT
  export RECORDING_JSON
  # HA-RECORDER Variables
  export CHUNK_FOLDER
  export CHUNK_START
  export CHUNK_TIME_SIZE
  export CHUNK_RECORDING_DIR

  log_info "🚀 Starting recording process for VIDEO_ID: $VIDEO_ID"
  log_info "🎹 Resolution: $RESOLUTION, Framerate: $FRAMERATE"
  log_info "📂 Chunk recording type: $CHUNK_RECORDING_TYPE"
  log_info "📁 Chunk directory: $CHUNK_RECORDING_DIR"
  log_info "⏱️ Chunk duration: ${CHUNK_TIME_SIZE}s"

  ### Chunk Upload Integration ###
  
  # Start chunk uploader if recording to S3
  if [[ "$CHUNK_RECORDING_TYPE" == "s3" ]]; then
    log_info "☁️ Starting chunk uploader for S3 storage..."
    log_info "🪣 S3 Bucket: ${HA_AWS_S3_BUCKET:-ov-recordings}"
    log_info "🔗 S3 Endpoint: ${HA_AWS_S3_SERVICE_ENDPOINT:-default AWS}"
    
    # Start the chunk uploader in background
    /usr/local/bin/chunk-uploader.sh "$VIDEO_ID" &
    UPLOADER_PID=$!
    echo $UPLOADER_PID > "/tmp/uploader-${VIDEO_ID}.pid"
    log_success "Chunk uploader started (PID: $UPLOADER_PID)"
  else
    log_info "💾 Local storage mode - chunk uploader not started"
  fi

  log_info "============= Loaded Environment Variables ============="
  env | tee -a "$LOG_FILE"
  log_info "========================================================"

  ### Store Recording json data ###

  mkdir -p $CHUNK_RECORDING_DIR
  chmod -R 777 /recordings/$VIDEO_ID
  
  # Create initial recording JSON if RECORDING_JSON is provided, otherwise create a default one
  if [[ -n "$RECORDING_JSON" ]]; then
    echo $RECORDING_JSON >/recordings/$VIDEO_ID/.recording.$VIDEO_ID
    log_info "📄 Recording metadata stored from RECORDING_JSON"
  else
    # Create default recording JSON structure
    TIMESTAMP=$(date +%s)000  # Milliseconds timestamp
    cat > /recordings/$VIDEO_ID/.recording.$VIDEO_ID << EOF
{
  "id": "$VIDEO_ID",
  "object": "recording", 
  "name": "$VIDEO_ID",
  "outputMode": "COMPOSED",
  "resolution": "$RESOLUTION",
  "frameRate": $FRAMERATE,
  "recordingLayout": "BEST_FIT",
  "sessionId": "$VIDEO_ID",
  "uniqueSessionId": "${VIDEO_ID}_${TIMESTAMP}",
  "createdAt": $TIMESTAMP,
  "size": 0,
  "duration": 0,
  "url": "",
  "hasAudio": false,
  "hasVideo": false,
  "status": "started"
}
EOF
    log_info "📄 Default recording metadata created"
  fi

  ### HA Controller Session Registration ###
  log_info "🔗 Registering session with HA Controller..."

  register_session_with_ha() {
    local recording_file="/recordings/$VIDEO_ID/.recording.$VIDEO_ID"
    
    if [[ -f "$recording_file" ]]; then
      log_info "📤 Sending session registration to HA Controller..."
      
      (
        timeout 30 /usr/local/bin/session-register.sh "$recording_file" 2>&1 | while read line; do
          log_info "[HA-REG] $line"
        done
        
        if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
          log_success "✅ Session registered with HA Controller successfully"
          
          /usr/local/bin/recorder-session-manager.sh "$recording_file" "$CHUNK_RECORDING_DIR" &
          HA_MANAGER_PID=$!
          echo $HA_MANAGER_PID > "/tmp/ha-manager-${VIDEO_ID}.pid"
          log_success "💓 HA Manager started (PID: $HA_MANAGER_PID)"
        else
          log_warn "⚠️ Failed to register session with HA Controller (non-critical)"
        fi
      ) &
      
      log_info "🔗 Session registration initiated in background"
    fi
  }

  register_session_with_ha

  ### Run headless Chrome ###

  source /headless-chrome.sh
  chmod 777 /recordings

  ### Evaluate chunk configuration ###
  # Get next index to use
  result=$(cd "$CHUNK_RECORDING_DIR" && echo $(ls ????.mp4 2>/dev/null || echo "$CHUNK_START") | sed 's/\w+.mp4//g' | sed 's/.mp4//g' | awk '{print $NF}' | sed 's/^0*//g')
  # Check if the result is empty
  if [[ -z "$result" ]]; then
      log_info "Result is empty. Setting default value to 0."
      result=0
  fi
  INDEX=$(printf %04d $(( 1 + $result)) )
  log_info "📊 Starting chunk index: $INDEX"

  # Create a non empty file to avoid OpenVidu to stop the recording
  echo "Recording by chunks" > /recordings/$VIDEO_ID/$VIDEO_NAME.$VIDEO_FORMAT
  log_info "📁 Placeholder video file created"

  ### Start recording with ffmpeg ###

  log_info "🎬 Starting FFmpeg recording..."
  
  if [[ "$ONLY_VIDEO" == true ]]; then
    # Record video only (no audio) with chunking
    log_info "🎥 Recording video only (no audio) with chunking"
    ffmpeg <./stop -y \
      -f x11grab -draw_mouse 0 -framerate $FRAMERATE -video_size $RESOLUTION -i :$DISPLAY_NUM \
      -c:v libx264 \
      -preset ultrafast \
      -crf 28 \
      -refs 4 \
      -qmin 4 \
      -pix_fmt yuv420p \
      -filter:v "fps=$FRAMERATE,drawtext=text='IMAGE BY NAEVATEC v2.0':fontsize=50:fontcolor=white:x=(w-text_w)/2:y=h-text_h-20:shadowcolor=black:shadowx=2:shadowy=2" \
      -f segment \
      -segment_time $CHUNK_TIME_SIZE \
      -segment_start_number $INDEX \
      -segment_format $VIDEO_FORMAT \
      -reset_timestamps 1 \
      "$CHUNK_RECORDING_DIR/%04d.$VIDEO_FORMAT"
  else
    # Record audio  ("-f alsa -i pulse [...] -c:a aac")
    log_info "🎥🎵 Recording video with audio"
    ffmpeg <./stop -y \
      -f alsa -i pulse \
      -f x11grab -draw_mouse 0 -framerate $FRAMERATE -video_size $RESOLUTION -i :$DISPLAY_NUM \
      -c:a aac \
      -c:v libx264 \
      -preset ultrafast \
      -crf 28 \
      -refs 4 \
      -qmin 4 \
      -pix_fmt yuv420p \
      -filter:v "fps=$FRAMERATE,drawtext=text='IMAGE BY NAEVATEC v2.0':fontsize=50:fontcolor=white:x=(w-text_w)/2:y=h-text_h-20:shadowcolor=black:shadowx=2:shadowy=2" \
      -f segment \
      -segment_time $CHUNK_TIME_SIZE \
      -segment_start_number $INDEX \
      -segment_format $VIDEO_FORMAT \
      -reset_timestamps 1 \
      "$CHUNK_RECORDING_DIR/%04d.$VIDEO_FORMAT"
  fi

  log_success "FFmpeg recording completed"

  ### Chunk Upload Cleanup ###
  
  log_info "🧹 Starting chunk processing cleanup..."

  # Stop chunk uploader if it was started - but allow it to finish current uploads
  if [[ "$CHUNK_RECORDING_TYPE" == "s3" ]]; then
    if [[ -f "/tmp/uploader-${VIDEO_ID}.pid" ]]; then
      UPLOADER_PID=$(cat "/tmp/uploader-${VIDEO_ID}.pid")
      if kill -0 "$UPLOADER_PID" 2>/dev/null; then
        log_info "🛑 Stopping chunk uploader (PID: $UPLOADER_PID) - recording finished"
        
        # Send TERM signal to the process group to kill all child processes
        kill -TERM -$UPLOADER_PID 2>/dev/null
        
        # Wait up to 10 seconds for graceful shutdown
        wait_count=0
        while [ ${wait_count:-0} -lt 10 ] && kill -0 "$UPLOADER_PID" 2>/dev/null; do
          log_info "⏳ Waiting for uploader to finish current uploads... (${wait_count}s)"
          sleep 1
          ((wait_count++))
        done
        
        # Force kill the entire process group if still running
        if kill -0 "$UPLOADER_PID" 2>/dev/null; then
          log_info "🔪 Force killing uploader process group after 10s timeout"
          kill -KILL -$UPLOADER_PID 2>/dev/null
        else
          log_success "Chunk uploader stopped gracefully"
        fi
      fi
      rm -f "/tmp/uploader-${VIDEO_ID}.pid"
    fi
    
    # Additional cleanup: Kill any remaining uploader processes by name
    log_info "🧹 Cleaning up any remaining uploader processes..."
    pkill -f "chunk-uploader.sh $VIDEO_ID" 2>/dev/null || true
    pkill -f "inotifywait.*$VIDEO_ID" 2>/dev/null || true
    
    # Wait a moment for any final uploads to complete
    log_info "⏳ Waiting 5 seconds for any final uploads to complete..."
    sleep 5
    
    # Download all uploaded chunks from S3 using the chunk downloader
    log_info "📥 Starting chunk download from S3..."
    
    # Export the same AWS environment that the uploader used
    export AWS_ACCESS_KEY_ID="${HA_AWS_ACCESS_KEY}"
    export AWS_SECRET_ACCESS_KEY="${HA_AWS_SECRET_KEY}"
    export HA_AWS_S3_SERVICE_ENDPOINT="${HA_AWS_S3_SERVICE_ENDPOINT}"
    export HA_AWS_S3_BUCKET="${HA_AWS_S3_BUCKET}"
    
    # Debug: Show what we're passing to downloader
    log_info "🔑 AWS credentials check:"
    log_info "  - Endpoint: ${HA_AWS_S3_SERVICE_ENDPOINT:-'not set'}"
    log_info "  - Bucket: ${HA_AWS_S3_BUCKET:-'not set'}"
    log_info "  - Access Key: ${HA_AWS_ACCESS_KEY:0:8}... (${#HA_AWS_ACCESS_KEY} chars)"
    
    if /usr/local/bin/chunk-downloader.sh "$VIDEO_ID" "$CHUNK_RECORDING_DIR"; then
      log_success "All chunks downloaded from S3 successfully"
    else
      log_error "Failed to download some chunks from S3"
      
      # Debug information
      log_info "🔍 Debugging chunk download failure..."
      log_info "📋 Checking S3 contents..."
      
      # List what's actually in S3
      AWS_LIST_CMD="timeout 30 aws s3 ls"
      [ -n "$S3_ENDPOINT" ] && AWS_LIST_CMD="$AWS_LIST_CMD --endpoint-url $S3_ENDPOINT"
      
      if $AWS_LIST_CMD "s3://$S3_BUCKET/$VIDEO_ID/chunks/" 2>&1 | tee -a "$LOG_FILE"; then
        log_info "S3 listing completed"
      else
        log_error "Failed to list S3 contents"
      fi
      
      # Check local directory
      log_info "📋 Checking local chunk directory..."
      if [ -d "$CHUNK_RECORDING_DIR" ]; then
        local local_chunks=$(find "$CHUNK_RECORDING_DIR" -name "*.mp4" -type f | wc -l)
        log_info "Found $local_chunks local chunks"
        if [ $local_chunks -gt 0 ]; then
          log_info "Local chunks found, continuing with available chunks"
        fi
      else
        log_error "Local chunk directory does not exist: $CHUNK_RECORDING_DIR"
        mkdir -p "$CHUNK_RECORDING_DIR"
      fi
    fi
    
    log_success "S3 chunk processing completed"
  else
    log_info "💾 Local storage mode - chunks already available locally"
  fi

  ### Join All Chunks (always needed regardless of storage type) ###
  
  log_info "🔗 Starting chunk joining process..."
  
  if [[ -d "$CHUNK_RECORDING_DIR" ]]; then
    # Count available chunks - use command substitution properly
    available_chunks=$(find "$CHUNK_RECORDING_DIR" -name "*.mp4" -type f | wc -l)
    
    log_info "📂 Checking directory: $CHUNK_RECORDING_DIR"
    log_info "📊 Found $available_chunks chunks to join"
    
    if [[ $available_chunks -gt 0 ]]; then
      log_info "🔗 Joining chunks from $CHUNK_RECORDING_DIR"
      
      # Create file list for FFmpeg concat
      concat_file="/tmp/concat-${VIDEO_ID}.txt"
      > "$concat_file"  # Clear the file first
      
      find "$CHUNK_RECORDING_DIR" -name "*.mp4" -type f | sort | while read chunk_file; do
        echo "file '$(realpath "$chunk_file")'" >> "$concat_file"
      done
      
      # Verify concat file was created and has content
      if [[ -f "$concat_file" ]] && [[ -s "$concat_file" ]]; then
        concat_entries=$(wc -l < "$concat_file")
        log_info "📄 Concat file created with $concat_entries entries"
        log_info "📋 Concat file contents:"
        cat "$concat_file" | tee -a "$LOG_FILE"
        
        # Join chunks into final video with timeout
        log_info "🔗 Starting FFmpeg concat operation..."
        if timeout 300 ffmpeg -y -f concat -safe 0 -i "$concat_file" -c copy "/recordings/$VIDEO_ID/$VIDEO_NAME.$VIDEO_FORMAT" 2>&1 | tee -a "$LOG_FILE"; then
          log_success "Chunks successfully joined into final video"
          
          # Clean up chunks and temporary files
          rm -rf "$CHUNK_RECORDING_DIR"
          rm -f "$concat_file"
          log_success "Chunk files cleaned up"
          
          # Verify final video exists and has reasonable size
          if [[ -f "/recordings/$VIDEO_ID/$VIDEO_NAME.$VIDEO_FORMAT" ]]; then
            final_size=$(stat -c%s "/recordings/$VIDEO_ID/$VIDEO_NAME.$VIDEO_FORMAT" 2>/dev/null || echo 0)
            if [[ $final_size -gt 1024 ]]; then
              log_success "Final video created successfully (${final_size} bytes)"
            else
              log_error "Final video file is too small (${final_size} bytes)"
            fi
          else
            log_error "Final video file was not created"
          fi
        else
          log_error "Failed to join chunks (timeout or error) - keeping chunks for manual recovery"
          rm -f "$concat_file"
        fi
      else
        log_error "Failed to create concat file or file is empty"
        if [[ -f "$concat_file" ]]; then
          log_info "📄 Concat file exists but may be empty:"
          ls -la "$concat_file" | tee -a "$LOG_FILE"
        fi
      fi
    else
      log_error "No MP4 chunks found in $CHUNK_RECORDING_DIR"
      log_info "📋 Directory contents:"
      ls -la "$CHUNK_RECORDING_DIR" 2>&1 | tee -a "$LOG_FILE" || log_warn "Cannot list directory contents"
    fi
  else
    log_error "Chunk directory $CHUNK_RECORDING_DIR does not exist"
    log_info "📋 Available recordings directories:"
    ls -la "/recordings/$VIDEO_ID/" 2>&1 | tee -a "$LOG_FILE" || log_warn "Cannot list recordings directory"
  fi

  ### Generate video report file ###
  
  log_info "📊 Generating video analysis report..."
  if ffprobe -v quiet -print_format json -show_format -show_streams /recordings/$VIDEO_ID/$VIDEO_NAME.$VIDEO_FORMAT >/recordings/$VIDEO_ID/$VIDEO_ID.info 2>/dev/null; then
    log_success "Video analysis completed"
  else
    log_warn "Video analysis failed, but continuing"
    echo '{"streams":[],"format":{"size":0,"duration":0}}' > /recordings/$VIDEO_ID/$VIDEO_ID.info
  fi

  ### Update Recording json data ###

  log_info "📁 Updating recording metadata..."
  TMP=$(mktemp /recordings/$VIDEO_ID/.$VIDEO_ID.XXXXXXXXXXXXXXXXXXXXXXX.json)
  
  # Check if analysis file exists and is valid JSON
  if [[ -f "/recordings/$VIDEO_ID/$VIDEO_ID.info" ]] && jq empty /recordings/$VIDEO_ID/$VIDEO_ID.info 2>/dev/null; then
    INFO=$(cat /recordings/$VIDEO_ID/$VIDEO_ID.info | jq '.')
    HAS_AUDIO_AUX=$(echo $INFO | jq '.streams[] | select(.codec_type == "audio")')
    if [ -z "$HAS_AUDIO_AUX" ]; then HAS_AUDIO=false; else HAS_AUDIO=true; fi
    HAS_VIDEO_AUX=$(echo $INFO | jq '.streams[] | select(.codec_type == "video")')
    if [ -z "$HAS_VIDEO_AUX" ]; then HAS_VIDEO=false; else HAS_VIDEO=true; fi
    SIZE=$(echo $INFO | jq '.format.size | tonumber' 2>/dev/null || echo 0)
    DURATION=$(echo $INFO | jq '.format.duration | tonumber' 2>/dev/null || echo 0)
  else
    log_warn "Video analysis file invalid, using fallback values"
    # Fallback: Get file size directly from filesystem
    if [[ -f "/recordings/$VIDEO_ID/$VIDEO_NAME.$VIDEO_FORMAT" ]]; then
      SIZE=$(stat -c%s "/recordings/$VIDEO_ID/$VIDEO_NAME.$VIDEO_FORMAT" 2>/dev/null || echo 0)
      # Try to get duration with a simple ffprobe call
      DURATION=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "/recordings/$VIDEO_ID/$VIDEO_NAME.$VIDEO_FORMAT" 2>/dev/null || echo 0)
      # Assume video exists if file size > 1KB
      if [[ $SIZE -gt 1024 ]]; then
        HAS_VIDEO=true
        HAS_AUDIO=true  # Assume audio since we recorded with audio
      else
        HAS_VIDEO=false
        HAS_AUDIO=false
      fi
    else
      SIZE=0
      DURATION=0
      HAS_VIDEO=false
      HAS_AUDIO=false
    fi
  fi

  if [[ "$HAS_AUDIO" == false && "$HAS_VIDEO" == false ]]; then
    STATUS="failed"
    log_error "Recording failed - no audio or video streams detected"
  else
    STATUS="stopped"
    log_success "Recording completed successfully"
  fi

  jq -c -r ".hasAudio=$HAS_AUDIO | .hasVideo=$HAS_VIDEO | .duration=$DURATION | .size=$SIZE | .status=\"$STATUS\"" "/recordings/$VIDEO_ID/.recording.$VIDEO_ID" >$TMP && mv $TMP /recordings/$VIDEO_ID/.recording.$VIDEO_ID
  
  log_info "📊 Recording stats: Duration=${DURATION}s, Size=${SIZE} bytes, Audio=$HAS_AUDIO, Video=$HAS_VIDEO"

  ### HA Controller - Quick Session Unregistration (Background) ###
  log_info "🧹 Unregistering session from HA Controller..."

  quick_unregister_session() {
    local recording_file="/recordings/$VIDEO_ID/.recording.$VIDEO_ID"
    
    if [[ -f "$recording_file" ]]; then
      local unique_session_id
      unique_session_id=$(jq -r '.uniqueSessionId // .sessionId // .id' "$recording_file" 2>/dev/null || echo "$VIDEO_ID")
      
      if [[ -n "$unique_session_id" ]]; then
        # Quick session removal - no status updates, just delete
        timeout 10 curl -s \
          -u "${APP_SECURITY_USERNAME:-recorder}:${APP_SECURITY_PASSWORD:-rec0rd3r_2024!}" \
          -X DELETE \
          "http://${CONTROLLER_HOST:-ov-recorder}:${CONTROLLER_PORT:-8080}/api/sessions/${unique_session_id}" \
          >/dev/null 2>&1 && log_info "[HA-CLEANUP] Session unregistered successfully" || log_warn "[HA-CLEANUP] Session unregistration failed (non-critical)"
      fi
    fi
  }

  # Start quick unregistration in background immediately
  quick_unregister_session &

  ### Generate video thumbnail ###

  log_info "🖼️ Generating video thumbnail..."
  if [[ -f "/recordings/$VIDEO_ID/$VIDEO_NAME.$VIDEO_FORMAT" ]]; then
    MIDDLE_TIME=$(ffmpeg -i /recordings/$VIDEO_ID/$VIDEO_NAME.$VIDEO_FORMAT 2>&1 | grep Duration | awk '{print $2}' | tr -d , | awk -F ':' '{print ($3+$2*60+$1*3600)/2}' || echo "1")
    THUMBNAIL_HEIGHT=$((480 * $HEIGHT / $WIDTH))
    
    if timeout 30 ffmpeg -ss $MIDDLE_TIME -i /recordings/$VIDEO_ID/$VIDEO_NAME.$VIDEO_FORMAT -vframes 1 -s 480x$THUMBNAIL_HEIGHT /recordings/$VIDEO_ID/$VIDEO_ID.jpg -y 2>/dev/null; then
      log_success "Thumbnail generated"
    else
      log_warn "Thumbnail generation failed or timed out"
    fi
  else
    log_warn "Video file not found, skipping thumbnail generation"
  fi

  ### Change permissions to all generated files ###

  sudo chmod -R 777 /recordings/$VIDEO_ID
  log_info "🔒 File permissions updated"

  ### Upload logs to S3 (if S3 storage is enabled) ###
  
  if [[ "$CHUNK_RECORDING_TYPE" == "s3" ]]; then
    log_info "📋 Starting log upload to S3..."
    
    # Upload all logs related to this recording session
    if /usr/local/bin/log-uploader.sh "$VIDEO_ID"; then
      log_success "All logs uploaded to S3 successfully"
    else
      log_warn "Failed to upload some logs to S3 (non-critical)"
      # Continue anyway - log upload failure shouldn't fail the recording
    fi
    
    log_success "Log upload process completed"
  else
    log_info "📋 Local storage mode - logs kept locally only"
  fi

  ### Clean up S3 chunks after successful recording ###
  
  if [[ "$CHUNK_RECORDING_TYPE" == "s3" ]]; then
    log_info "🧹 Starting S3 chunk cleanup..."
    
    # Only cleanup if we have a successful final video
    if [[ -f "/recordings/$VIDEO_ID/$VIDEO_NAME.$VIDEO_FORMAT" ]]; then
      final_size=$(stat -c%s "/recordings/$VIDEO_ID/$VIDEO_NAME.$VIDEO_FORMAT" 2>/dev/null || echo 0)
      
      if [[ $final_size -gt 1048576 ]]; then  # > 1MB
        log_info "✅ Final video verified (${final_size} bytes) - proceeding with S3 cleanup"
        
        # Call chunk cleaner with the same environment variables
        export AWS_ACCESS_KEY_ID="${HA_AWS_ACCESS_KEY}"
        export AWS_SECRET_ACCESS_KEY="${HA_AWS_SECRET_KEY}"
        export HA_AWS_S3_SERVICE_ENDPOINT="${HA_AWS_S3_SERVICE_ENDPOINT}"
        export HA_AWS_S3_BUCKET="${HA_AWS_S3_BUCKET}"
        export VIDEO_NAME="${VIDEO_NAME}"
        export VIDEO_FORMAT="${VIDEO_FORMAT}"
        
        if /usr/local/bin/chunk-cleaner.sh "$VIDEO_ID"; then
          log_success "S3 chunks cleaned up successfully"
        else
          log_warn "Failed to cleanup some S3 chunks (non-critical - chunks preserved for manual cleanup)"
          # Don't fail the recording process if cleanup fails
        fi
      else
        log_warn "Final video too small (${final_size} bytes) - skipping S3 cleanup for safety"
        log_info "💡 S3 chunks preserved for manual recovery"
      fi
    else
      log_warn "Final video not found - skipping S3 cleanup for safety"
      log_info "💡 S3 chunks preserved for manual recovery"
    fi
    
    log_success "S3 chunk cleanup process completed"
  else
    log_info "💾 Local storage mode - no S3 cleanup needed"
  fi

  ### Clean up temporary analysis file ###
  
  if [[ "${DEBUG_MODE:-false}" == "true" ]]; then
    log_info "🐛 DEBUG_MODE enabled - preserving video.info file"
    
    # Copy debug files immediately while we're still in the main block
    log_info "🐛 Copying debug files..."
    [[ -f /tmp/container.log ]] && cp /tmp/container.log /recordings/$VIDEO_ID/$VIDEO_ID-container.log || log_warn "/tmp/container.log not found"
    [[ -f ~/.config/google-chrome/chrome_debug.log ]] && cp ~/.config/google-chrome/chrome_debug.log /recordings/$VIDEO_ID/chrome_debug.log || log_warn "Chrome debug log not found"
    log_info "🐛 Debug files copied"
  else
    log_info "🧹 Cleaning up temporary analysis file..."
    if [[ -f "/recordings/$VIDEO_ID/$VIDEO_ID.info" ]]; then
      rm -f "/recordings/$VIDEO_ID/$VIDEO_ID.info"
      log_success "video.info file removed (data preserved in .recording.$VIDEO_ID)"
    fi
  fi

  ### HA Controller - Cleanup Background Processes ###
  log_info "🧹 Cleaning up HA Controller background processes..."

  cleanup_ha_processes() {
    # Quick cleanup - kill processes immediately without waiting
    if [[ -f "/tmp/ha-manager-${VIDEO_ID}.pid" ]]; then
      HA_MANAGER_PID=$(cat "/tmp/ha-manager-${VIDEO_ID}.pid")
      if kill -0 "$HA_MANAGER_PID" 2>/dev/null; then
        log_info "🛑 Killing HA Manager (PID: $HA_MANAGER_PID)"
        kill -KILL "$HA_MANAGER_PID" 2>/dev/null || true
      fi
      rm -f "/tmp/ha-manager-${VIDEO_ID}.pid"
    fi
    
    # Kill any remaining HA processes quickly
    pkill -KILL -f "recorder-session-manager.sh.*$VIDEO_ID" 2>/dev/null || true
    pkill -KILL -f "session-register.sh.*$VIDEO_ID" 2>/dev/null || true
    
    log_success "🧹 HA Controller cleanup completed"
  }

  # Do HA cleanup in background while other tasks continue
  cleanup_ha_processes &

  ### Change permissions to all generated files ###

  sudo chmod -R 777 /recordings/$VIDEO_ID
  log_info "🔒 File permissions updated"

  log_success "🎉 Recording process completed for VIDEO_ID: $VIDEO_ID"

  exit 0

} 2>&1 | tee -a /tmp/container.log

# Final debug file copy (outside the tee block to avoid issues)
if [[ ${DEBUG_MODE} == "true" ]]; then
  # This is now redundant since we copy above, but keeping for safety
  log_info "🐛 Final debug check..."
fi

### Change permissions to all generated files ###
sudo chmod -R 777 /recordings/$VIDEO_ID

# Force exit to ensure container stops
exit 0