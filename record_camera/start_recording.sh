#!/bin/bash

# Checking /media/sdcard is mounted
if ! mountpoint -q /media/sdcard; then
    echo "ERROR: The SD card has not been mounted /media/sdcard!" >&2
    exit 1
fi

# Check write permission
if ! [ -w /media/sdcard ]; then
    echo "ERROR: do not have permission write to SD card!" >&2
    exit 1
fi

# Get the directory where this script is located
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Use the script directory to locate config.json
CONFIG_FILE="${SCRIPT_DIR}/config.json"

# Function to read JSON values
get_json_value() {
    local key="$1"
    jq -r ".$key" "$CONFIG_FILE" 2>/dev/null
}

# Check config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: File $CONFIG_FILE not found!"
    exit 1
fi

# Read global settings
GLOBAL_LOG_PATH=$(get_json_value "global.logpath")
mkdir -p "$GLOBAL_LOG_PATH"

# Read cameras array
CAMERAS=$(jq -c '.cameras[]' "$CONFIG_FILE")
if [ -z "$CAMERAS" ]; then
    echo "ERROR: No cameras defined in config.json!"
    exit 1
fi

# Camera connection check function
check_camera_connection() {
    local uri="$1"
    timeout 5s ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$uri" > /dev/null 2>&1
    return $?
}

# FFmpeg recording function
start_ffmpeg() {
    local uri="$1"
    local segment_time="$2"
    local outpath="$3"
    local file_name="$4"
    local log_file="$5"
    local camera_name="$6"

    while true; do
        if ! check_camera_connection "$uri"; then
            echo "$(date +'%Y-%m-%d %H:%M:%S') - [$camera_name] ERROR: Cannot connect to camera. Retrying in 30s..." >> "$log_file"
            sleep 30
            continue
        fi

        echo "$(date +'%Y-%m-%d %H:%M:%S') - [$camera_name] Starting FFmpeg..." >> "$log_file"
        
        ffmpeg \
            -loglevel error \
            -rtsp_transport tcp \
            -i "$uri" \
            -c copy \
            -f segment \
            -segment_time "$segment_time" \
            -reset_timestamps 1 \
            -segment_format mp4 \
            -strftime 1 \
            "$outpath/$file_name" 2>> "$log_file"

        echo "$(date +'%Y-%m-%d %H:%M:%S') - [$camera_name] FFmpeg exited. Restarting in 10s..." >> "$log_file"
        sleep 10
    done
}

# Process each camera
echo "$CAMERAS" | while read -r camera; do
    # Parse parameters using jq
    uri=$(echo "$camera" | jq -r '.uri')
    segment_time=$(echo "$camera" | jq -r '.segment_time')
    outpath=$(echo "$camera" | jq -r '.outpath')
    file_name=$(echo "$camera" | jq -r '.file_name')
    camera_name=$(echo "$camera" | jq -r '.name')
    logpath=$GLOBAL_LOG_PATH

    # Create directories
    mkdir -p "$logpath"
    mkdir -p "$outpath"
    LOG_FILE="$logpath/${camera_name}_$(date +'%Y%m%d').log"

    # Start recording
    start_ffmpeg "$uri" "$segment_time" "$outpath" "$file_name" "$LOG_FILE" "$camera_name" &
done

wait
