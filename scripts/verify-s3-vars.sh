#!/usr/bin/env bash
# Verify Open-Meteo S3 mirror có những variables raw nào cho mỗi model.
# Chạy TRƯỚC KHI restart sync với compose mới — đảm bảo tên var đúng.
#
# Usage:  ./scripts/verify-s3-vars.sh
# Output: bảng ✓/✗ + danh sách vars NOT FOUND để sửa compose

set -u

S3_BASE="https://openmeteo.s3.amazonaws.com/data"
# Probe nhiều chunks để tránh false-404 nếu chunk cụ thể chưa publish
CHUNKS_GFS=(1024 1025 1026 1027 1028 1029 1030)
CHUNKS_ECMWF=(1580 1582 1584 1586 1588 1590)
CHUNKS_CAMS=(2275 2278 2281 2284)

probe_var() {
  local model=$1; shift
  local var=$1; shift
  local chunks=("$@")
  for n in "${chunks[@]}"; do
    code=$(curl -s -o /dev/null -w "%{http_code}" -m 5 \
      "$S3_BASE/$model/$var/chunk_$n.om")
    [ "$code" = "200" ] && { echo "200 $n"; return 0; }
  done
  echo "404"
  return 1
}

check_model() {
  local model=$1; shift
  local chunks_var=$1; shift
  declare -n chunks_ref="$chunks_var"
  local vars=("$@")

  echo ""
  echo "════════════════════════════════════════════════════════════"
  echo " $model"
  echo "════════════════════════════════════════════════════════════"
  local ok=() bad=()
  for v in "${vars[@]}"; do
    res=$(probe_var "$model" "$v" "${chunks_ref[@]}")
    if [[ "$res" == 200* ]]; then
      printf "  \e[32m✓\e[0m %-35s (chunk_%s)\n" "$v" "${res#200 }"
      ok+=("$v")
    else
      printf "  \e[31m✗\e[0m %-35s NOT FOUND on S3\n" "$v"
      bad+=("$v")
    fi
  done
  echo ""
  echo "  Available (${#ok[@]}): $(IFS=,; echo "${ok[*]}")"
  if [ ${#bad[@]} -gt 0 ]; then
    echo "  ✗ Missing (${#bad[@]}): $(IFS=,; echo "${bad[*]}")"
    echo "    → Phải REMOVE khỏi compose 'command' hoặc thử tên khác."
  fi
}

# GFS — raw vars trong compose mới
GFS_VARS=(
  temperature_2m relative_humidity_2m precipitation
  snowfall_water_equivalent
  cloud_cover cloud_cover_low cloud_cover_mid cloud_cover_high
  shortwave_radiation uv_index
  wind_u_component_10m wind_v_component_10m
  wind_u_component_80m wind_v_component_80m
  wind_gusts_10m pressure_msl visibility cape freezing_level_height
  # Alternative naming (test fallback nếu primary 404)
  u_component_of_wind_10m v_component_of_wind_10m
  wind_10m_u wind_10m_v
)
check_model ncep_gfs013 CHUNKS_GFS "${GFS_VARS[@]}"

# ECMWF — raw vars trong compose mới
ECMWF_VARS=(
  temperature_2m dewpoint_2m precipitation snowfall_water_equivalent
  cloud_cover_low cloud_cover_mid cloud_cover_high
  wind_u_component_10m wind_v_component_10m
  wind_u_component_100m wind_v_component_100m
  wind_gusts_10m pressure_msl
  # Alternatives
  u_component_of_wind_10m v_component_of_wind_10m
)
check_model ecmwf_ifs025 CHUNKS_ECMWF "${ECMWF_VARS[@]}"

# CAMS — xác nhận đã sync đúng
CAMS_VARS=(
  pm2_5 pm10 carbon_monoxide nitrogen_dioxide
  ozone sulphur_dioxide dust aerosol_optical_depth uv_index
)
check_model cams_global CHUNKS_CAMS "${CAMS_VARS[@]}"

echo ""
echo "════════════════════════════════════════════════════════════"
echo " HƯỚNG DẪN"
echo "════════════════════════════════════════════════════════════"
echo " 1. Vars có dấu ✓ → giữ trong docker-compose.yml 'command'"
echo " 2. Vars có dấu ✗ → REMOVE khỏi compose (binary sẽ skip im lặng,"
echo "    nhưng API trả null cho derived vars phụ thuộc)"
echo " 3. Nếu wind_u_component_10m ✗ nhưng u_component_of_wind_10m ✓"
echo "    → đổi naming trong compose cho khớp."
echo " 4. Sau khi sửa compose, restart:"
echo "      docker compose restart sync-gfs sync-ecmwf"
