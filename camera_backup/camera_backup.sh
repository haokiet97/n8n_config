#!/bin/bash

# Cấu hình
# Get the directory where this script is located
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Use the script directory to locate config.json
CONFIG_FILE="${SCRIPT_DIR}/config.json"
BOT_TOKEN=$(jq -r '.bot_token' "$CONFIG_FILE")

# Hàm lấy thời gian
get_time_variables() {
    local current_hour=$(date +%H)
    local current_day=$(date +%d)
    local current_month=$(date +%m)
    local current_year=$(date +%Y)

    # Điều chỉnh giờ và ngày giống như trong n8n flow
    if [ "$current_hour" = "00" ]; then
        adjusted_day=$((10#$current_day - 1))
        adjusted_day=$(printf "%02d" $adjusted_day)
    else
        adjusted_day="$current_day"
    fi

    # Điều chỉnh giờ (giờ trước đó)
    adjusted_hour=$(( (10#$current_hour - 1 + 24) % 24 ))
    adjusted_hour=$(printf "%02d" $adjusted_hour)

    echo "$current_year $current_month $adjusted_day $adjusted_hour"
}

# Hàm quét và gửi file
process_camera() {
    local camera_name="$1"
    local outpath="$2"
    local telegram_chat_id="$3"
    local message_thread_id="$4"

    # Lấy thời gian đã điều chỉnh
    read current_year current_month adjusted_day adjusted_hour <<< $(get_time_variables)

    # Pattern tìm file (giống như trong n8n)
    local dt_pattern="output_${current_year}${current_month}${adjusted_day}_${adjusted_hour}*"
    local pattern="output_"
    local max_filename = "${dt_pattern}5959"
    echo "Processing camera: $camera_name"
    echo "Looking for files in: $outpath"
    echo "Pattern: $pattern"

    # Tìm các file phù hợp
    local files=()
    while IFS= read -r -d '' file; do
        filename=$(basename "$file")
        if [[ "$max_filename" >= "$filename" ]]; then
            files+=("$file")
        fi
        
    done < <(find "$outpath" -maxdepth 1 -type f -name "*${pattern}*" -print0 2>/dev/null)

    # Kiểm tra có file không
    if [ ${#files[@]} -eq 0 ]; then
        echo "No files found for pattern: $pattern"
        return
    fi

    echo "Found ${#files[@]} files to process"

    # Xử lý từng file
    for file_path in "${files[@]}"; do
        local filename=$(basename "$file_path")
        local file_size=$(stat -c%s "$file_path" 2>/dev/null || stat -f%z "$file_path" 2>/dev/null)

        echo "Processing file: $filename (Size: $file_size bytes)"

        # Gửi file lên Telegram
        echo "Sending to Telegram (chat_id: $telegram_chat_id, thread_id: $message_thread_id)..."

        # Sử dụng curl để gửi video
        response=$(curl -s -X POST \
            -H "Content-Type: multipart/form-data" \
            -F "chat_id=$telegram_chat_id" \
            -F "message_thread_id=$message_thread_id" \
            -F "video=@$file_path" \
            -F "duration=240" \
            -F "caption=$filename" \
            -F "supports_streaming=true" \
            -F "disable_notification=true" \
            "https://api.telegram.org/bot$BOT_TOKEN/sendVideo")

        # Kiểm tra kết quả
        if echo "$response" | grep -q '"ok":true'; then
            echo "Successfully sent: $filename"

            # Xóa file sau khi gửi thành công (tùy chọn)
            echo "Deleting file: $file_path"
            rm -f "$file_path"

            # Kiểm tra xem file có tồn tại không sau khi xóa
            if [ ! -f "$file_path" ]; then
                echo "File deleted successfully"
            else
                echo "Warning: Failed to delete file"
            fi
        else
            echo "Failed to send: $filename"
            echo "Response: $response"
        fi

        echo "---"
        sleep 1 # Đợi 1 giây giữa các file
    done
}

# Hàm chính
main() {
    echo "Starting camera backup process..."
    echo "Timestamp: $(date)"

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

    # Đọc danh sách cameras
    cameras=$(jq -c '.cameras[]' "$CONFIG_FILE")

    if [ -z "$cameras" ]; then
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
            echo "Skipping camera due to missing information: $camera"
        fi
    done

    echo "Process completed at: $(date)"
}

# Script để chạy theo lịch (crontab)
run_scheduled() {
    # Lấy thời gian hiện tại
    current_minute=$(date +%M)
    current_hour=$(date +%H)

    # Chạy vào phút thứ 5 mỗi giờ (giống n8n flow)
    if [ "$current_minute" = "05" ]; then
        echo "Running scheduled backup at $(date)"
        main >> /var/log/camera_backup.log 2>&1
    else
        echo "Not time to run yet. Current time: $(date)"
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
        # Chế độ test - chỉ hiển thị thông tin
        echo "Test mode - showing variables:"
        get_time_variables
        echo "Bot token exists: $( [ -n "$BOT_TOKEN" ] && echo "Yes" || echo "No" )"
        ;;
    *)
        echo "Usage: $0 [scheduled|manual|test]"
        echo "  scheduled - Run in scheduled mode (check time)"
        echo "  manual    - Run immediately (default)"
        echo "  test      - Test configuration"
        exit 1
        ;;
esac
