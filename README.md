# BE.Weather-Forecast

Backend self-host cho tab **Dự báo** của app NOAA Weather (mobile repo
`noaa_weather/`). Triển khai **Open-Meteo Docker** (AGPL-3.0) để xử lý NOAA
GFS + ECMWF + CAMS thành JSON API.

Repo này nằm **cùng cấp** với:
- `noaa_weather/`        — Flutter mobile app
- `BE.Weather-Tiles/`    — Backend xử lý tiles cho tab Map
- `BE.Weather-Forecast/` — **REPO NÀY** — Backend forecast/AQI/geocoding

**Tách biệt hoàn toàn** với `BE.Weather-Tiles`: riêng repo, riêng Docker
stack, riêng nginx vhost, riêng cron, riêng SSL cert. Có thể deploy chung
VPS hoặc khác VPS — không phụ thuộc lẫn nhau.

## Deploy target hiện tại

- **VPS**: `206.72.200.120` (cùng host với BE.Weather-Tiles)
- **Host port**: `6970` (tile-BE đang ở `6969`)
- **Admin UI**: tab `Forecast BE` trong `http://206.72.200.120:6969/admin/`
  → admin BE đã có proxy endpoints `/api/v1/admin/forecast/*` gọi xuống stack này.
- **Deploy folder**: `/opt/open-meteo-forecast/` trên VPS

## Tại sao stack này?

| Tiêu chí | Giá trị |
|---|---|
| **License code** | AGPL-3.0 — commercial OK, deploy nguyên image = không cần public source |
| **License data** | NOAA GFS (public domain) + ECMWF/DWD/CAMS (CC BY 4.0) — đã có attribution trong app |
| **Chi phí** | $0 ongoing (dùng VPS hiện có) + ~30GB bandwidth/tháng download GRIB2 |
| **Limit** | Không có (tự host) — nginx rate-limit chặn abuse bên ngoài |
| **Maintenance** | Pull image mỗi 3 tháng (hoặc bật watchtower) |
| **Battle-tested** | Cùng codebase với `api.open-meteo.com` production |

## Yêu cầu

- VPS Linux (Debian/Ubuntu khuyến nghị) đã có Docker + Docker Compose v2 + nginx + certbot.
- Subdomain trỏ về VPS, vd `forecast-api.yourdomain.com`.
- ~30GB disk trống cho GRIB2 rolling cache.
- ~4GB RAM tăng thêm cho VPS.

## Cấu trúc repo

```
BE.Weather-Forecast/
├── docker-compose.yml           # Stack Open-Meteo (api + sync-gfs/ecmwf/aqi)
├── nginx/
│   └── forecast-api.conf        # vhost mẫu với rate-limit + cache
├── cron/
│   └── omfc-cleanup.sh          # Cleanup runs cũ hàng tuần
├── .gitignore                   # bỏ qua data/ + log
└── README.md                    # File này
```

## Bước 1 — Deploy Docker stack lên VPS 206.72.200.120

```bash
# Trên máy dev — copy repo lên VPS
scp -r BE.Weather-Forecast/ user@206.72.200.120:/opt/open-meteo-forecast/

# SSH lên VPS
ssh user@206.72.200.120
cd /opt/open-meteo-forecast

# Khởi động stack (4 containers: api + sync-gfs + sync-ecmwf + sync-aqi)
docker compose up -d

# Theo dõi download batch đầu (~15-30 phút, ~10-15 GB)
docker compose logs -f sync-gfs
```

Khi nào sẵn sàng: log thấy `serve started on 0.0.0.0:8080` từ container `omfc-api`.

Smoke test trực tiếp (port 6970 đã publish ra host):

```bash
# Từ VPS hoặc bất kỳ máy nào có route đến 206.72.200.120
curl 'http://206.72.200.120:6970/v1/forecast?latitude=10.77&longitude=106.7&hourly=temperature_2m,relative_humidity_2m'
```

Phải trả về JSON với `hourly.time[]`, `hourly.temperature_2m[]`, v.v.

## Bước 2 — Cập nhật tile-BE để admin có thể gọi Forecast BE

Admin UI ở `http://206.72.200.120:6969/admin/` (tile-BE) có tab `Forecast BE`
mới — gọi đến Forecast BE qua `host.docker.internal:6970`. Linux Docker cần
khai báo `extra_hosts` trong tile-BE để resolve hostname này:

```bash
# Trên VPS, vào folder tile-BE
cd /opt/<đường-dẫn-tile-BE>

# Đã có sẵn trong docker-compose.yml (đã commit):
#   extra_hosts:
#     - "host.docker.internal:host-gateway"

# Restart tile-BE để áp dụng
docker compose up -d
```

Verify từ tile-BE container có gọi được Forecast BE:

```bash
docker exec noaa_be wget -qO- 'http://host.docker.internal:6970/v1/forecast?latitude=10.77&longitude=106.7&current=temperature_2m'
```

Mở admin UI → tab **Forecast BE** → click **Refresh** → badge phải hiện **Online**.

