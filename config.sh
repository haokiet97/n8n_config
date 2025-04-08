#!/bin/bash

# Script để nhập và export các biến môi trường

# Nhập giá trị cho biến CLOUDFLARE_TUNNEL_TOKEN
read -p "Nhập Cloudflare Tunnel Token (CLOUDFLARE_TUNNEL_TOKEN): " CLOUDFLARE_TUNNEL_TOKEN

# Nhập giá trị cho biến EXTERNAL_IP
read -p "Nhập Domain/External IP cho n8n callback url(Ví dụ: https://n8n.giapnv.io.com): " EXTERNAL_IP

# Export các biến
export CLOUDFLARE_TUNNEL_TOKEN="$CLOUDFLARE_TUNNEL_TOKEN"
export EXTERNAL_IP="$EXTERNAL_IP"

# Hiển thị thông báo thành công
echo "Đã export các biến môi trường"

# Ghi các biến vào file .env
cat > .env <<EOF
# Cloudflare
CLOUDFLARE_TUNNEL_TOKEN=$CLOUDFLARE_TUNNEL_TOKEN

# n8n Configuration
EXTERNAL_IP=$EXTERNAL_IP
EOF

# Hiển thị thông báo thành công
echo "Đã lưu các biến vào file .env:"
cat .env
source ./.env
