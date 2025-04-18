#!/bin/bash

CONFIG_FILE="config.yaml"

# Hàm kiểm tra kết nối camera
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
            -reconnect 1 \
            -reconnect_at_eof 1 \
            -reconnect_streamed 1 \
            -reconnect_delay_max 5 \
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

# Đọc cấu hình toàn cục
GLOBAL_LOG_PATH=$(yq e '.global.logpath' "$CONFIG_FILE")
mkdir -p "$GLOBAL_LOG_PATH"

# Xử lý từng camera
yq e '.cameras[]' "$CONFIG_FILE" | while read -r camera; do
    # Parse thông số
    uri=$(echo "$camera" | yq e '.uri' -)
    segment_time=$(echo "$camera" | yq e '.segment_time' -)
    outpath=$(echo "$camera" | yq e '.outpath' -)
    file_name=$(echo "$camera" | yq e '.file_name' -)
    camera_name=$(echo "$camera" | yq e '.name' -)
    
    # Xác định thư mục log (ưu tiên cấu hình camera nếu có)
    camera_logpath=$(echo "$camera" | yq e '.logpath' -)
    logpath="${camera_logpath:-$GLOBAL_LOG_PATH}"
    mkdir -p "$logpath"
    
    # Tạo file log
    log_file="${logpath}/${camera_name}_$(date +'%Y%m%d').log"
    
    # Khởi chạy
    mkdir -p "$outpath"
    start_ffmpeg "$uri" "$segment_time" "$outpath" "$file_name" "$log_file" "$camera_name" &
done

wait
