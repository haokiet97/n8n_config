#!/bin/bash
# Get the directory where this script is located
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Use the script directory to locate config.yaml
CONFIG_FILE="${SCRIPT_DIR}/config.yaml"

# Hàm đọc YAML cho yq-jq wrapper
get_yaml_value() {
    local key="$1"
    yq -y ".$key" "$CONFIG_FILE" 2>/dev/null
}

# Kiểm tra file config
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: File $CONFIG_FILE not found!"
    exit 1
fi

# Đọc thông số toàn cục
GLOBAL_LOG_PATH=$(get_yaml_value "global.logpath" | head -n 1)
mkdir -p "$GLOBAL_LOG_PATH"

# Đọc danh sách cameras (sử dụng jq filter trực tiếp)
CAMERAS=$(yq -j '.' "$CONFIG_FILE" | jq -c '.cameras[]')
if [ -z "$CAMERAS" ]; then
    echo "ERROR: No cameras defined in config.yaml!"
    exit 1
fi

#Hàm kiểm tra kết nối camera
check_camera_connection() {
    local uri="$1"
    timeout 5s ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$uri" > /dev/null 2>&1
    return $?
}

# Hàm ghi hình
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


# Xử lý từng camera
# Xử lý từng camera
echo "$CAMERAS" | while read -r camera; do
    # Parse thông số dùng jq
    uri=$(echo "$camera" | jq -r '.uri')
    segment_time=$(echo "$camera" | jq -r '.segment_time')
    outpath=$(echo "$camera" | jq -r '.outpath')
    file_name=$(echo "$camera" | jq -r '.file_name')
    camera_name=$(echo "$camera" | jq -r '.name')
    logpath=$GLOBAL_LOG_PATH

    # Tạo thư mục
    mkdir -p "$logpath"
    mkdir -p "$outpath"
    LOG_FILE="$logpath/${camera_name}_$(date +'%Y%m%d').log"

    # Khởi chạy
    start_ffmpeg "$uri" "$segment_time" "$outpath" "$file_name" "$LOG_FILE" "$camera_name" &
done

wait
