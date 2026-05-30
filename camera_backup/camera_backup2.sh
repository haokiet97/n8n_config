#!/bin/bash

# Cấu hình
# Get the directory where this script is located
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Use the script directory to locate config.json
CONFIG_FILE="${SCRIPT_DIR}/config.json"
BOT_TOKEN=$(jq -r '.bot_token' "$CONFIG_FILE")

# Hàm lấy thời gian cho pattern từ go2rtc
get_time_variables() {
    local current_hour=$(date +%H)
    local current_day=$(date +%d)
    local current_month=$(date +%m)
    local current_year=$(date +%Y)

    # Điều chỉnh giờ và ngày cho file ghi từ go2rtc
    # File có dạng: 20260515_142530.mp4 (năm tháng ngày_giờ phút giây)
    if [ "$current_hour" = "00" ]; then
        adjusted_day=$((10#$current_day - 1))
        adjusted_day=$(printf "%02d" $adjusted_day)
    else
        adjusted_day="$current_day"
    fi

    # Lấy giờ hiện tại (không điều chỉnh cho go2rtc)
    current_hour_padded=$(printf "%02d" $((10#$current_hour)))
    
    echo "$current_year $current_month $adjusted_day $current_hour_padded"
}

# Hàm quét và gửi file cho go2rtc recording
process_camera() {
    local camera_name="$1"
    local outpath="$2"
    local telegram_chat_id="$3"
    local message_thread_id="$4"

    # Lấy thời gian
    read current_year current_month adjusted_day current_hour <<< $(get_time_variables)

    # Pattern tìm file cho go2rtc (dạng: YYYYMMDD_HHMMSS.mp4)
    local pattern="output_${current_year}${current_month}${adjusted_day}_"
    
    echo "========================================="
    echo "Processing camera: $camera_name"
    echo "Looking for files in: $outpath"
    echo "Pattern: $pattern"
    echo "Current time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "========================================="

    # Tìm các file phù hợp với pattern (trong giờ hiện tại)
    local files=()
    while IFS= read -r -d '' file; do
        files+=("$file")
    done < <(find "$outpath" -maxdepth 1 -type f -name "*${pattern}*.mp4" -print0 2>/dev/null | sort -z)

    # Kiểm tra có file không
    if [ ${#files[@]} -eq 0 ]; then
        echo "No files found for pattern: $pattern"
        echo "Files in directory:"
        ls -la "$outpath" 2>/dev/null || echo "Cannot list directory"
        return
    fi

    echo "Found ${#files[@]} files to process"

    # Xử lý từng file
    for file_path in "${files[@]}"; do
        local filename=$(basename "$file_path")
        local file_size=$(stat -c%s "$file_path" 2>/dev/null || stat -f%z "$file_path" 2>/dev/null)
        local file_date=$(echo "$filename" | grep -oP '^\d{8}_\d{6}' || echo "unknown")

        echo "---"
        echo "Processing file: $filename"
        echo "Size: $((file_size / 1024 / 1024)) MB"
        echo "Recording time: $file_date"

        # Kiểm tra file có đang được ghi không (tránh gửi file đang ghi dở)
        if lsof "$file_path" 2>/dev/null | grep -q "ffmpeg"; then
            echo "WARNING: File is being written, skipping..."
            continue
        fi

        # Gửi file lên Telegram
        echo "Sending to Telegram..."

        # Sử dụng curl để gửi video
        response=$(curl -s -w "\n%{http_code}" -X POST \
            -H "Content-Type: multipart/form-data" \
            -F "chat_id=$telegram_chat_id" \
            ${message_thread_id:+-F "message_thread_id=$message_thread_id"} \
            -F "video=@$file_path" \
            -F "caption=📹 $camera_name - $filename" \
            -F "duration=180" \
            -F "supports_streaming=true" \
            -F "disable_notification=true" \
            "https://api.telegram.org/bot$BOT_TOKEN/sendVideo" 2>&1)

        # Tách response code và body
        http_code=$(echo "$response" | tail -n1)
        response_body=$(echo "$response" | sed '$d')

        # Kiểm tra kết quả
        if [ "$http_code" = "200" ] && echo "$response_body" | grep -q '"ok":true'; then
            echo "✓ Successfully sent: $filename"
            
            # Xóa file sau khi gửi thành công
            echo "Deleting file: $file_path"
            if rm -f "$file_path"; then
                echo "✓ File deleted successfully"
            else
                echo "✗ Warning: Failed to delete file"
            fi
        else
            echo "✗ Failed to send: $filename"
            echo "HTTP Code: $http_code"
            echo "Response: $response_body"
        fi
        
        sleep 2 # Đợi 2 giây giữa các file
    done
}

# Hàm chính
main() {
    echo "========================================="
    echo "Starting camera backup process..."
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "========================================="

    # Đọc cấu hình từ file JSON
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Error: Config file not found: $CONFIG_FILE"
        exit 1
    fi

    # Kiểm tra bot token
    if [ -z "$BOT_TOKEN" ] || [ "$BOT_TOKEN" = "null" ]; then
        echo "Error: Bot token not found in config file"
        exit 1
    fi

    # Kiểm tra jq
    if ! command -v jq &> /dev/null; then
        echo "Error: jq is not installed. Please install: apt-get install jq"
        exit 1
    fi

    # Đọc danh sách cameras
    cameras=$(jq -c '.cameras[]' "$CONFIG_FILE" 2>/dev/null)

    if [ -z "$cameras" ] || [ "$cameras" = "null" ]; then
        echo "Error: No cameras found in config file"
        exit 1
    fi

    # Xử lý từng camera
    echo "$cameras" | while IFS= read -r camera; do
        name=$(echo "$camera" | jq -r '.name // empty')
        outpath=$(echo "$camera" | jq -r '.outpath // empty')
        telegram_chat_id=$(echo "$camera" | jq -r '.telegram_chat_id // empty')
        message_thread_id=$(echo "$camera" | jq -r '.message_thread_id // empty')

        # Kiểm tra thông tin camera
        if [ -n "$name" ] && [ -n "$outpath" ] && [ -n "$telegram_chat_id" ]; then
            process_camera "$name" "$outpath" "$telegram_chat_id" "$message_thread_id"
        else
            echo "Skipping camera due to missing information:"
            echo "  Name: $name"
            echo "  Outpath: $outpath"
            echo "  Chat ID: $telegram_chat_id"
        fi
        echo ""
    done

    echo "========================================="
    echo "Process completed at: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "========================================="
}

# Script để chạy theo lịch (crontab)
run_scheduled() {
    # Lấy thời gian hiện tại
    current_minute=$(date +%M)

    # Chạy mỗi 5 phút một lần
    if [ $((10#$current_minute % 5)) -eq 0 ]; then
        echo "Running scheduled backup at $(date)"
        main >> /var/log/camera_backup.log 2>&1
    else
        # Debug: echo "Not time to run yet. Current time: $(date)"
        :
    fi
}

# Chọn chế độ chạy
case "${1:-}" in
    "scheduled")
        run_scheduled
        ;;
    "manual"|"")
        main
        ;;
    "test")
        echo "Test mode - showing variables:"
        get_time_variables
        echo "Bot token exists: $( [ -n "$BOT_TOKEN" ] && echo "Yes" || echo "No" )"
        echo "Config file: $CONFIG_FILE"
        echo "Config content:"
        cat "$CONFIG_FILE" | jq '.' 2>/dev/null || cat "$CONFIG_FILE"
        ;;
    *)
        echo "Usage: $0 [scheduled|manual|test]"
        echo "  scheduled - Run in scheduled mode (every 5 minutes)"
        echo "  manual    - Run immediately (default)"
        echo "  test      - Test configuration"
        exit 1
        ;;
esac
