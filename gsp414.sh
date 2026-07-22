#!/usr/bin/env bash
# GSP414 - Creating Date-Partitioned Tables in BigQuery
# Jalankan di Cloud Shell: bash gsp414.sh
#
# Yang di-cover: Task 1, 2, 3, 5, 6 (semua Check my progress).
# Task 4 (explore NOAA data) hanya navigasi UI — tidak perlu dijalankan.
# Semua soal pilihan ganda tetap harus diklik manual.

set -euo pipefail

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
LOCATION="US"   # public dataset (data-to-insights, bigquery-public-data) ada di US

[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }
echo "Project: $PROJECT"

q() { # q "<judul>" "<sql>"
  echo
  echo "=============================================================="
  echo ">> $1"
  echo "=============================================================="
  bq --project_id="$PROJECT" --location="$LOCATION" query \
     --use_legacy_sql=false --format=pretty "$2"
}

# ---------------------------------------------------------------- Task 1
echo ">> Task 1: buat dataset ecommerce"
bq --project_id="$PROJECT" --location="$LOCATION" mk -f -d ecommerce

# ---------------------------------------------------------------- Task 2
q "Task 2: buat tabel ecommerce.partition_by_day (partition by date_formatted)" "
CREATE OR REPLACE TABLE \`$PROJECT.ecommerce.partition_by_day\`
PARTITION BY date_formatted
OPTIONS(
  description=\"a table partitioned by date\"
) AS
SELECT DISTINCT
  PARSE_DATE(\"%Y%m%d\", date) AS date_formatted,
  fullvisitorId
FROM \`data-to-insights.ecommerce.all_sessions_raw\`
"

# ---------------------------------------------------------------- Task 3
echo ">> Task 3: verifikasi partition_by_day"
q "Task 3a: query partition 2016-08-01 (harusnya ~25 KB)" "
SELECT *
FROM \`$PROJECT.ecommerce.partition_by_day\`
WHERE date_formatted = '2016-08-01'
"

q "Task 3b: query partition 2018-07-08 (harusnya 0 B karena tidak ada data 2018)" "
SELECT *
FROM \`$PROJECT.ecommerce.partition_by_day\`
WHERE date_formatted = '2018-07-08'
"

# ---------------------------------------------------------------- Task 5
# Task 4 cuma navigasi UI (explore NOAA dataset), skip.
# Task 5: buat tabel days_with_rain dari NOAA data
q "Task 5: buat tabel ecommerce.days_with_rain (partition + auto-expire 730d)" "
CREATE OR REPLACE TABLE \`$PROJECT.ecommerce.days_with_rain\`
PARTITION BY date
OPTIONS(
  partition_expiration_days=730,
  description=\"weather stations with precipitation, partitioned by day\"
) AS
SELECT
  DATE(CAST(year AS INT64), CAST(mo AS INT64), CAST(da AS INT64)) AS date,
  (SELECT ANY_VALUE(name) FROM \`bigquery-public-data.noaa_gsod.stations\` AS stations
   WHERE stations.usaf = stn) AS station_name,
  prcp
FROM \`bigquery-public-data.noaa_gsod.gsod*\` AS weather
WHERE prcp < 99.9
  AND prcp > 0
  AND _TABLE_SUFFIX >= '2018'
"

# ---------------------------------------------------------------- Task 6
echo ">> Task 6: verifikasi partition expiry"
q "Task 6: cek partition_age tertua (harusnya <= 730)" "
SELECT
  AVG(prcp) AS average,
  station_name,
  date,
  CURRENT_DATE() AS today,
  DATE_DIFF(CURRENT_DATE(), date, DAY) AS partition_age,
  EXTRACT(MONTH FROM date) AS month
FROM \`$PROJECT.ecommerce.days_with_rain\`
WHERE station_name = 'WAKAYAMA'
GROUP BY station_name, date, today, month, partition_age
ORDER BY partition_age DESC
"

echo
echo "Selesai. Sisa yang manual: semua soal pilihan ganda + Task 4 (navigate NOAA dataset di UI)."
