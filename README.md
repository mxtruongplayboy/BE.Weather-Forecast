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

## Bước 1 — Deploy Docker stack

```bash
# Trên máy dev — push repo lên git remote, sau đó pull về VPS
# (hoặc copy trực tiếp)
scp -r BE.Weather-Forecast/ user@vps:/opt/open-meteo-forecast/

# SSH lên VPS
ssh user@vps
cd /opt/open-meteo-forecast

# Khởi động stack
docker compose up -d

# Theo dõi download batch đầu (~15-30 phút, ~10-15 GB)
docker compose logs -f sync-gfs
```

Khi nào sẵn sàng: log thấy `serve started on 0.0.0.0:8080` từ container `omfc-api`.

Smoke test local:

```bash
curl 'http://127.0.0.1:8081/v1/forecast?latitude=10.77&longitude=106.7&hourly=temperature_2m,relative_humidity_2m'
```

Phải trả về JSON với `hourly.time[]`, `hourly.temperature_2m[]`, v.v.

## Bước 2 — nginx vhost + HTTPS

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

Smoke test public:

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
