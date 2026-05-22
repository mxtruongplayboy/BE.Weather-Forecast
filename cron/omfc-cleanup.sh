#!/bin/bash
# Cleanup Open-Meteo Forecast BE rolling cache.
#
# Cài đặt (chạy mỗi giờ qua crontab):
#   sudo cp omfc-cleanup.sh /usr/local/bin/omfc-cleanup
#   sudo chmod +x /usr/local/bin/omfc-cleanup
#   sudo crontab -e
#     → thêm dòng: 0 * * * * /usr/local/bin/omfc-cleanup
#
# Giữ 1 ngày run gần nhất — đủ để drain in-flight request + detect corrupt file.
# Chạy mỗi giờ nên disk chỉ giữ ~1 run (~10-15 GB) thay vì tích lũy nhiều run.
# KHÔNG đụng đến tile-server (chỉ exec vào container omfc-api).

set -euo pipefail

LOG=/var/log/omfc-cleanup.log
echo "[$(date -Iseconds)] omfc-cleanup start" >> "$LOG"

# Verify container đang chạy
if ! docker ps --format '{{.Names}}' | grep -q '^omfc-api$'; then
    echo "[$(date -Iseconds)] omfc-api container not running, skip" >> "$LOG"
    exit 0
fi

# Open-Meteo CLI cleanup
docker exec omfc-api /app/openmeteo-api delete-old-runs --keep-days 1 \
    2>&1 | tee -a "$LOG"

# Cảnh báo nếu vượt 25GB (1 run ~10-15GB, buffer x1.5)
DATA_DIR=/opt/open-meteo-forecast/data
if [ -d "$DATA_DIR" ]; then
    USED_GB=$(du -sBG "$DATA_DIR" | awk '{print $1}' | sed 's/G//')
    echo "[$(date -Iseconds)] data size: ${USED_GB}G" >> "$LOG"
    if [ "$USED_GB" -gt 25 ]; then
        echo "[$(date -Iseconds)] WARNING: data size > 25GB" >> "$LOG"
        # Optional: gửi alert qua email / Telegram / Slack
    fi
fi

echo "[$(date -Iseconds)] omfc-cleanup done" >> "$LOG"
