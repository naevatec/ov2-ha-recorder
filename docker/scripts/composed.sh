#!/bin/bash

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
  fi

  CHUNK_RECORDING_TYPE=${HA_RECORDING_STORAGE:-local} # May be "local" or "s3"
  CHUNK_FOLDER=${CHUNK_FOLDER:-/chunks}
  CHUNK_START=${START_CHUNK:-0000}
  CHUNK_TIME_SIZE=${CHUNK_TIME_SIZE:-10}              # In seconds
  CHUNK_RECORDING_DIR=/recordings/$VIDEO_ID/$CHUNK_FOLDER

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


  echo
  echo "============= Loaded Environment Variables ============="
  env
  echo "========================================================"
  echo

  ### Store Recording json data ###

  mkdir -p $CHUNK_RECORDING_DIR
  chmod -R 777 /recordings/$VIDEO_ID
  echo $RECORDING_JSON >/recordings/$VIDEO_ID/.recording.$VIDEO_ID

  ### Run headless Chrome ###

  source /headless-chrome.sh

  chmod 777 /recordings


  ### Evaluate chunk configuration ###
  # Get next index to use
  result=$(cd "$CHUNK_RECORDING_DIR" && echo $(ls ????.mp4 2>/dev/null || echo "$CHUNK_START") | sed 's/\w+.mp4//g' | sed 's/.mp4//g' | awk '{print $NF}' | sed 's/^0*//g')
  # Check if the result is empty
  if [[ -z "$result" ]]; then
      echo "[composed.sh] Result is empty. Setting default value to 0."
      result=0
  fi
  INDEX=$(printf %04d $(( 1 + $result)) )

  # Create a non empty file to avoid OpenVidu to stop the recording
  echo "Recording by chunks" > /recordings/$VIDEO_ID/$VIDEO_NAME.$VIDEO_FORMAT

  ### Start recording with ffmpeg ###

  if [[ "$ONLY_VIDEO" == true ]]; then
    # Do not record audio
    ffmpeg <./stop -y -f x11grab -draw_mouse 0 -framerate $FRAMERATE -video_size $RESOLUTION -i :$DISPLAY_NUM -c:v libx264 -preset ultrafast -crf 28 -refs 4 -qmin 4 -pix_fmt yuv420p -filter:v fps=$FRAMERATE "/recordings/$VIDEO_ID/$VIDEO_NAME.$VIDEO_FORMAT"
  else
    # Record audio  ("-f alsa -i pulse [...] -c:a aac")
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

  # If CHUNK_RECORDING_TYPE is "local", just join the chunks
  if [ "$CHUNK_RECORDING_TYPE" == "local" ]; then
    # Join all chunks into a single file
    if [[ -d "$CHUNK_RECORDING_DIR" ]]; then
      echo "[composed.sh] Joining chunks in $CHUNK_RECORDING_DIR"
      ffmpeg -y -f concat -safe 0 -i <(for f in "$CHUNK_RECORDING_DIR"/*.mp4; do echo "file '$PWD/$f'"; done) -c copy "/recordings/$VIDEO_ID/$VIDEO_NAME.$VIDEO_FORMAT"
      # Remove chunks after joining
      rm -rf "$CHUNK_RECORDING_DIR"
    else
      echo "[composed.sh] Directory $CHUNK_RECORDING_DIR does not exist."
    fi
  fi


  ### Generate video report file ###
  ffprobe -v quiet -print_format json -show_format -show_streams /recordings/$VIDEO_ID/$VIDEO_NAME.$VIDEO_FORMAT >/recordings/$VIDEO_ID/$VIDEO_ID.info

  ### Update Recording json data ###

  TMP=$(mktemp /recordings/$VIDEO_ID/.$VIDEO_ID.XXXXXXXXXXXXXXXXXXXXXXX.json)
  INFO=$(cat /recordings/$VIDEO_ID/$VIDEO_ID.info | jq '.')
  HAS_AUDIO_AUX=$(echo $INFO | jq '.streams[] | select(.codec_type == "audio")')
  if [ -z "$HAS_AUDIO_AUX" ]; then HAS_AUDIO=false; else HAS_AUDIO=true; fi
  HAS_VIDEO_AUX=$(echo $INFO | jq '.streams[] | select(.codec_type == "video")')
  if [ -z "$HAS_VIDEO_AUX" ]; then HAS_VIDEO=false; else HAS_VIDEO=true; fi
  SIZE=$(echo $INFO | jq '.format.size | tonumber')
  DURATION=$(echo $INFO | jq '.format.duration | tonumber')

  if [[ "$HAS_AUDIO" == false && "$HAS_VIDEO" == false ]]; then
    STATUS="failed"
  else
    STATUS="stopped"
  fi

  jq -c -r ".hasAudio=$HAS_AUDIO | .hasVideo=$HAS_VIDEO | .duration=$DURATION | .size=$SIZE | .status=\"$STATUS\"" "/recordings/$VIDEO_ID/.recording.$VIDEO_ID" >$TMP && mv $TMP /recordings/$VIDEO_ID/.recording.$VIDEO_ID

  ### Generate video thumbnail ###

  MIDDLE_TIME=$(ffmpeg -i /recordings/$VIDEO_ID/$VIDEO_NAME.$VIDEO_FORMAT 2>&1 | grep Duration | awk '{print $2}' | tr -d , | awk -F ':' '{print ($3+$2*60+$1*3600)/2}')
  THUMBNAIL_HEIGHT=$((480 * $HEIGHT / $WIDTH))
  ffmpeg -ss $MIDDLE_TIME -i /recordings/$VIDEO_ID/$VIDEO_NAME.$VIDEO_FORMAT -vframes 1 -s 480x$THUMBNAIL_HEIGHT /recordings/$VIDEO_ID/$VIDEO_ID.jpg

  ### Change permissions to all generated files ###

  sudo chmod -R 777 /recordings/$VIDEO_ID

} 2>&1 | tee -a /tmp/container.log

if [[ ${DEBUG_MODE} == "true" ]]; then
  [[ -f /tmp/container.log ]] && cp /tmp/container.log /recordings/$VIDEO_ID/$VIDEO_ID-container.log || echo "/tmp/container.log not found"
  [[ -f ~/.config/google-chrome/chrome_debug.log ]] && cp ~/.config/google-chrome/chrome_debug.log /recordings/$VIDEO_ID/chrome_debug.log || echo "~/.config/google-chrome/chrome_debug.log"
fi

### Change permissions to all generated files ###
sudo chmod -R 777 /recordings/$VIDEO_ID