## Bước 3 — (Tùy chọn) nginx vhost + HTTPS cho mobile app

App mobile có thể gọi trực tiếp `http://206.72.200.120:6970/v1/...` (HTTP),
nhưng cho production khuyến nghị có HTTPS vhost riêng:

```bash
# Edit forecast-api.conf, đổi `forecast-api.yourdomain.com` thành subdomain thật
sudo nano /opt/open-meteo-forecast/nginx/forecast-api.conf

# Copy vào nginx sites
sudo cp /opt/open-meteo-forecast/nginx/forecast-api.conf \
        /etc/nginx/sites-available/

sudo ln -s /etc/nginx/sites-available/forecast-api.conf \
           /etc/nginx/sites-enabled/

# Lấy cert Let's Encrypt
sudo certbot --nginx -d forecast-api.yourdomain.com

# Test + reload
sudo nginx -t
sudo systemctl reload nginx
```

Smoke test public HTTPS:

```bash
curl 'https://forecast-api.yourdomain.com/v1/forecast?latitude=10.77&longitude=106.7&current=temperature_2m'
```

## Bước 3 — Cleanup cron

```bash
sudo cp /opt/open-meteo-forecast/cron/omfc-cleanup.sh /etc/cron.weekly/omfc-cleanup
sudo chmod +x /etc/cron.weekly/omfc-cleanup

# Chạy thử ngay
sudo /etc/cron.weekly/omfc-cleanup
tail /var/log/omfc-cleanup.log
```

## Bước 4 — Đổi `.env` của Flutter app

Trong file `.env` của repo Flutter (KHÔNG commit lên git):

**Option A — HTTP trực tiếp đến VPS (đơn giản, dùng cho dev/staging):**

```env
OPEN_METEO_FORECAST_URL=http://206.72.200.120:6970/v1
OPEN_METEO_AIR_QUALITY_URL=http://206.72.200.120:6970/v1
OPEN_METEO_GEOCODING_URL=http://206.72.200.120:6970/v1
```

⚠️ Android 9+ chặn HTTP cleartext mặc định — cần thêm
`android:usesCleartextTraffic="true"` vào AndroidManifest. Hiện code đã set
`true` trong `noaa_weather/android/app/src/main/AndroidManifest.xml`.

**Option B — HTTPS qua nginx vhost (production):**

```env
OPEN_METEO_FORECAST_URL=https://forecast-api.yourdomain.com/v1
OPEN_METEO_AIR_QUALITY_URL=https://forecast-api.yourdomain.com/v1
OPEN_METEO_GEOCODING_URL=https://forecast-api.yourdomain.com/v1
```

Build lại app:

```bash
flutter clean
flutter pub get
flutter build apk --release   # hoặc ipa
```

Test trên thiết bị thật — mở tab Dự báo → Talker log phải thấy gọi
`forecast-api.yourdomain.com` thay vì `api.open-meteo.com`.

## Verify cách ly với tile-server

```bash
# Dừng forecast BE → tile-server vẫn chạy
docker stop omfc-api
docker ps   # tile-server containers vẫn UP

# Khởi động lại
docker start omfc-api

# Dừng tile-server → forecast BE vẫn chạy
docker stop <tile-container-names>
curl https://forecast-api.yourdomain.com/v1/forecast?...   # vẫn OK
```

## Monitoring

Khuyến nghị setup health check ngoài VPS (free):

- [UptimeRobot](https://uptimerobot.com/) — 50 monitors free, 5 phút interval.
- [Healthchecks.io](https://healthchecks.io/) — 20 checks free.

Health check URL:

```
https://forecast-api.yourdomain.com/v1/forecast?latitude=10.77&longitude=106.7&current=temperature_2m
```

Pass condition: HTTP 200 + JSON body chứa `current.temperature_2m`.

## Cập nhật image

3 tháng/lần (hoặc bật watchtower trong `docker-compose.yml`):

```bash
cd /opt/open-meteo-forecast
docker compose pull
docker compose up -d
```

## Rollback

Nếu self-host gặp sự cố, switch app về public Open-Meteo:

```env
# Trong .env của app — để trống = fallback về public
OPEN_METEO_FORECAST_URL=
OPEN_METEO_AIR_QUALITY_URL=
OPEN_METEO_GEOCODING_URL=
```

Rebuild app + emergency release. **Lưu ý**: public Open-Meteo terms cấm
commercial — chỉ dùng tạm để khôi phục service, fix self-host ASAP.

## Tham khảo

- [Open-Meteo GitHub](https://github.com/open-meteo/open-meteo) — source code AGPL-3.0
- [Open-Meteo Docker docs](https://github.com/open-meteo/open-meteo/blob/main/docker.md)
- [NOAA NOMADS](https://nomads.ncep.noaa.gov/) — nguồn GFS GRIB2 underlying
- [ECMWF Open Data](https://www.ecmwf.int/en/forecasts/datasets/open-data) — nguồn IFS underlying
- [CAMS](https://atmosphere.copernicus.eu/) — nguồn Air Quality
