# Security Policy — BE.Weather-Forecast

Open-Meteo self-host wrapper. Image: `ghcr.io/open-meteo/open-meteo:latest`.

## Sensitive surface

- **Public API** `/v1/forecast`, `/v1/air-quality`, `/v1/search` — KHÔNG có auth (Open-Meteo public design)
- **Sync containers** — `omfc-sync-gfs/ecmwf/aqi` kéo data từ S3 Open-Meteo mirror
- **`data/` folder** — `.om` files (forecast data, non-sensitive)

## Threat model

| Risk | Mitigation |
|---|---|
| DDoS public API | nginx 30r/s burst 60 + UFW + Cloudflare (khi có domain) |
| Sync abuse từ S3 mirror | Trust Open-Meteo S3 + HTTPS + retention `--past-days 1` |
| Container compromise (sync) | cap_drop ALL + no_new_privileges + non-root UID 999 |
| Data corruption | sync atomic rename + read-only API; backup script không cần (data re-fetchable) |
| Disk overflow | `data-directory-max-size-gb` flag + cleanup cron |

## Files NEVER commit

- `data/` (large GRIB cache, re-downloadable)
- `logs/`
- `*.pem`, `*.key`

## Public endpoint policy

Forecast API là public — KHÔNG cần token. Nhưng vẫn rate limit để chống abuse:
- nginx vhost 30r/s burst 60 per IP
- Cache layer 60s TTL → giảm load nếu nhiều client gọi cùng location

Mobile app gọi không cần header gì cả — chỉ HTTPS + URL param.

## Verification

```bash
# Public access OK
curl 'https://forecast-206-72-200-120.nip.io/v1/forecast?latitude=10.77&longitude=106.7&current=temperature_2m'

# Rate limit kicked in (200 req nhanh)
for i in {1..200}; do curl -s -o /dev/null -w "%{http_code}\n" "$URL"; done | sort | uniq -c
# Expect mostly 200, some 429
```

## Hardening checklist

- [x] nginx vhost với rate limit + security headers (`nginx/forecast-api.conf`)
- [x] Container non-root (Open-Meteo image UID 999)
- [x] cap_drop ALL + no_new_privileges
- [x] Bind 127.0.0.1:6968 (no public docker port)
- [x] Auto-update opt-in qua Watchtower label
- [x] `.gitignore` cho data/ + logs/

## See also

- `/Users/goodjob/mobile/doan/SECURITY.md` — cross-system policy
- `nginx/forecast-api.conf` — public-facing nginx config
