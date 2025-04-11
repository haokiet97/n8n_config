#!/bin/bash

# Tên file service
SERVICE_FILE="docker-compose-n8n.service"

# Lấy đường dẫn tuyệt đối của thư mục chứa script hiện tại
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Nội dung file service
SERVICE_CONTENT="[Unit]
Description=Docker Compose N8N Stack
Requires=docker.service
After=docker.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
RemainAfterExit=yes
User=root          # ← Ensures service runs as root
Group=root         # ← Optional, but explicit
WorkingDirectory=$SCRIPT_DIR
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=300
Restart=on-failure

[Install]
WantedBy=multi-user.target"

# Ghi nội dung vào file
echo "$SERVICE_CONTENT" | tee "/etc/systemd/system/$SERVICE_FILE" > /dev/null

# Thông báo kết quả
if [ $? -eq 0 ]; then
    systemctl enable docker
    echo "Đã tạo file service thành công tại /etc/systemd/system/$SERVICE_FILE"
    echo "các bước tiếp theo:"
    echo "1. Reload systemd: systemctl daemon-reload"
    systemctl daemon-reload
    echo "2. Kích hoạt service: systemctl enable $SERVICE_FILE"
    systemctl enable $SERVICE_FILE
    echo "3. Khởi động service: systemctl start $SERVICE_FILE"
    systemctl start $SERVICE_FILE
else
    echo "Có lỗi xảy ra khi tạo file service"
    exit 1
fi
