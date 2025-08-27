#!/bin/bash -x

### Use container as a single headless chrome ###

if [ "$HEADLESS_CHROME_ONLY" == true ]; then
    google-chrome --no-sandbox --headless --remote-debugging-port=$HEADLESS_CHROME_PORT  &> /chrome.log &
    sleep 100000000
else
  ### Use container as OpenVidu recording module ###

  # For ov2-ha-recoreder, the mode will be COMPOSED always
  CONTAINER_WORKING_MODE=${CONTAINER_WORKING_MODE:-COMPOSED}

  ./composed.sh

fi