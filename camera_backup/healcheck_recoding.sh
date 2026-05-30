#!/bin/bash
# healcheck_recording.sh

STREAM_NAME="record_tro_1_main"
GO2RTC_URL="http://0.0.0.0:1984"

# Cách 1: Gọi API để tạo producer bằng cách lấy thông tin stream
check_and_restart() {
    echo "Checking stream: $STREAM_NAME"
    
    # Gọi API để lấy thông tin stream, việc này sẽ kích hoạt producer nếu chưa có
    response=$(curl -s "${GO2RTC_URL}/api/streams?src=${STREAM_NAME}")
    
    # Kiểm tra xem có producer nào không
    if echo "$response" | grep -q '"producers":\[\]'; then
        echo "No producer found, restarting stream via API..."
        
        # Xóa stream config (tùy chọn)
        curl -s -X DELETE "${GO2RTC_URL}/api/streams?src=${STREAM_NAME}"
        sleep 2
        
        # Reload config để stream được tạo lại
        curl -s -X POST "${GO2RTC_URL}/api/restart"
        
        echo "Stream restarted"
    else
        echo "Stream is active"
    fi
}

check_and_restart
