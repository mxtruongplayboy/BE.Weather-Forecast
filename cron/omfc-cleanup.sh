#!/bin/bash
# Cleanup Open-Meteo Forecast BE rolling cache.
#
# Cài đặt:
#   sudo cp omfc-cleanup.sh /etc/cron.weekly/omfc-cleanup
#   sudo chmod +x /etc/cron.weekly/omfc-cleanup
#
# Chạy hàng tuần qua /etc/cron.weekly (chủ nhật 6h sáng theo default Debian/Ubuntu).
# Giữ 3 ngày run gần nhất cho mỗi model — xóa run cũ hơn.
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
docker exec omfc-api /app/openmeteo-api delete-old-runs --keep-days 3 \
    2>&1 | tee -a "$LOG"

# Optional: hard limit disk usage — nếu vượt 40GB thì cảnh báo
DATA_DIR=/opt/open-meteo-forecast/data
if [ -d "$DATA_DIR" ]; then
    USED_GB=$(du -sBG "$DATA_DIR" | awk '{print $1}' | sed 's/G//')
    echo "[$(date -Iseconds)] data size: ${USED_GB}G" >> "$LOG"
    if [ "$USED_GB" -gt 40 ]; then
        echo "[$(date -Iseconds)] WARNING: data size > 40GB" >> "$LOG"
        # Optional: gửi alert qua email / Telegram / Slack
    fi
fi

echo "[$(date -Iseconds)] omfc-cleanup done" >> "$LOG"
